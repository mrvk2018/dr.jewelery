#!/usr/bin/env python3
"""
Инкрементальный доимпорт продаж DrJaw → sales_history (Items + Cart Sold).

  python migration/incremental_drjaw_sales.py --dry-run --month 2026-11
  python migration/incremental_drjaw_sales.py --month 2026-11

- Не дублирует legacy_id = Items.Id и не вставляет, если есть pwa_id_{Items.Id}.
- Дозаполняет seller_name / payment_method у pwa_id_* из Cart при NULL.
- Новые строки: legacy_id = Items.Id (число), sold_date_kst из Cart.PurshaseDate.
"""

from __future__ import annotations

import argparse
import calendar
import json
import logging
import re
import sys
import uuid
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any
from dotenv import load_dotenv
from supabase import Client, create_client

from enrich_sales_from_mssql import (
    PURSHASE_TYPE_TO_PAYMENT,
    classify_metal_category,
    list_price_from_sale,
    merge_payload,
    parse_bonus,
    parse_weight,
    resolve_store_from_mart,
    map_purshase_source_to_seller,
    map_purshase_type_to_payment,
)

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
KST = timezone(timedelta(hours=9))
LOG_PATH = SCRIPT_DIR / "incremental_drjaw_sales.log"

MSSQL_SOLD_SELECT = """
SELECT
  CAST(i.Id AS VARCHAR(32)) AS legacy_id,
  i.Articul AS sku,
  i.Price,
  i.Weight,
  i.Mart,
  i.Manager,
  i.CartId,
  i.Bonus,
  i.Comment,
  a.Metall,
  a.Type,
  c.PurshaseDate,
  c.PurshaseSource,
  c.PurshaseType
FROM dbo.Items AS i
INNER JOIN dbo.Cart AS c
  ON c.CartId = i.CartId AND c.OperationType = N'Sold' AND i.Status = N'Sold'
LEFT JOIN dbo.Articuls AS a ON a.Articul = i.Articul
WHERE CAST(c.PurshaseDate AS DATE) >= %s
  AND CAST(c.PurshaseDate AS DATE) <= %s
ORDER BY c.PurshaseDate ASC, i.Id ASC
"""


def setup_logging() -> logging.Logger:
    logger = logging.getLogger("incremental_drjaw")
    logger.setLevel(logging.DEBUG)
    fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
    fh = logging.FileHandler(LOG_PATH, encoding="utf-8")
    fh.setFormatter(fmt)
    sh = logging.StreamHandler(sys.stdout)
    sh.setLevel(logging.INFO)
    sh.setFormatter(fmt)
    if not logger.handlers:
        logger.addHandler(fh)
        logger.addHandler(sh)
    return logger


def load_cfg() -> dict[str, Any]:
    import os

    load_dotenv(SCRIPT_DIR / ".env")
    load_dotenv(REPO_ROOT / ".env", override=True)
    return {
        "mssql_host": os.getenv("MSSQL_HOST", "211.176.43.226").strip(),
        "mssql_port": int(os.getenv("MSSQL_PORT", "1433")),
        "mssql_user": os.getenv("MSSQL_USER", "DrJ_Reader").strip(),
        "mssql_password": os.getenv("MSSQL_PASSWORD", "Read_only11!"),
        "mssql_database": os.getenv("MSSQL_DATABASE", "DrJaw").strip(),
        "supabase_url": os.getenv("SUPABASE_URL", "").strip(),
        "supabase_service_key": os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip(),
    }


def parse_month(month: str) -> tuple[date, date]:
    m = re.match(r"^(\d{4})-(\d{2})$", month.strip())
    if not m:
        raise ValueError("month must be YYYY-MM")
    y, mo = int(m.group(1)), int(m.group(2))
    start = date(y, mo, 1)
    end = date(y, mo, calendar.monthrange(y, mo)[1])
    return start, end


def purshase_date_to_utc_kst(dt: Any) -> tuple[datetime | None, str | None]:
    if dt is None:
        return None, None
    if isinstance(dt, str):
        text = dt.strip().replace("Z", "+00:00")
        try:
            dt = datetime.fromisoformat(text)
        except ValueError:
            return None, None
    if isinstance(dt, datetime):
        if dt.tzinfo is None:
            local = dt.replace(tzinfo=KST)
        else:
            local = dt.astimezone(KST)
        utc = local.astimezone(timezone.utc)
        return utc, local.date().isoformat()
    return None, None


