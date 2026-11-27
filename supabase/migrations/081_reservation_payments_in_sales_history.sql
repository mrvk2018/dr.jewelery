-- 081: Платежи по броням (reservation_payments) в ленте list_sales_history_report
-- по дате транзакции (created_at KST). Касса смены / summary не меняем (079).

BEGIN;

DROP FUNCTION IF EXISTS public.list_sales_history_report(date, date, text, integer, integer);

CREATE OR REPLACE FUNCTION public.list_sales_history_report(
  p_date_from date,
  p_date_to date,
  p_store text DEFAULT 'ALL',
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  legacy_id text,
  product_id text,
  sku text,
  product_name text,
  weight_grams numeric,
  list_price_krw bigint,
  price_krw bigint,
  discount_percent integer,
  store_location text,
  seller_name text,
  seller_code text,
  payment_method text,
  sold_at_utc timestamptz,
  sold_date_kst date,
  image_url text,
  metal_category text,
  source_system text,
  manufacturer text,
  can_return boolean,
  sale_batch_id text,
  scrap_trade_in_krw bigint,
  net_cash_delta_krw bigint,
  is_trade_in boolean,
  is_reservation_payment boolean,
  reservation_payment_type text,
  reservation_status text,
  reservation_customer_name text,
  reservation_customer_phone text,
  reservation_items_summary text,
  reservation_has_refund boolean,
  reservation_expires_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, storage
AS $$
  WITH sales_rows AS (
    SELECT
      b.id,
      b.legacy_id,
      b.product_id,
      b.sku,
      b.p_name AS product_name,
      COALESCE(b.p_weight, public.sales_history_payload_weight_grams(b.raw_legacy_payload)) AS weight_grams,
      COALESCE(b.list_price_krw, b.price_krw) AS list_price_krw,
      b.price_krw,
      COALESCE(b.discount_percent, 0) AS discount_percent,
      b.resolved_store AS store_location,
      NULLIF(btrim(b.seller_name), '') AS seller_name,
      b.seller_code,
      b.payment_method,
      b.sold_at_utc,
      b.sold_date_kst,
      b.resolved_image_url AS image_url,
      b.resolved_metal_category AS metal_category,
      b.source_system,
      NULLIF(btrim(b.raw_legacy_payload ->> 'Manager'), '') AS manufacturer,
      (
        b.price_krw > 0
        AND b.legacy_id LIKE 'pwa_id_%'
        AND COALESCE(b.source_system, '') IS DISTINCT FROM 'DrJaw'
        AND b.p_status = 'sold'
        AND NOT EXISTS (
          SELECT 1
          FROM public.sales_history AS r
          WHERE (r.migration_meta ->> 'reverses_legacy_id') = b.legacy_id
            AND COALESCE(r.migration_meta ->> 'type', '') = 'return'
        )
      ) AS can_return,
      b.sale_batch_id,
      b.scrap_trade_in_krw,
      b.net_cash_delta_krw,
      (b.scrap_trade_in_krw > 0 OR coalesce(b.migration_meta ->> 'trade_in', '') = 'true') AS is_trade_in,
      false AS is_reservation_payment,
      NULL::text AS reservation_payment_type,
      NULL::text AS reservation_status,
      NULL::text AS reservation_customer_name,
      NULL::text AS reservation_customer_phone,
      NULL::text AS reservation_items_summary,
      false AS reservation_has_refund,
      NULL::timestamptz AS reservation_expires_at
    FROM (
      SELECT sh.*,
        public._sales_history_resolve_store(sh) AS resolved_store,
        COALESCE(p.weight_grams, p_sku.weight_grams) AS p_weight,
        COALESCE(p.status, p_sku.status) AS p_status,
        COALESCE(
          NULLIF(btrim(p.name ->> 'ru'), ''),
          NULLIF(btrim(p.name ->> 'ko'), ''),
          NULLIF(btrim(sh.sku), '')
        ) AS p_name,
        COALESCE(
          public.product_primary_image_url(p),
          public.product_primary_image_url(p_sku),
          public.product_storage_image_url_by_sku(sh.sku)
        ) AS resolved_image_url,
        COALESCE(
          sh.metal_category,
          public.classify_jewelry_metal_category(
            COALESCE(p.metal, p_sku.metal),
            COALESCE(p.metal_type, p_sku.metal_type)
          ),
          'other'
        ) AS resolved_metal_category
      FROM public.sales_history AS sh
      LEFT JOIN public.products AS p ON p.id = sh.product_id
      LEFT JOIN LATERAL (
        SELECT ps.*
        FROM public.products AS ps
        WHERE NULLIF(btrim(sh.sku), '') IS NOT NULL
          AND upper(btrim(ps.sku)) = upper(btrim(sh.sku))
        ORDER BY ps.updated_at DESC NULLS LAST
        LIMIT 1
      ) AS p_sku ON true
      WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
        AND (
          upper(btrim(COALESCE(p_store, 'ALL'))) = 'ALL'
          OR public._sales_history_resolve_store(sh) = upper(btrim(p_store))
        )
    ) AS b
  ),
  reservation_rows AS (
    SELECT
      rp.id,
      ('rsv_pay_' || rp.id::text) AS legacy_id,
      NULL::text AS product_id,
      COALESCE(ri_agg.sku_csv, '') AS sku,
      (
        CASE rp.payment_type
          WHEN 'deposit' THEN 'Залог по брони · '
          WHEN 'topup' THEN 'Доплата по брони · '
          WHEN 'buyout' THEN 'Выкуп брони (доплата) · '
          WHEN 'refund' THEN 'Возврат залога по брони · '
          ELSE 'Бронь · '
        END
        || COALESCE(NULLIF(btrim(r.customer_name), ''), 'Клиент')
        || ' ('
        || COALESCE(NULLIF(btrim(r.customer_phone), ''), '—')
        || ')'
      ) AS product_name,
      0::numeric AS weight_grams,
      NULL::bigint AS list_price_krw,
      rp.amount_krw::bigint AS price_krw,
      0 AS discount_percent,
      rp.branch AS store_location,
      NULLIF(btrim(rp.seller_name), '') AS seller_name,
      rp.seller_code,
      rp.payment_method,
      rp.created_at AS sold_at_utc,
      (rp.created_at AT TIME ZONE 'Asia/Seoul')::date AS sold_date_kst,
      ri_agg.thumb_url AS image_url,
      'other' AS metal_category,
      'reservation_payment' AS source_system,
      NULL::text AS manufacturer,
      false AS can_return,
      ('rsv_' || r.id::text) AS sale_batch_id,
      0::bigint AS scrap_trade_in_krw,
      NULL::bigint AS net_cash_delta_krw,
      false AS is_trade_in,
      true AS is_reservation_payment,
      rp.payment_type AS reservation_payment_type,
      r.status AS reservation_status,
      NULLIF(btrim(r.customer_name), '') AS reservation_customer_name,
      NULLIF(btrim(r.customer_phone), '') AS reservation_customer_phone,
      ri_agg.items_text AS reservation_items_summary,
      EXISTS (
        SELECT 1
        FROM public.reservation_payments AS rf
        WHERE rf.reservation_id = r.id
          AND rf.payment_type = 'refund'
      ) AS reservation_has_refund,
      r.expires_at AS reservation_expires_at
    FROM public.reservation_payments AS rp
    INNER JOIN public.reservations AS r ON r.id = rp.reservation_id
    LEFT JOIN LATERAL (
      SELECT
        string_agg(
          ri.sku || CASE
            WHEN NULLIF(btrim(ri.title), '') IS NOT NULL
              THEN ' — ' || btrim(ri.title)
            ELSE ''
          END,
          ', ' ORDER BY ri.sku
        ) AS items_text,
        string_agg(ri.sku, ', ' ORDER BY ri.sku) AS sku_csv,
        (
          SELECT COALESCE(
            public.product_primary_image_url(p),
            public.product_storage_image_url_by_sku(ri2.sku)
          )
          FROM public.reservation_items AS ri2
          LEFT JOIN public.products AS p ON p.id = ri2.product_id
          WHERE ri2.reservation_id = r.id
          ORDER BY ri2.sku
          LIMIT 1
        ) AS thumb_url
      FROM public.reservation_items AS ri
      WHERE ri.reservation_id = r.id
    ) AS ri_agg ON true
    WHERE (rp.created_at AT TIME ZONE 'Asia/Seoul')::date BETWEEN p_date_from AND p_date_to
      AND (
        upper(btrim(COALESCE(p_store, 'ALL'))) = 'ALL'
        OR public._norm_store_icn_ans(rp.branch) = upper(btrim(p_store))
      )
  ),
  merged AS (
    SELECT * FROM sales_rows
    UNION ALL
    SELECT * FROM reservation_rows
  )
  SELECT *
  FROM merged
  ORDER BY sold_at_utc DESC NULLS LAST, legacy_id DESC
  LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 200), 1)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

COMMENT ON FUNCTION public.list_sales_history_report(date, date, text, integer, integer) IS
  'Лента продаж + платежи по броням (reservation_payments) по дате created_at KST.';

REVOKE ALL ON FUNCTION public.list_sales_history_report(date, date, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_sales_history_report(date, date, text, integer, integer)
  TO anon, authenticated, service_role;

COMMIT;