#!/usr/bin/env python3
"""Compare sales_history (Supabase) vs DrJaw Cart for a KST date range."""
from __future__ import annotations

import json
import os
from collections import Counter, defaultdict
from datetime import date, datetime, timezone
from decimal import Decimal
from pathlib import Path

from dotenv import load_dotenv
from supabase import create_client

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
DATE_FROM = date(2026, 11, 3)
DATE_TO = date(2026, 11, 20)
OUT_PATH = SCRIPT_DIR / f"audit_sales_{DATE_FROM.isoformat()}_{DATE_TO.isoformat()}.json"


def load_cfg() -> dict:
    load_dotenv(SCRIPT_DIR / ".env")
    load_dotenv(REPO_ROOT / ".env", override=True)
    return {
        "supabase_url": os.getenv("SUPABASE_URL", "").strip(),
        "supabase_key": os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip(),
        "mssql_host": os.getenv("MSSQL_HOST", "211.176.43.226").strip(),
        "mssql_port": int(os.getenv("MSSQL_PORT", "1433")),
        "mssql_user": os.getenv("MSSQL_USER", "DrJ_Reader").strip(),
        "mssql_password": os.getenv("MSSQL_PASSWORD", "Read_only11!"),
        "mssql_database": os.getenv("MSSQL_DATABASE", "DrJaw").strip(),
    }


def fetch_supabase_rows(cfg: dict) -> list[dict]:
    sb = create_client(cfg["supabase_url"], cfg["supabase_key"])
    cols = (
        "id,legacy_id,sku,product_id,price_krw,list_price_krw,metal_category,"
        "seller_name,payment_method,source_system,sold_at_utc,sold_date_kst,"
        "migration_meta,raw_legacy_payload"
    )
    out: list[dict] = []
    offset = 0
    page = 1000
    while True:
        q = (
            sb.table("sales_history")
            .select(cols)
            .gte("sold_date_kst", DATE_FROM.isoformat())
            .lte("sold_date_kst", DATE_TO.isoformat())
            .order("sold_date_kst")
            .order("legacy_id")
        )
        batch = q.range(offset, offset + page - 1).execute().data or []
        out.extend(batch)
        if len(batch) < page:
            break
        offset += page

    skus = sorted({str(r.get("sku") or "").strip() for r in out if str(r.get("sku") or "").strip()})
    products: dict[str, dict] = {}
    for i in range(0, len(skus), 400):
        chunk = skus[i : i + 400]
        if not chunk:
            continue
        resp = (
            sb.table("products")
            .select("id,sku,name,metal,metal_type,weight_grams,status")
            .in_("sku", chunk)
            .execute()
        )
        for p in resp.data or []:
            products[str(p["sku"])] = p

    pids = sorted(
        {
            str(r.get("product_id") or "").strip()
            for r in out
            if str(r.get("product_id") or "").strip()
        }
    )
    for i in range(0, len(pids), 400):
        chunk = pids[i : i + 400]
        if not chunk:
            continue
        resp = (
            sb.table("products")
            .select("id,sku,name,metal,metal_type,weight_grams,status")
            .in_("id", chunk)
            .execute()
        )
        for p in resp.data or []:
            products.setdefault(str(p["sku"]), p)
            products[str(p["id"])] = p

    enriched = []
    for r in out:
        pid = str(r.get("product_id") or "").strip()
        sku = str(r.get("sku") or "").strip()
        prod = products.get(pid) or products.get(sku) or {}
        name = None
        if prod.get("name"):
            nm = prod["name"]
            if isinstance(nm, dict):
                name = nm.get("ru") or nm.get("ko") or nm.get("en")
            else:
                name = str(nm)
        if not name:
            payload = r.get("raw_legacy_payload") or {}
            if isinstance(payload, dict):
                name = payload.get("Type") or payload.get("name")
        price = int(r.get("price_krw") or 0)
        meta = r.get("migration_meta") or {}
        if isinstance(meta, str):
            try:
                meta = json.loads(meta)
            except json.JSONDecodeError:
                meta = {}
        is_return = (
            price < 0
            or str(meta.get("type") or "") == "return"
            or str(r.get("legacy_id") or "").startswith("return_")
        )
        enriched.append(
            {
                **r,
                "product_name": name,
                "metal_type": prod.get("metal_type") or prod.get("metal"),
                "weight_grams": prod.get("weight_grams"),
                "product_status": prod.get("status"),
                "is_return_line": is_return,
                "group": (
                    "pwa"
                    if str(r.get("legacy_id") or "").startswith("pwa_id_")
                    else "drjaw"
                ),
            }
        )
    return enriched


