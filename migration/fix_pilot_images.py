#!/usr/bin/env python3
"""
Retry photos for pilot batch: MSSQL Articuls.Image → WebP → sales_history/{legacy_id}.webp

python migration/fix_pilot_images.py
"""

from __future__ import annotations

import io
import logging
import os
import sys
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from PIL import Image, UnidentifiedImageError
from supabase import Client, create_client

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
LOG_PATH = SCRIPT_DIR / "fix_pilot_images.log"

MSSQL_IMAGE_BY_ITEM_ID = """
SELECT a.Image AS Image
FROM dbo.Items AS i
INNER JOIN dbo.Articuls AS a ON i.Articul = a.Articul
WHERE i.Id = %s
"""

PHOTO_STATUS_FAILED = "download_failed"
PHOTO_STATUS_SUCCESS = "success"


def setup_logging() -> logging.Logger:
    logger = logging.getLogger("fix_pilot_images")
    logger.setLevel(logging.DEBUG)
    fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
    fh = logging.FileHandler(LOG_PATH, encoding="utf-8")
    fh.setFormatter(fmt)
    sh = logging.StreamHandler(sys.stdout)
    sh.setFormatter(fmt)
    if not logger.handlers:
        logger.addHandler(fh)
        logger.addHandler(sh)
    return logger


def is_env_placeholder(val: str) -> bool:
    if not val:
        return True
    lowered = val.lower()
    return "insert_" in lowered or val.endswith("_here") or lowered == "https://supabase.co"


def load_config(logger: logging.Logger) -> dict[str, Any]:
    load_dotenv(SCRIPT_DIR / ".env")
    load_dotenv(REPO_ROOT / ".env", override=True)

    url = os.getenv("SUPABASE_URL", "").strip()
    service_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if is_env_placeholder(url) or is_env_placeholder(service_key):
        logger.error("Configure SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in root .env")
        sys.exit(1)

    return {
        "supabase_url": url,
        "supabase_service_key": service_key,
        "bucket": os.getenv("SUPABASE_STORAGE_BUCKET", "product-images").strip(),
        "storage_prefix": os.getenv("SUPABASE_STORAGE_PREFIX", "sales_history").strip(),
        "webp_quality": int(os.getenv("WEBP_QUALITY", "80")),
        "mssql_host": os.getenv("MSSQL_HOST", "211.176.43.226").strip(),
        "mssql_port": int(os.getenv("MSSQL_PORT", "1433")),
        "mssql_user": os.getenv("MSSQL_USER", "DrJ_Reader").strip(),
        "mssql_password": os.getenv("MSSQL_PASSWORD", "Read_only11!"),
        "mssql_database": os.getenv("MSSQL_DATABASE", "DrJaw").strip(),
    }


def to_webp(raw: bytes, quality: int, logger: logging.Logger, legacy_id: str) -> bytes | None:
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


def parse_item_id(legacy_id: str) -> int | str:
    text = str(legacy_id).strip()
    if text.isdigit():
        return int(text)
    return text


def fetch_mssql_image_blob(cfg: dict[str, Any], legacy_id: str, logger: logging.Logger) -> bytes | None:
    import pymssql

    item_id = parse_item_id(legacy_id)
    try:
        conn = pymssql.connect(
            server=cfg["mssql_host"],
            port=cfg["mssql_port"],
            user=cfg["mssql_user"],
            password=cfg["mssql_password"],
            database=cfg["mssql_database"],
            login_timeout=30,
            timeout=120,
        )
        cursor = conn.cursor()
        cursor.execute(MSSQL_IMAGE_BY_ITEM_ID, (item_id,))
        row = cursor.fetchone()
        cursor.close()
        conn.close()
    except Exception as exc:
        logger.error("legacy_id=%s MSSQL read failed: %s", legacy_id, exc)
        return None

    if not row or row[0] is None:
        return None
    blob = row[0]
    if isinstance(blob, memoryview):
        blob = blob.tobytes()
    if isinstance(blob, bytes) and len(blob) > 0:
        return blob
    return None


def fetch_failed_rows(supabase: Client, logger: logging.Logger) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    page_size = 1000
    offset = 0
    while True:
        end = offset + page_size - 1
        response = (
            supabase.table("sales_history")
            .select("legacy_id, sku, photo_status")
            .eq("photo_status", PHOTO_STATUS_FAILED)
            .order("legacy_id")
            .range(offset, end)
            .execute()
        )
        chunk = response.data or []
        if not chunk:
            break
        rows.extend(chunk)
        logger.info("Loaded failed rows chunk offset=%s count=%s total=%s", offset, len(chunk), len(rows))
        if len(chunk) < page_size:
            break
        offset += page_size
    return rows


def upload_and_patch(
    supabase: Client,
    cfg: dict[str, Any],
    legacy_id: str,
    webp_bytes: bytes,
    logger: logging.Logger,
) -> str | None:
    object_path = f"{cfg['storage_prefix']}/{legacy_id}.webp"
    try:
        supabase.storage.from_(cfg["bucket"]).upload(
            object_path,
            webp_bytes,
            file_options={"content-type": "image/webp", "upsert": "true"},
        )
        public_url = supabase.storage.from_(cfg["bucket"]).get_public_url(object_path)
        supabase.table("sales_history").update(
            {
                "photo_status": PHOTO_STATUS_SUCCESS,
                "image_url": public_url,
            }
        ).eq("legacy_id", legacy_id).execute()
        return public_url
    except Exception as exc:
        logger.error("legacy_id=%s upload/update failed: %s", legacy_id, exc)
        return None


def main() -> None:
    logger = setup_logging()
    cfg = load_config(logger)
    supabase = create_client(cfg["supabase_url"], cfg["supabase_service_key"])

    failed_rows = fetch_failed_rows(supabase, logger)
    logger.info("Rows with photo_status=%s: %s", PHOTO_STATUS_FAILED, len(failed_rows))

    restored = 0
    no_blob = 0
    convert_failed = 0
    upload_failed = 0

    for index, row in enumerate(failed_rows, start=1):
        legacy_id = str(row.get("legacy_id", "")).strip()
        if not legacy_id:
            continue

        raw = fetch_mssql_image_blob(cfg, legacy_id, logger)
        if raw is None:
            no_blob += 1
            logger.warning("[%s/%s] legacy_id=%s no Articuls.Image blob", index, len(failed_rows), legacy_id)
            continue

        webp = to_webp(raw, cfg["webp_quality"], logger, legacy_id)
        if webp is None:
            convert_failed += 1
            continue

        url = upload_and_patch(supabase, cfg, legacy_id, webp, logger)
        if url is None:
            upload_failed += 1
            continue

        restored += 1
        if restored % 20 == 0 or index == len(failed_rows):
            logger.info("Progress: restored=%s / target=%s", restored, len(failed_rows))

    logger.info(
        "Fix pilot images done. target=%s restored=%s no_blob=%s convert_failed=%s upload_failed=%s",
        len(failed_rows),
        restored,
        no_blob,
        convert_failed,
        upload_failed,
    )


if __name__ == "__main__":
    main()
