#!/usr/bin/env python3
"""
Bulk ETL: DrJaw legacy sales JSON → Supabase public.sales_history + Storage (WebP).

Historical field mapping (same source as sync.js / SUITE_DATABASE_INFO.md):
  Items.Id      → legacy_id  (PK экземпляра, upsert key; products.id в sync)
  Items.Articul → sku        (артикул экземпляра)
  Items.Price   → price_krw  (целые KRW, как parsePriceKrw в sync.js)
  Items.CartId  → sold_at_utc / sold_date_kst (YYYYMMDDHHmmss + суффикс магазина, KST)
  Items.Status, Mart, Manager → migration_meta (аудит)
  Фото: URL в JSON или LEGACY_IMAGE_BASE_URL + Articul (как product-images/{sku}.webp)

pip install -r migration/requirements.txt

Run from repo root:
  python migration/etl_sales_migration.py

Env: migration/.env (preferred) or project root .env
"""

from __future__ import annotations

import io
import json
import logging
import os
import re
import sys
import uuid
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import requests
from dotenv import load_dotenv
from PIL import Image, UnidentifiedImageError
from supabase import Client, create_client

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
LOG_PATH = SCRIPT_DIR / "migration_errors.log"
CHECKPOINT_PATH = SCRIPT_DIR / ".migration_checkpoint.json"
KST = ZoneInfo("Asia/Seoul")
ETL_VERSION = "1.2.0-drjaw-mssql-blob"

# DrJaw Items.* (PascalCase из MSSQL / legacy API) — приоритет как в sync.js
LEGACY_ID_KEYS = ("Id", "id", "ID", "legacy_id", "item_id", "ItemsId")
SKU_KEYS = ("Articul", "articul", "SKU", "sku")
PRICE_KEYS = ("Price", "price", "price_krw", "sale_price", "sale_price_krw")
DATE_FIELD_KEYS = (
    "SoldDate",
    "sold_date",
    "sold_at",
    "sale_date",
    "transaction_date",
    "Date",
    "date",
    "updated_at",
    "UpdatedAt",
)
CART_ID_KEYS = ("CartId", "cart_id", "CartID")
IMAGE_URL_KEYS = (
    "image_url",
    "imageUrl",
    "ImageUrl",
    "photo_url",
    "primary_image_url",
    "picture_url",
)


PHOTO_SUCCESS = "success"
PHOTO_UPLOADED = "uploaded"
PHOTO_MISSING_BLOB = "missing_blob"
PHOTO_MISSING_URL = "missing_url"
PHOTO_DOWNLOAD_FAILED = "download_failed"
PHOTO_INVALID_IMAGE = "invalid_image"
PHOTO_UPLOAD_FAILED = "upload_failed"
PHOTO_TOO_LARGE = "too_large"


def setup_logging() -> logging.Logger:
    logger = logging.getLogger("sales_migration")
    logger.setLevel(logging.DEBUG)
    fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")

    fh = logging.FileHandler(LOG_PATH, encoding="utf-8")
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(fmt)

    sh = logging.StreamHandler(sys.stdout)
    sh.setLevel(logging.INFO)
    sh.setFormatter(fmt)

    if not logger.handlers:
        logger.addHandler(fh)
        logger.addHandler(sh)
    return logger


def is_env_placeholder(val: str) -> bool:
    if not val:
        return True
    lowered = val.lower()
    if "insert_" in lowered or val.endswith("_here"):
        return True
    if lowered in ("https://supabase.co", "https://your-project.supabase.co"):
        return True
    if "your-old-api" in lowered:
        return True
    return False


def json_safe_value(value: Any) -> Any:
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    if isinstance(value, bytes):
        return f"<bytes {len(value)}>"
    if isinstance(value, dict):
        return {str(k): json_safe_value(v) for k, v in value.items()}
    if isinstance(value, list):
        return [json_safe_value(v) for v in value]
    return value


