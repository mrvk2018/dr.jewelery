#!/usr/bin/env python3
"""
Дообогащение sales_history из DrJaw MSSQL (Items + Articuls).

  python migration/enrich_sales_from_mssql.py --dry-run --date-from 2026-09-18 --date-to 2026-09-19
  python migration/enrich_sales_from_mssql.py --date-from 2026-09-18 --date-to 2026-09-19

Env: migration/.env or repo .env (как etl_sales_migration.py).
"""

from __future__ import annotations

import argparse
import json
import logging
import re
import sys
import time
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from supabase import Client, create_client

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
BACKUP_DIR = SCRIPT_DIR / "backups"
LOG_PATH = SCRIPT_DIR / "enrich_sales_from_mssql.log"

MSSQL_ENRICH_SELECT = """
SELECT
  CAST(i.Id AS VARCHAR(32)) AS legacy_id,
  i.Articul,
  i.Price,
  i.Weight,
  i.Mart,
  i.Manager,
  i.CartId,
  i.Bonus,
  i.Comment,
  a.Metall,
  a.Type
FROM dbo.Items AS i
LEFT JOIN dbo.Articuls AS a ON a.Articul = i.Articul
"""

MSSQL_ENRICH_BY_IDS = MSSQL_ENRICH_SELECT + """
WHERE CAST(i.Id AS VARCHAR(32)) IN ({placeholders})
"""

MSSQL_ENRICH_SOLD_WITH_CART = MSSQL_ENRICH_SELECT + """
WHERE i.CartId IS NOT NULL AND LTRIM(RTRIM(i.CartId)) <> ''
"""


def setup_logging() -> logging.Logger:
    logger = logging.getLogger("enrich_sales")
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


def load_mssql_config() -> dict[str, Any]:
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


def resolve_store_from_mart(mart: Any) -> str | None:
    raw = str(mart or "").strip()
    if not raw:
        return None
    lower = raw.lower()
    if (
        raw == "D.Y №2"
        or "№2" in lower
        or "d.y" in lower
        or lower == "ans"
        or "ансан" in lower
    ):
        return "ANS"
    return "ICN"


def classify_metal_category(metall: Any) -> str:
    text = str(metall or "").strip().lower()
    if not text:
        return "other"
    if "золото" in text or re.search(r"(^|[^0-9])(585|750|583|375)([^0-9]|$)", text):
        return "gold"
    if "серебр" in text or "925" in text:
        return "silver"
    return "other"


def parse_bonus(value: Any) -> int:
    if value is None:
        return 0
    text = str(value).strip()
    if not text:
        return 0
    try:
        n = int(Decimal(text).to_integral_value())
    except (InvalidOperation, ValueError):
        return 0
    return max(0, min(n, 100))


def parse_weight(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float, Decimal)):
        w = float(value)
        return w if w > 0 else None
    text = str(value).strip().replace(",", ".")
    if not text:
        return None
    try:
        w = float(Decimal(text))
    except (InvalidOperation, ValueError):
        return None
    return w if w > 0 else None


def list_price_from_sale(price_krw: int, bonus_pct: int) -> int:
    if price_krw <= 0:
        return 0
    if bonus_pct <= 0:
        return price_krw
    if bonus_pct >= 100:
        return price_krw
    return int(round(price_krw * 100.0 / (100 - bonus_pct)))


def json_safe(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value) if value % 1 else int(value)
    if isinstance(value, datetime):
        return value.isoformat()
    return value


def is_drjaw_row(row: dict[str, Any]) -> bool:
    legacy = str(row.get("legacy_id") or "")
    if legacy.startswith("pwa_id_"):
        return False
    meta = row.get("migration_meta") or {}
    if isinstance(meta, str):
        try:
            meta = json.loads(meta)
        except json.JSONDecodeError:
            meta = {}
    src = str(row.get("source_system") or meta.get("source_system") or "").strip()
    if src.lower() == "drjaw":
        return True
    if meta.get("etl_version") or meta.get("field_mapping"):
        return True
    if legacy.isdigit():
        return True
    return False


def merge_payload(existing: dict[str, Any] | None, patch: dict[str, Any]) -> dict[str, Any]:
    base = dict(existing or {})
    for key, val in patch.items():
        if val is None:
            continue
        if key == "Weight" and base.get("Weight") not in (None, "", 0):
            continue
        base[key] = json_safe(val)
    return base