def json_safe(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value) if value % 1 else int(value)
    if isinstance(value, datetime):
        return value.isoformat()
    return value


def fetch_mssql(cfg: dict[str, Any], d_from: date, d_to: date) -> list[dict[str, Any]]:
    import pymssql

    conn = pymssql.connect(
        server=cfg["mssql_host"],
        port=cfg["mssql_port"],
        user=cfg["mssql_user"],
        password=cfg["mssql_password"],
        database=cfg["mssql_database"],
        login_timeout=30,
        timeout=600,
    )
    try:
        cur = conn.cursor(as_dict=True)
        cur.execute(MSSQL_SOLD_SELECT, (d_from.isoformat(), d_to.isoformat()))
        rows = cur.fetchall() or []
        return [{str(k): json_safe(v) for k, v in row.items()} for row in rows]
    finally:
        conn.close()


def load_existing_keys(sb: Client) -> tuple[set[str], set[str]]:
    numeric: set[str] = set()
    pwa_by_product: set[str] = set()
    offset = 0
    while True:
        resp = (
            sb.table("sales_history")
            .select("legacy_id,product_id")
            .range(offset, offset + 999)
            .execute()
        )
        batch = resp.data or []
        for r in batch:
            lid = str(r.get("legacy_id") or "").strip()
            if lid:
                numeric.add(lid)
            pid = str(r.get("product_id") or "").strip()
            if lid.startswith("pwa_id_") and pid:
                pwa_by_product.add(pid)
            if lid.startswith("pwa_id_"):
                base = lid[len("pwa_id_") :].split("_", 1)[0]
                if base.isdigit():
                    pwa_by_product.add(base)
        if len(batch) < 1000:
            break
        offset += 1000
    return numeric, pwa_by_product


def _storage_safe_sku(sku: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_.-]+", "_", str(sku or "").strip())


def _url_is_primary_product_webp(url: str, sku: str) -> bool:
    raw = str(url or "").strip()
    if not raw:
        return False
    sku_clean = str(sku or "").strip()
    if not sku_clean:
        return True
    filename = raw.split("?")[0].rstrip("/").rsplit("/", 1)[-1]
    return filename == f"{_storage_safe_sku(sku_clean)}.webp"


def _gallery_slot0_url(row: dict[str, Any]) -> str | None:
    slots = row.get("gallery_slots")
    if isinstance(slots, list) and slots:
        first = str(slots[0] or "").strip()
        if first:
            return first
    return None


def _product_has_primary_image(row: dict[str, Any]) -> bool:
    sku = str(row.get("sku") or "").strip()
    if _url_is_primary_product_webp(str(row.get("image_url") or ""), sku):
        return True
    if _gallery_slot0_url(row):
        return True
    return False


def pick_vitrine_product_by_sku(sb: Client, sku: str) -> dict[str, Any] | None:
    sku_clean = str(sku or "").strip()
    if not sku_clean:
        return None
    rows = (
        sb.table("products")
        .select("id,sku,image_url,additional_images,gallery_slots,updated_at")
        .eq("sku", sku_clean)
        .order("updated_at", desc=True)
        .limit(25)
        .execute()
        .data
        or []
    )
    if not rows:
        return None
    rows.sort(
        key=lambda r: (_product_has_primary_image(r), str(r.get("updated_at") or "")),
        reverse=True,
    )
    return rows[0]


def _primary_image_from_product(row: dict[str, Any]) -> str | None:
    sku = str(row.get("sku") or "").strip()
    img = str(row.get("image_url") or "").strip()
    if img and _url_is_primary_product_webp(img, sku):
        return img
    slot0 = _gallery_slot0_url(row)
    if slot0 and _url_is_primary_product_webp(slot0, sku):
        return slot0
    if slot0 and sku == "":
        return slot0
    extra = row.get("additional_images") or []
    if extra:
        first = str(extra[0] or "").strip()
        if first and _url_is_primary_product_webp(first, sku):
            return first
    return None