def load_config(logger: logging.Logger) -> dict[str, Any]:
    load_dotenv(SCRIPT_DIR / ".env")
    load_dotenv(REPO_ROOT / ".env", override=True)

    url = os.getenv("SUPABASE_URL", "").strip()
    service_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    old_api_url = os.getenv("OLD_API_URL", "").strip()
    old_api_key = os.getenv("OLD_API_KEY", "").strip()

    sales_source = os.getenv("SALES_SOURCE", "").strip().lower()
    if sales_source not in ("api", "mssql"):
        sales_source = "mssql" if is_env_placeholder(old_api_url) else "api"

    missing = [
        name
        for name, val in (
            ("SUPABASE_URL", url),
            ("SUPABASE_SERVICE_ROLE_KEY", service_key),
        )
        if is_env_placeholder(val)
    ]
    if sales_source == "api":
        missing.extend(
            name
            for name, val in (
                ("OLD_API_URL", old_api_url),
                ("OLD_API_KEY", old_api_key),
            )
            if is_env_placeholder(val)
        )
    if missing:
        logger.error(
            "Fill migration/.env (or root .env): missing/placeholder %s",
            ", ".join(missing),
        )
        sys.exit(1)

    legacy_image_base_url = os.getenv("LEGACY_IMAGE_BASE_URL", "").strip()
    if not legacy_image_base_url and url and not is_env_placeholder(url):
        legacy_image_base_url = f"{url.rstrip('/')}/storage/v1/object/public"

    return {
        "supabase_url": url,
        "supabase_service_key": service_key,
        "sales_source": sales_source,
        "old_api_url": old_api_url,
        "old_api_key": old_api_key,
        "old_api_key_header": os.getenv("OLD_API_KEY_HEADER", "Authorization").strip(),
        "old_api_key_prefix": os.getenv("OLD_API_KEY_PREFIX", "Bearer").strip(),
        "page_limit": int(os.getenv("OLD_API_PAGE_LIMIT", "200")),
        "bucket": os.getenv("SUPABASE_STORAGE_BUCKET", "product-images").strip(),
        "storage_prefix": os.getenv("SUPABASE_STORAGE_PREFIX", "sales_history").strip(),
        "webp_quality": int(os.getenv("WEBP_QUALITY", "80")),
        "http_timeout": int(os.getenv("HTTP_TIMEOUT_SEC", "60")),
        "image_max_bytes": int(os.getenv("IMAGE_MAX_BYTES", str(15 * 1024 * 1024))),
        "legacy_image_base_url": legacy_image_base_url,
        "pilot_mode": os.getenv("MIGRATION_PILOT", "0").strip().lower()
        in ("1", "true", "yes"),
        "mssql_host": os.getenv("MSSQL_HOST", "211.176.43.226").strip(),
        "mssql_port": int(os.getenv("MSSQL_PORT", "1433")),
        "mssql_user": os.getenv("MSSQL_USER", "DrJ_Reader").strip(),
        "mssql_password": os.getenv("MSSQL_PASSWORD", "Read_only11!"),
        "mssql_database": os.getenv("MSSQL_DATABASE", "DrJaw").strip(),
    }


def first_present(record: dict[str, Any], keys: tuple[str, ...]) -> Any:
    for key in keys:
        if key in record and record[key] is not None:
            return record[key]
        for rk, rv in record.items():
            if rk.lower() == key.lower() and rv is not None:
                return rv
    return None


def parse_legacy_id(record: dict[str, Any]) -> str | None:
    """DrJaw: Items.Id (строка для upsert, как products.id в sync.js)."""
    raw = first_present(record, LEGACY_ID_KEYS)
    if raw is None:
        return None
    text = str(raw).strip()
    return text or None


def parse_sku(record: dict[str, Any]) -> str | None:
    """DrJaw: Items.Articul → products.sku."""
    raw = first_present(record, SKU_KEYS)
    if raw is None:
        return None
    text = str(raw).strip()
    return text or None


def parse_cart_id_timestamp(cart_id: Any) -> datetime | None:
    """
    DrJaw Items.CartId: YYYYMMDDHHmmss + опциональный суффикс точки (scripts/probe-sold-date.js).
    Время трактуем как Asia/Seoul → UTC.
    """
    if cart_id is None:
        return None
    text = str(cart_id).strip()
    match = re.match(r"^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})", text)
    if not match:
        return None
    y, mo, d, h, mi, s = (int(g) for g in match.groups())
    try:
        local = datetime(y, mo, d, h, mi, s, tzinfo=KST)
    except ValueError:
        return None
    return local.astimezone(timezone.utc)


def parse_sold_moment(record: dict[str, Any]) -> tuple[datetime | None, str]:
    """Возвращает (sold_at_utc, sold_at_source)."""
    for key in DATE_FIELD_KEYS:
        raw = first_present(record, (key,))
        if raw is None:
            continue
        parsed = parse_transaction_utc(raw)
        if parsed is not None:
            return parsed, f"field:{key}"

    cart_raw = first_present(record, CART_ID_KEYS)
    parsed_cart = parse_cart_id_timestamp(cart_raw)
    if parsed_cart is not None:
        return parsed_cart, "cart_id"

    return None, "unknown"