PAGE_SIZE = 1000
MSSQL_ID_CHUNK = 400


def fetch_sales_rows(
    supabase: Client,
    date_from: str | None,
    date_to: str | None,
) -> list[dict[str, Any]]:
    columns = (
        "id, legacy_id, sku, price_krw, sold_date_kst, product_id, "
        "store_location, seller_name, metal_category, list_price_krw, "
        "discount_percent, source_system, raw_legacy_payload, migration_meta"
    )
    out: list[dict[str, Any]] = []
    offset = 0
    while True:
        q = (
            supabase.table("sales_history")
            .select(columns)
            .not_.like("legacy_id", "pwa_id%")
            .order("sold_date_kst")
            .order("legacy_id")
        )
        if date_from:
            q = q.gte("sold_date_kst", date_from)
        if date_to:
            q = q.lte("sold_date_kst", date_to)
        resp = q.range(offset, offset + PAGE_SIZE - 1).execute()
        batch = resp.data or []
        out.extend(r for r in batch if is_drjaw_row(r))
        if len(batch) < PAGE_SIZE:
            break
        offset += PAGE_SIZE
    return out


def fetch_mssql_rows(cfg: dict[str, Any], legacy_ids: list[str]) -> dict[str, dict[str, Any]]:
    if not legacy_ids:
        return {}
    import pymssql

    needed = {str(lid).strip() for lid in legacy_ids if str(lid).strip()}
    out: dict[str, dict[str, Any]] = {}

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
        if len(needed) > 500:
            logger = logging.getLogger("enrich_sales")
            logger.info("MSSQL: single scan Items with CartId...")
            cur.execute(MSSQL_ENRICH_SOLD_WITH_CART)
            for row in cur.fetchall() or []:
                lid = str(row.get("legacy_id") or "").strip()
                if lid in needed:
                    out[lid] = {str(k): json_safe(v) for k, v in row.items()}
        else:
            for start in range(0, len(legacy_ids), MSSQL_ID_CHUNK):
                chunk = legacy_ids[start : start + MSSQL_ID_CHUNK]
                placeholders = ",".join(["%s"] * len(chunk))
                sql = MSSQL_ENRICH_BY_IDS.format(placeholders=placeholders)
                cur.execute(sql, tuple(chunk))
                for row in cur.fetchall() or []:
                    lid = str(row.get("legacy_id") or "").strip()
                    if lid:
                        out[lid] = {str(k): json_safe(v) for k, v in row.items()}
        cur.close()
    finally:
        conn.close()
    return out


def preload_product_ids(supabase: Client, legacy_ids: list[str]) -> set[str]:
    known: set[str] = set()
    ids = [lid for lid in legacy_ids if lid.strip()]
    for start in range(0, len(ids), MSSQL_ID_CHUNK):
        chunk = ids[start : start + MSSQL_ID_CHUNK]
        resp = supabase.table("products").select("id").in_("id", chunk).execute()
        for row in resp.data or []:
            known.add(str(row["id"]))
    return known


def resolve_product_id(
    legacy_id: str,
    sku: str | None,
    known_ids: set[str] | None,
    sku_to_product_id: dict[str, str] | None,
) -> str | None:
    lid = legacy_id.strip()
    if lid and known_ids and lid in known_ids:
        return lid
    if lid.isdigit():
        return lid
    sku_t = (sku or "").strip()
    if sku_t and sku_to_product_id:
        hit = sku_to_product_id.get(sku_t)
        if hit:
            return hit
    return None


def preload_sku_product_ids(supabase: Client, skus: list[str]) -> dict[str, str]:
    unique = sorted({s.strip() for s in skus if s and str(s).strip()})
    out: dict[str, str] = {}
    for start in range(0, len(unique), MSSQL_ID_CHUNK):
        chunk = unique[start : start + MSSQL_ID_CHUNK]
        resp = supabase.table("products").select("id, sku").in_("sku", chunk).execute()
        for row in resp.data or []:
            sku = str(row.get("sku") or "").strip()
            pid = str(row.get("id") or "").strip()
            if sku and pid and sku not in out:
                out[sku] = pid
    return out