def fetch_mssql_sold_items(cfg: dict) -> list[dict]:
    import pymssql

    sql = """
    SELECT
      CAST(i.Id AS VARCHAR(32)) AS legacy_id,
      i.Articul AS sku,
      i.Price,
      i.Status,
      i.CartId,
      c.PurshaseDate,
      c.OperationType,
      c.TotalSum AS cart_total,
      c.PurshaseSource,
      c.PurshaseType
    FROM dbo.Items AS i
    INNER JOIN dbo.Cart AS c ON c.CartId = i.CartId
    WHERE c.OperationType = N'Sold'
      AND i.Status = N'Sold'
      AND CAST(c.PurshaseDate AS DATE) >= %s
      AND CAST(c.PurshaseDate AS DATE) <= %s
    ORDER BY c.PurshaseDate DESC, i.Id DESC
    """
    conn = pymssql.connect(
        server=cfg["mssql_host"],
        port=cfg["mssql_port"],
        user=cfg["mssql_user"],
        password=cfg["mssql_password"],
        database=cfg["mssql_database"],
        login_timeout=30,
        timeout=120,
    )
    try:
        cur = conn.cursor(as_dict=True)
        cur.execute(sql, (DATE_FROM.isoformat(), DATE_TO.isoformat()))
        rows = cur.fetchall() or []
        for row in rows:
            if isinstance(row.get("PurshaseDate"), datetime):
                row["PurshaseDate"] = row["PurshaseDate"].isoformat()
        return rows
    finally:
        conn.close()


def kst_label(utc_iso: str | None) -> str | None:
    if not utc_iso:
        return None
    try:
        dt = datetime.fromisoformat(utc_iso.replace("Z", "+00:00"))
        from zoneinfo import ZoneInfo

        return dt.astimezone(ZoneInfo("Asia/Seoul")).strftime("%Y-%m-%d %H:%M:%S KST")
    except Exception:
        return utc_iso