def safe_storage_sku(articul: str) -> str:
    """Как sync.js: sanitize Articul для пути Storage."""
    return re.sub(r"[^\w.-]+", "_", articul.strip())


def resolve_legacy_image_url(record: dict[str, Any], cfg: dict[str, Any]) -> str | None:
    direct = first_present(record, IMAGE_URL_KEYS)
    if direct is not None and str(direct).strip():
        return str(direct).strip()

    base = cfg.get("legacy_image_base_url") or ""
    sku = parse_sku(record)
    if base and sku:
        safe = safe_storage_sku(sku)
        return f"{base.rstrip('/')}/product-images/{safe}.webp"
    return None


def parse_price_krw(value: Any) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return max(value, 0)
    if isinstance(value, float):
        return max(int(round(value)), 0)
    text = str(value).strip()
    if not text:
        return None
    text = re.sub(r"[^\d.\-]", "", text.replace(",", ""))
    if not text:
        return None
    try:
        dec = Decimal(text)
    except InvalidOperation:
        return None
    return max(int(dec.to_integral_value()), 0)


def parse_transaction_utc(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        ts = float(value)
        if ts > 1e12:
            ts /= 1000.0
        return datetime.fromtimestamp(ts, tz=timezone.utc)
    text = str(value).strip()
    if not text:
        return None
    if text.isdigit():
        ts = int(text)
        if ts > 1_000_000_000_000:
            ts //= 1000
        return datetime.fromtimestamp(ts, tz=timezone.utc)
    normalized = text.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(normalized)
    except ValueError:
        for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d", "%Y/%m/%d %H:%M:%S", "%Y/%m/%d"):
            try:
                dt = datetime.strptime(text, fmt)
                break
            except ValueError:
                dt = None
        if dt is None:
            return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=KST)
    return dt.astimezone(timezone.utc)


def sold_date_kst_from_utc(dt_utc: datetime) -> str:
    return dt_utc.astimezone(KST).date().isoformat()


def legacy_auth_headers(cfg: dict[str, Any]) -> dict[str, str]:
    header = cfg["old_api_key_header"]
    prefix = cfg["old_api_key_prefix"]
    token = cfg["old_api_key"]
    value = f"{prefix} {token}".strip() if prefix else token
    return {header: value, "Accept": "application/json"}


def extract_records(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, list):
        return [dict(x) for x in payload if isinstance(x, dict)]
    if not isinstance(payload, dict):
        return []
    for key in ("data", "items", "results", "sales", "records", "rows"):
        chunk = payload.get(key)
        if isinstance(chunk, list):
            return [dict(x) for x in chunk if isinstance(x, dict)]
    return []


_MSSQL_CONN: Any = None

SALES_HISTORY_MSSQL_BATCH = """
SELECT
  i.Id,
  i.Articul,
  i.Price,
  i.Weight,
  i.Size,
  i.Stones,
  i.Status,
  i.Mart,
  i.Manager,
  i.CartId
FROM dbo.Items AS i
WHERE i.CartId IS NOT NULL AND LTRIM(RTRIM(i.CartId)) <> ''
ORDER BY i.Id
OFFSET %s ROWS FETCH NEXT %s ROWS ONLY
"""

MSSQL_IMAGE_BY_ITEM_ID = """
SELECT a.Image AS Image
FROM dbo.Items AS i
INNER JOIN dbo.Articuls AS a ON i.Articul = a.Articul
WHERE i.Id = %s
"""


def parse_item_id(legacy_id: str) -> int | str:
    text = str(legacy_id).strip()
    if text.isdigit():
        return int(text)
    return text


def fetch_mssql_image_blob(
    cfg: dict[str, Any],
    legacy_id: str,
    logger: logging.Logger,
) -> bytes | None:
    item_id = parse_item_id(legacy_id)
    try:
        conn = get_mssql_connection(cfg)
        cursor = conn.cursor()
        cursor.execute(MSSQL_IMAGE_BY_ITEM_ID, (item_id,))
        row = cursor.fetchone()
        cursor.close()
    except Exception as exc:
        logger.error("legacy_id=%s MSSQL Image read failed: %s", legacy_id, exc)
        return None

    if not row or row[0] is None:
        return None
    blob = row[0]
    if isinstance(blob, memoryview):
        blob = blob.tobytes()
    if isinstance(blob, bytes) and len(blob) > 0:
        return blob
    return None