def build_patch(
    sh_row: dict[str, Any],
    ms_row: dict[str, Any] | None,
    product_id: str | None,
) -> dict[str, Any] | None:
    if ms_row is None:
        return None

    legacy_id = str(sh_row.get("legacy_id") or "")
    price_krw = int(sh_row.get("price_krw") or 0)
    bonus = parse_bonus(ms_row.get("Bonus"))
    metall = ms_row.get("Metall")
    metal_category = classify_metal_category(metall)
    store = resolve_store_from_mart(ms_row.get("Mart"))
    manager = str(ms_row.get("Manager") or "").strip() or None
    weight = parse_weight(ms_row.get("Weight"))

    payload_patch: dict[str, Any] = {
        "Metall": metall,
        "Type": ms_row.get("Type"),
        "Weight": weight,
        "Manager": manager,
        "Mart": ms_row.get("Mart"),
        "Bonus": bonus if bonus > 0 else ms_row.get("Bonus"),
    }
    new_payload = merge_payload(sh_row.get("raw_legacy_payload"), payload_patch)

    patch: dict[str, Any] = {
        "raw_legacy_payload": new_payload,
        "metal_category": metal_category,
    }

    if store and not str(sh_row.get("store_location") or "").strip():
        patch["store_location"] = store
    if manager and not str(sh_row.get("seller_name") or "").strip():
        patch["seller_name"] = manager
    if product_id and not str(sh_row.get("product_id") or "").strip():
        patch["product_id"] = product_id
    if not str(sh_row.get("source_system") or "").strip():
        patch["source_system"] = "DrJaw"

    new_discount = bonus if bonus > 0 else int(sh_row.get("discount_percent") or 0)
    new_list = list_price_from_sale(price_krw, bonus)
    if bonus > 0:
        patch["discount_percent"] = new_discount
        patch["list_price_krw"] = new_list
    elif not sh_row.get("list_price_krw"):
        patch["list_price_krw"] = price_krw

    return {
        "sales_history_id": sh_row["id"],
        "legacy_id": legacy_id,
        "sku": sh_row.get("sku"),
        "sold_date_kst": sh_row.get("sold_date_kst"),
        "before": {
            "store_location": sh_row.get("store_location"),
            "seller_name": sh_row.get("seller_name"),
            "metal_category": sh_row.get("metal_category"),
            "product_id": sh_row.get("product_id"),
            "list_price_krw": sh_row.get("list_price_krw"),
            "discount_percent": sh_row.get("discount_percent"),
        },
        "after": patch,
        "mssql": {
            "Metall": metall,
            "Type": ms_row.get("Type"),
            "Weight": weight,
            "Mart": ms_row.get("Mart"),
            "Manager": manager,
            "Bonus": bonus,
        },
    }