def main() -> None:
    cfg = load_cfg()
    if not cfg["supabase_url"]:
        raise SystemExit("SUPABASE_URL missing")

    sb_rows = fetch_supabase_rows(cfg)
    ms_rows = fetch_mssql_sold_items(cfg)
    ms_by_legacy = {str(r["legacy_id"]): r for r in ms_rows}

    drjaw_sb = [r for r in sb_rows if r["group"] == "drjaw"]
    pwa_sb = [r for r in sb_rows if r["group"] == "pwa"]
    returns_sb = [r for r in sb_rows if r["is_return_line"]]
    negative_sb = [r for r in sb_rows if int(r.get("price_krw") or 0) < 0]
    other_sb = [
        r
        for r in sb_rows
        if not r["is_return_line"]
        and int(r.get("price_krw") or 0) > 0
        and str(r.get("metal_category") or "other") == "other"
    ]

    ms_legacy_set = set(ms_by_legacy)
    drjaw_in_sb_not_ms = [
        r for r in drjaw_sb if str(r.get("legacy_id")) not in ms_legacy_set
    ]
    ms_not_in_sb = [
        r for r in ms_rows if str(r["legacy_id"]) not in {str(x.get("legacy_id")) for x in drjaw_sb}
    ]

    latest_ms = ms_rows[0] if ms_rows else None

    cleanup_candidates = []
    for r in pwa_sb + returns_sb:
        legacy = str(r.get("legacy_id") or "")
        price = int(r.get("price_krw") or 0)
        reasons = []
        if r["is_return_line"]:
            reasons.append("return_line")
        if price < 0:
            reasons.append("negative_price")
        if str(r.get("metal_category") or "") == "other" and price > 0:
            reasons.append("metal_other")
        if legacy.startswith("pwa_id_"):
            reasons.append("pwa_sale")
        test_hints = (
            "test" in legacy.lower()
            or "test" in str(r.get("sku") or "").lower()
            or r.get("seller_name") in (None, "")
        )
        if test_hints and (r["is_return_line"] or price < 0):
            reasons.append("possible_test")
        if reasons:
            cleanup_candidates.append(
                {
                    "id": r["id"],
                    "legacy_id": legacy,
                    "sku": r.get("sku"),
                    "price_krw": price,
                    "sold_date_kst": r.get("sold_date_kst"),
                    "product_id": r.get("product_id"),
                    "product_status": r.get("product_status"),
                    "reasons": reasons,
                }
            )

    report = {
        "period_kst": {"from": DATE_FROM.isoformat(), "to": DATE_TO.isoformat()},
        "counts": {
            "supabase_total": len(sb_rows),
            "supabase_drjaw": len(drjaw_sb),
            "supabase_pwa": len(pwa_sb),
            "supabase_returns": len(returns_sb),
            "supabase_negative_price": len(negative_sb),
            "supabase_other_metal_positive": len(other_sb),
            "mssql_sold_items": len(ms_rows),
            "drjaw_sb_not_in_mssql_period": len(drjaw_in_sb_not_ms),
            "mssql_not_in_supabase_drjaw": len(ms_not_in_sb),
        },
        "mssql_latest_sale_in_period": latest_ms,
        "pwa_payment_methods": dict(Counter(str(r.get("payment_method")) for r in pwa_sb)),
        "drjaw_payment_methods": dict(Counter(str(r.get("payment_method")) for r in drjaw_sb)),
        "supabase_rows": [
            {
                "id": r["id"],
                "legacy_id": r.get("legacy_id"),
                "sku": r.get("sku"),
                "name": r.get("product_name"),
                "price_krw": r.get("price_krw"),
                "metal_category": r.get("metal_category"),
                "metal_type": r.get("metal_type"),
                "weight_grams": r.get("weight_grams"),
                "seller_name": r.get("seller_name"),
                "payment_method": r.get("payment_method"),
                "is_return": r.get("is_return_line"),
                "product_status": r.get("product_status"),
                "group": r.get("group"),
                "sold_date_kst": r.get("sold_date_kst"),
                "sold_at_kst": kst_label(r.get("sold_at_utc")),
                "in_mssql_period": str(r.get("legacy_id")) in ms_legacy_set,
            }
            for r in sb_rows
        ],
        "mssql_rows": ms_rows,
        "drjaw_sb_missing_mssql_match": [
            {
                "legacy_id": r.get("legacy_id"),
                "sku": r.get("sku"),
                "sold_date_kst": r.get("sold_date_kst"),
                "price_krw": r.get("price_krw"),
            }
            for r in drjaw_in_sb_not_ms
        ],
        "mssql_missing_supabase": ms_not_in_sb[:200],
        "cleanup_candidates_pwa_test_returns": cleanup_candidates,
    }

    def _json_default(o: object):
        if isinstance(o, Decimal):
            return float(o)
        if isinstance(o, datetime):
            return o.isoformat()
        raise TypeError(type(o))

    OUT_PATH.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, default=_json_default),
        encoding="utf-8",
    )
    print(json.dumps(report["counts"], ensure_ascii=False, indent=2))
    print(f"Full report: {OUT_PATH}")
    if negative_sb:
        print("\nNegative price rows:")
        for r in negative_sb:
            print(
                f"  {r.get('legacy_id')} | {r.get('sku')} | {r.get('price_krw')} | "
                f"{r.get('sold_date_kst')} | return={r.get('is_return_line')}"
            )
    if other_sb:
        print("\nOther metal (positive) rows:")
        for r in other_sb:
            print(
                f"  {r.get('legacy_id')} | {r.get('sku')} | {r.get('price_krw')} | "
                f"group={r.get('group')}"
            )


if __name__ == "__main__":
    main()