def get_mssql_connection(cfg: dict[str, Any]):
    global _MSSQL_CONN
    if _MSSQL_CONN is not None:
        return _MSSQL_CONN
    import pymssql

    _MSSQL_CONN = pymssql.connect(
        server=cfg["mssql_host"],
        port=cfg["mssql_port"],
        user=cfg["mssql_user"],
        password=cfg["mssql_password"],
        database=cfg["mssql_database"],
        login_timeout=30,
        timeout=120,
    )
    return _MSSQL_CONN


def fetch_legacy_batch_mssql(
    cfg: dict[str, Any],
    offset: int,
    logger: logging.Logger,
) -> list[dict[str, Any]]:
    limit = cfg["page_limit"]
    try:
        conn = get_mssql_connection(cfg)
        cursor = conn.cursor(as_dict=True)
        cursor.execute(SALES_HISTORY_MSSQL_BATCH, (offset, limit))
        rows = cursor.fetchall()
        cursor.close()
    except Exception as exc:
        logger.error("MSSQL batch offset=%s failed: %s", offset, exc)
        raise

    records: list[dict[str, Any]] = []
    for row in rows or []:
        if not isinstance(row, dict):
            continue
        record = {str(k): json_safe_value(v) for k, v in row.items()}
        records.append(record)
    logger.info("Fetched MSSQL DrJaw batch offset=%s count=%s", offset, len(records))
    return records


def fetch_legacy_batch(
    session: requests.Session,
    cfg: dict[str, Any],
    offset: int,
    logger: logging.Logger,
) -> list[dict[str, Any]]:
    limit = cfg["page_limit"]
    params = {"limit": limit, "offset": offset}
    try:
        resp = session.get(
            cfg["old_api_url"],
            params=params,
            timeout=cfg["http_timeout"],
        )
        resp.raise_for_status()
    except requests.RequestException as exc:
        logger.error("Legacy API offset=%s failed: %s", offset, exc)
        raise

    try:
        body = resp.json()
    except json.JSONDecodeError as exc:
        logger.error("Legacy API offset=%s invalid JSON: %s", offset, exc)
        raise

    records = extract_records(body)
    logger.info("Fetched legacy batch offset=%s count=%s", offset, len(records))
    return records


def download_image_bytes(
    session: requests.Session,
    url: str,
    cfg: dict[str, Any],
    logger: logging.Logger,
    legacy_id: str,
) -> tuple[bytes | None, str | None]:
    try:
        resp = session.get(url, timeout=cfg["http_timeout"], stream=True)
        resp.raise_for_status()
        data = resp.content
    except requests.RequestException as exc:
        logger.warning("legacy_id=%s image download failed: %s", legacy_id, exc)
        return None, PHOTO_DOWNLOAD_FAILED

    if len(data) > cfg["image_max_bytes"]:
        logger.warning("legacy_id=%s image too large (%s bytes)", legacy_id, len(data))
        return None, PHOTO_TOO_LARGE
    if not data:
        return None, PHOTO_DOWNLOAD_FAILED
    return data, None


def to_webp_bytes(raw: bytes, quality: int, logger: logging.Logger, legacy_id: str) -> bytes | None:
    try:
        with Image.open(io.BytesIO(raw)) as img:
            img.load()
            if img.mode not in ("RGB", "RGBA"):
                img = img.convert("RGBA" if "A" in img.getbands() else "RGB")
            elif img.mode == "RGBA":
                background = Image.new("RGB", img.size, (255, 255, 255))
                background.paste(img, mask=img.split()[3])
                img = background
            out = io.BytesIO()
            img.save(out, format="WEBP", quality=quality, method=4)
            return out.getvalue()
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        logger.warning("legacy_id=%s WebP convert failed: %s", legacy_id, exc)
        return None


def upload_webp(
    supabase: Client,
    cfg: dict[str, Any],
    legacy_id: str,
    webp_bytes: bytes,
    logger: logging.Logger,
) -> tuple[str | None, str | None]:
    object_path = f"{cfg['storage_prefix']}/{legacy_id}.webp"
    bucket = cfg["bucket"]
    try:
        supabase.storage.from_(bucket).upload(
            object_path,
            webp_bytes,
            file_options={"content-type": "image/webp", "upsert": "true"},
        )
        public_url = supabase.storage.from_(bucket).get_public_url(object_path)
        return public_url, None
    except Exception as exc:
        logger.error("legacy_id=%s storage upload failed: %s", legacy_id, exc)
        return None, PHOTO_UPLOAD_FAILED