def write_backup(records: list[dict[str, Any]], label: str) -> Path:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = BACKUP_DIR / f"enrich_sales_{label}_{stamp}.json"
    payload = {
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "scope": label,
        "rows": records,
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def sales_row_needs_enrich(row: dict[str, Any]) -> bool:
    payload = row.get("raw_legacy_payload") or {}
    if not isinstance(payload, dict):
        return True
    if not str(payload.get("Metall") or "").strip():
        return True
    if not str(row.get("store_location") or "").strip():
        return True
    if not str(row.get("seller_name") or "").strip():
        return True
    if str(row.get("metal_category") or "other") == "other":
        return True
    return False


def make_supabase_client(cfg: dict[str, Any]) -> Client:
    return create_client(cfg["supabase_url"], cfg["supabase_service_key"])


def apply_patches(
    supabase: Client,
    plans: list[dict[str, Any]],
    logger: logging.Logger,
    cfg: dict[str, Any],
) -> None:
    client = supabase
    for index, plan in enumerate(plans, start=1):
        if index % 150 == 1 and index > 1:
            client = make_supabase_client(cfg)
        row_id = plan["sales_history_id"]
        update_body = dict(plan["after"])
        last_err: Exception | None = None
        for attempt in range(5):
            try:
                client.table("sales_history").update(update_body).eq("id", row_id).execute()
                last_err = None
                break
            except Exception as exc:
                last_err = exc
                wait = min(2 ** attempt, 30)
                logger.warning(
                    "Update retry legacy_id=%s attempt=%s: %s",
                    plan["legacy_id"],
                    attempt + 1,
                    exc,
                )
                client = make_supabase_client(cfg)
                time.sleep(wait)
        if last_err is not None:
            raise last_err
        if index <= 5 or index % 250 == 0 or index == len(plans):
            logger.info(
                "Updated %s/%s legacy_id=%s",
                index,
                len(plans),
                plan["legacy_id"],
            )


def main() -> None:
    parser = argparse.ArgumentParser(description="Enrich sales_history from DrJaw MSSQL")
    parser.add_argument("--dry-run", action="store_true", help="Only print planned changes")
    parser.add_argument("--all", action="store_true", help="All DrJaw rows (ignore date filters)")
    parser.add_argument("--date-from", help="sold_date_kst from (YYYY-MM-DD)")
    parser.add_argument("--date-to", help="sold_date_kst to (YYYY-MM-DD)")
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print full JSON plans (default: summary only)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-apply all rows (including already enriched)",
    )
    args = parser.parse_args()

    if not args.all and (not args.date_from or not args.date_to):
        parser.error("Specify --all or both --date-from and --date-to")

    logger = setup_logging()
    cfg = load_mssql_config()
    if not cfg["supabase_url"] or not cfg["supabase_service_key"]:
        logger.error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required")
        sys.exit(1)

    date_from = None if args.all else args.date_from
    date_to = None if args.all else args.date_to
    scope_label = "all" if args.all else f"{date_from}_{date_to}"

    supabase = create_client(cfg["supabase_url"], cfg["supabase_service_key"])
    sales_rows = fetch_sales_rows(supabase, date_from, date_to)
    logger.info(
        "DrJaw candidates (%s): %s",
        scope_label,
        len(sales_rows),
    )

    legacy_ids = [str(r["legacy_id"]) for r in sales_rows]
    logger.info("Loading MSSQL Items+Articuls for %s ids...", len(legacy_ids))
    mssql_by_id = fetch_mssql_rows(cfg, legacy_ids)
    logger.info("MSSQL matches: %s", len(mssql_by_id))
    known_product_ids = preload_product_ids(supabase, legacy_ids)
    sku_to_pid = preload_sku_product_ids(
        supabase, [str(r.get("sku") or "") for r in sales_rows]
    )

    plans: list[dict[str, Any]] = []
    missing_mssql: list[str] = []
    row_by_id = {str(r["id"]): r for r in sales_rows}
    skip_enriched = not args.force and not args.dry_run
    for sh in sales_rows:
        if skip_enriched and not sales_row_needs_enrich(sh):
            continue
        lid = str(sh["legacy_id"])
        ms = mssql_by_id.get(lid)
        if ms is None:
            missing_mssql.append(lid)
            continue
        pid = resolve_product_id(lid, sh.get("sku"), known_product_ids, sku_to_pid)
        plan = build_patch(sh, ms, pid)
        if plan:
            plans.append(plan)

    summary = {
        "mode": "dry-run" if args.dry_run else "apply",
        "scope": scope_label,
        "sales_history_rows": len(sales_rows),
        "plans": len(plans),
        "missing_mssql": len(missing_mssql),
        "sample_missing_mssql": missing_mssql[:20],
    }
    if args.verbose:
        summary["plans_detail"] = plans
    print(json.dumps(summary, ensure_ascii=False, indent=2))

    if missing_mssql:
        logger.warning(
            "No MSSQL row for %s legacy_ids (first: %s)",
            len(missing_mssql),
            ", ".join(missing_mssql[:10]),
        )

    if args.dry_run:
        logger.info("Dry-run complete (%s plans).", len(plans))
        return

    if not plans:
        logger.info("Nothing to apply.")
        return

    backup_rows = []
    for p in plans:
        sid = p["sales_history_id"]
        sh_row = row_by_id.get(sid) or next(
            (r for r in sales_rows if r["id"] == sid),
            {},
        )
        backup_rows.append(
            {
                "id": sid,
                "legacy_id": p["legacy_id"],
                "snapshot_before": p["before"],
                "raw_legacy_payload": sh_row.get("raw_legacy_payload"),
            }
        )

    backup_path = write_backup(backup_rows, scope_label)
    logger.info("Backup written: %s", backup_path)

    apply_patches(supabase, plans, logger, cfg)
    logger.info("Applied %s updates.", len(plans))


if __name__ == "__main__":
    main()