def storage_webp_url_for_sku(sku: str, supabase_url: str) -> str | None:
    """Public URL products/{sku}.webp if object exists (no .jpg fallback)."""
    sku_clean = str(sku or "").strip()
    if not sku_clean:
        return None
    safe = _storage_safe_sku(sku_clean)
    base = str(supabase_url or "").rstrip("/")
    if not base:
        return None
    public_url = (
        f"{base}/storage/v1/object/public/product-images/products/{safe}.webp"
    )
    try:
        req = urllib.request.Request(public_url, method="HEAD")
        with urllib.request.urlopen(req, timeout=15) as resp:
            if getattr(resp, "status", 200) == 200:
                return public_url
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return None
    except Exception:
        return None
    return None


def _commission_base_krw(price_krw: int, list_price_krw: int | None) -> int:
    listed = abs(int(list_price_krw or 0))
    sold = abs(int(price_krw))
    return listed if listed > 0 else sold


def resolve_seller_payroll_fields(
    sb: Client,
    seller_name: str | None,
    price_krw: int,
    metal_category: str | None,
    list_price_krw: int | None = None,
) -> dict[str, Any]:
    name = str(seller_name or "").strip()
    if not name:
        return {}
    try:
        res = sb.rpc("resolve_seller_by_name", {"p_name": name}).execute().data
    except Exception:
        return {}
    if not res:
        return {}
    row = res[0] if isinstance(res, list) else res
    if not isinstance(row, dict):
        return {}
    code = str(row.get("promo_code") or "").strip().upper()
    if not code:
        return {}
    gold = float(row.get("gold_commission_percent") or 0)
    silver = float(row.get("silver_commission_percent") or 0)
    metal = str(metal_category or "other").strip().lower()
    if code == "ADMIN":
        pct = 0.0
    elif metal == "gold":
        pct = gold
    elif metal == "silver":
        pct = silver
    else:
        pct = 0.0
    base = _commission_base_krw(price_krw, list_price_krw)
    sign = -1 if price_krw < 0 else 1
    commission_krw = sign * int(round(base * pct / 100.0))
    out: dict[str, Any] = {
        "seller_code": code,
        "commission_percent": pct,
        "commission_krw": commission_krw,
    }
    if code == "ADMIN":
        out["seller_name"] = name
    else:
        resolved = str(row.get("name") or "").strip()
        if resolved:
            out["seller_name"] = resolved
    return out


def enrich_drjaw_insert_row(
    sb: Client, row: dict[str, Any], supabase_url: str = ""
) -> dict[str, Any]:
    sku = str(row.get("sku") or "").strip()
    vitrine = pick_vitrine_product_by_sku(sb, sku)
    if vitrine:
        vid = str(vitrine.get("id") or "").strip()
        if vid:
            row["product_id"] = vid
        img = _primary_image_from_product(vitrine)
        if img:
            row["image_url"] = img
    if not str(row.get("image_url") or "").strip():
        storage_img = storage_webp_url_for_sku(sku, supabase_url)
        if storage_img:
            row["image_url"] = storage_img
    payroll = resolve_seller_payroll_fields(
        sb,
        row.get("seller_name"),
        int(row.get("price_krw") or 0),
        row.get("metal_category"),
        int(row.get("list_price_krw") or 0) or None,
    )
    row.update(payroll)
    return row


def find_pwa_rows(sb: Client, product_id: str) -> list[dict[str, Any]]:
    return (
        sb.table("sales_history")
        .select("id,legacy_id,seller_name,payment_method,metal_category")
        .eq("product_id", product_id)
        .like("legacy_id", "pwa_id%")
        .order("sold_at_utc", desc=True)
        .execute()
        .data
        or []
    )