def process_photo_from_mssql_blob(
    supabase: Client,
    cfg: dict[str, Any],
    legacy_id: str,
    logger: logging.Logger,
) -> tuple[str | None, str]:
    raw = fetch_mssql_image_blob(cfg, legacy_id, logger)
    if raw is None:
        return None, PHOTO_MISSING_BLOB
    if len(raw) > cfg["image_max_bytes"]:
        logger.warning("legacy_id=%s MSSQL blob too large (%s bytes)", legacy_id, len(raw))
        return None, PHOTO_TOO_LARGE

    webp = to_webp_bytes(raw, cfg["webp_quality"], logger, legacy_id)
    if webp is None:
        return None, PHOTO_INVALID_IMAGE

    public_url, upload_err = upload_webp(supabase, cfg, legacy_id, webp, logger)
    if public_url is None:
        return None, upload_err or PHOTO_UPLOAD_FAILED
    return public_url, PHOTO_SUCCESS


def process_photo_http(
    session: requests.Session,
    supabase: Client,
    cfg: dict[str, Any],
    record: dict[str, Any],
    legacy_id: str,
    logger: logging.Logger,
) -> tuple[str | None, str]:
    url = resolve_legacy_image_url(record, cfg)
    if url is None:
        return None, PHOTO_MISSING_URL
    raw, err = download_image_bytes(session, url, cfg, logger, legacy_id)
    if raw is None:
        return None, err or PHOTO_DOWNLOAD_FAILED

    webp = to_webp_bytes(raw, cfg["webp_quality"], logger, legacy_id)
    if webp is None:
        return None, PHOTO_INVALID_IMAGE

    public_url, upload_err = upload_webp(supabase, cfg, legacy_id, webp, logger)
    if public_url is None:
        return None, upload_err or PHOTO_UPLOAD_FAILED
    return public_url, PHOTO_UPLOADED


def process_photo(
    session: requests.Session,
    supabase: Client,
    cfg: dict[str, Any],
    record: dict[str, Any],
    legacy_id: str,
    logger: logging.Logger,
) -> tuple[str | None, str]:
    if cfg.get("sales_source") == "mssql":
        return process_photo_from_mssql_blob(supabase, cfg, legacy_id, logger)
    return process_photo_http(session, supabase, cfg, record, legacy_id, logger)


def build_row(
    record: dict[str, Any],
    legacy_id: str,
    import_batch_id: str,
    image_url: str | None,
    photo_status: str,
    cfg: dict[str, Any],
) -> dict[str, Any]:
    sold_at_utc, sold_at_source = parse_sold_moment(record)
    sold_date_kst = sold_date_kst_from_utc(sold_at_utc) if sold_at_utc else None

    price_raw = first_present(record, PRICE_KEYS)
    price_krw = parse_price_krw(price_raw)

    sku = parse_sku(record)
    cart_id = first_present(record, CART_ID_KEYS)

    migration_meta: dict[str, Any] = {
        "etl_version": ETL_VERSION,
        "source_system": "DrJaw",
        "field_mapping": {
            "legacy_id": "Items.Id",
            "sku": "Items.Articul",
            "price_krw": "Items.Price",
            "sold_at": sold_at_source,
        },
        "sold_at_source": sold_at_source,
        "cart_id": str(cart_id).strip() if cart_id is not None else None,
        "status": first_present(record, ("Status", "status")),
        "mart": first_present(record, ("Mart", "mart")),
        "manager": first_present(record, ("Manager", "manager")),
        "photo_status": photo_status,
        "legacy_image_resolved_from": (
            "mssql_articuls_image_blob"
            if cfg.get("sales_source") == "mssql"
            else (
                "direct_url"
                if first_present(record, IMAGE_URL_KEYS)
                else ("articul_path" if cfg.get("legacy_image_base_url") and sku else None)
            )
        ),
    }

    row: dict[str, Any] = {
        "legacy_id": legacy_id,
        "sku": sku,
        "price_krw": price_krw,
        "sold_at_utc": sold_at_utc.isoformat() if sold_at_utc else None,
        "sold_date_kst": sold_date_kst,
        "image_url": image_url,
        "photo_status": photo_status,
        "import_batch_id": import_batch_id,
        "raw_legacy_payload": record,
        "migration_meta": migration_meta,
    }
    return row


def upsert_batch(supabase: Client, rows: list[dict[str, Any]], logger: logging.Logger) -> None:
    if not rows:
        return
    try:
        supabase.table("sales_history").upsert(rows, on_conflict="legacy_id").execute()
        logger.info("Upserted %s rows into sales_history", len(rows))
    except Exception as exc:
        logger.error("Supabase upsert failed (%s rows): %s", len(rows), exc)
        for row in rows:
            logger.error("  failed legacy_id=%s", row.get("legacy_id"))
        raise


def read_checkpoint() -> int:
    if not CHECKPOINT_PATH.exists():
        return 0
    try:
        data = json.loads(CHECKPOINT_PATH.read_text(encoding="utf-8"))
        return int(data.get("offset", 0))
    except (json.JSONDecodeError, OSError, ValueError):
        return 0


def write_checkpoint(offset: int) -> None:
    CHECKPOINT_PATH.write_text(
        json.dumps({"offset": offset, "updated_at": datetime.now(timezone.utc).isoformat()}),
        encoding="utf-8",
    )


def run_migration() -> None:
    logger = setup_logging()
    cfg = load_config(logger)
    import_batch_id = str(uuid.uuid4())
    pilot = cfg["pilot_mode"]
    logger.info(
        "Starting sales_history migration batch_id=%s pilot=%s source=%s",
        import_batch_id,
        pilot,
        cfg["sales_source"],
    )

    supabase: Client = create_client(cfg["supabase_url"], cfg["supabase_service_key"])
    session = requests.Session()
    session.headers.update(legacy_auth_headers(cfg))

    offset = 0 if pilot else read_checkpoint()
    limit = cfg["page_limit"]
    pending_upsert: list[dict[str, Any]] = []
    total_processed = 0
    total_skipped = 0
    batch_number = 0

    logger.info(
        "Full migration mode: checkpoint_offset=%s page_limit=%s pilot=%s",
        offset,
        limit,
        pilot,
    )

    while True:
        try:
            if cfg["sales_source"] == "mssql":
                batch = fetch_legacy_batch_mssql(cfg, offset, logger)
            else:
                batch = fetch_legacy_batch(session, cfg, offset, logger)
        except Exception:
            logger.error("Stopping at offset=%s due to fetch error", offset)
            break

        if not batch:
            logger.info("No more records at offset=%s — done.", offset)
            break

        for record in batch:
            legacy_id = parse_legacy_id(record)
            if legacy_id is None:
                total_skipped += 1
                logger.error("Skip row without Items.Id: %s", json.dumps(record)[:500])
                continue

            try:
                stored_image_url, photo_status = process_photo(
                    session, supabase, cfg, record, legacy_id, logger
                )
                row = build_row(
                    record,
                    legacy_id,
                    import_batch_id,
                    stored_image_url,
                    photo_status,
                    cfg,
                )
                pending_upsert.append(row)
                total_processed += 1

                if len(pending_upsert) >= limit:
                    upsert_batch(supabase, pending_upsert, logger)
                    pending_upsert.clear()
            except Exception as exc:
                total_skipped += 1
                logger.exception("legacy_id=%s processing failed: %s", legacy_id, exc)

        if pending_upsert:
            upsert_batch(supabase, pending_upsert, logger)
            pending_upsert.clear()

        batch_number += 1
        offset += len(batch)
        if not pilot:
            write_checkpoint(offset)

        bar_width = 24
        filled = min(bar_width, batch_number)
        progress_bar = ("#" * filled).ljust(bar_width, "-")
        logger.info(
            "[PROGRESS] [%s] batch=%s rows=%s cumulative=%s next_offset=%s skipped=%s",
            progress_bar,
            batch_number,
            len(batch),
            total_processed,
            offset,
            total_skipped,
        )

        if pilot:
            logger.info(
                "ПИЛОТНЫЙ ПРОГОН НА 200 СТРОК ЗАВЕРШЕН. "
                "Проверьте данные в дашборде Supabase"
            )
            break

        if len(batch) < limit:
            break

    logger.info(
        "Migration finished. processed=%s skipped=%s last_offset=%s log=%s",
        total_processed,
        total_skipped,
        offset,
        LOG_PATH,
    )


if __name__ == "__main__":
    run_migration()