def build_insert_row(ms: dict[str, Any], import_batch: str) -> dict[str, Any]:
    legacy_id = str(ms["legacy_id"]).strip()
    price_krw = int(Decimal(str(ms.get("Price") or 0)).to_integral_value())
    bonus = parse_bonus(ms.get("Bonus"))
    metall = ms.get("Metall")
    metal_category = classify_metal_category(metall)
    store = resolve_store_from_mart(ms.get("Mart"))
    seller = map_purshase_source_to_seller(ms.get("PurshaseSource"))
    payment = map_purshase_type_to_payment(ms.get("PurshaseType"))
    sold_utc, sold_kst = purshase_date_to_utc_kst(ms.get("PurshaseDate"))
    weight = parse_weight(ms.get("Weight"))
    list_price = list_price_from_sale(price_krw, bonus)
    payload = merge_payload(
        None,
        {
            "Metall": metall,
            "Type": ms.get("Type"),
            "Weight": weight,
            "Manager": ms.get("Manager"),
            "Mart": ms.get("Mart"),
            "Bonus": ms.get("Bonus"),
            "cart_id": ms.get("CartId"),
            "PurshaseSource": seller,
            "PurshaseType": ms.get("PurshaseType"),
            "PurshaseDate": ms.get("PurshaseDate"),
        },
    )
    row: dict[str, Any] = {
        "legacy_id": legacy_id,
        "sku": str(ms.get("sku") or "").strip() or None,
        "product_id": legacy_id if legacy_id.isdigit() else None,
        "price_krw": price_krw,
        "list_price_krw": list_price if bonus > 0 else price_krw,
        "discount_percent": bonus if bonus > 0 else 0,
        "store_location": store,
        "seller_name": seller,
        "payment_method": payment,
        "sold_at_utc": sold_utc.isoformat() if sold_utc else None,
        "sold_date_kst": sold_kst,
        "photo_status": "success",
        "import_batch_id": import_batch,
        "source_system": "DrJaw",
        "raw_legacy_payload": payload,
        "metal_category": metal_category,
        "migration_meta": {
            "source_system": "DrJaw",
            "etl_version": "incremental_drjaw_sales.py",
            "cart_id": ms.get("CartId"),
            "logged_by": "incremental_drjaw_sales",
        },
    }
    return row


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--month", default="2026-11", help="YYYY-MM")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    logger = setup_logging()
    cfg = load_cfg()
    if not cfg["supabase_url"] or not cfg["supabase_service_key"]:
        logger.error("Supabase env missing")
        sys.exit(1)

    d_from, d_to = parse_month(args.month)
    logger.info("MSSQL Sold %s .. %s", d_from, d_to)
    ms_rows = fetch_mssql(cfg, d_from, d_to)
    logger.info("MSSQL rows: %s", len(ms_rows))

    sb = create_client(cfg["supabase_url"], cfg["supabase_service_key"])
    existing, pwa_products = load_existing_keys(sb)

    import_batch = str(uuid.uuid4())
    inserts: list[dict[str, Any]] = []
    backfills: list[dict[str, Any]] = []
    skipped_numeric = 0
    skipped_pwa = 0

    for ms in ms_rows:
        lid = str(ms["legacy_id"]).strip()
        pwa_key = f"pwa_id_{lid}"
        if lid in existing:
            skipped_numeric += 1
            continue
        if lid in pwa_products or pwa_key in existing:
            skipped_pwa += 1
            pwa_rows = find_pwa_rows(sb, lid)
            for pr in pwa_rows:
                patch: dict[str, Any] = {}
                if not str(pr.get("seller_name") or "").strip():
                    s = map_purshase_source_to_seller(ms.get("PurshaseSource"))
                    if s:
                        patch["seller_name"] = s
                if not str(pr.get("payment_method") or "").strip():
                    p = map_purshase_type_to_payment(ms.get("PurshaseType"))
                    if p:
                        patch["payment_method"] = p
                if patch:
                    backfills.append({"id": pr["id"], "legacy_id": pr["legacy_id"], **patch})
            continue
        inserts.append(
            enrich_drjaw_insert_row(
                sb,
                build_insert_row(ms, import_batch),
                cfg["supabase_url"],
            )
        )

    summary = {
        "month": args.month,
        "mssql": len(ms_rows),
        "insert": len(inserts),
        "backfill_pwa": len(backfills),
        "skipped_existing_numeric": skipped_numeric,
        "skipped_has_pwa": skipped_pwa,
        "dry_run": args.dry_run,
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))

    if args.dry_run:
        if inserts[:5]:
            print("sample_inserts:", json.dumps(inserts[:5], ensure_ascii=False, indent=2))
        if backfills[:5]:
            print("sample_backfills:", json.dumps(backfills[:5], ensure_ascii=False, indent=2))
        return

    for row in inserts:
        sb.table("sales_history").upsert(row, on_conflict="legacy_id").execute()
    logger.info("Inserted/upserted %s DrJaw rows", len(inserts))

    for bf in backfills:
        sid = bf.pop("id")
        bf.pop("legacy_id", None)
        sb.table("sales_history").update(bf).eq("id", sid).execute()
    logger.info("Backfilled %s PWA rows from Cart", len(backfills))


if __name__ == "__main__":
    main()