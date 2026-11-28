-- 083: Самостоятельная приёмка лома (scrap_metal_intakes) в ленте и кассе «Истории продаж».
-- Trade-In лом по-прежнему только через scrap_trade_in_krw в sales_history (без дубля).

BEGIN;

CREATE OR REPLACE FUNCTION public._scrap_intake_history_summary(
  p_gold_eq numeric,
  p_silver_eq numeric
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(
    trim(both ' · ' from concat_ws(
      ' · ',
      CASE
        WHEN COALESCE(p_gold_eq, 0) > 0 THEN
          'Золото 585 (прив. ' || to_char(round(p_gold_eq::numeric, 2), 'FM999999990.00') || ' г)'
        ELSE NULL
      END,
      CASE
        WHEN COALESCE(p_silver_eq, 0) > 0 THEN
          'Серебро 925 (прив. ' || to_char(round(p_silver_eq::numeric, 2), 'FM999999990.00') || ' г)'
        ELSE NULL
      END
    )),
    ''
  );
$$;

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
  reservation_expires_at timestamptz,
  is_scrap_intake boolean,
  scrap_intake_id text,
  scrap_intake_summary text,
  scrap_intake_notes text,
  scrap_intake_gold_eq_585 numeric,
  scrap_intake_silver_eq_925 numeric,
  scrap_intake_photo_urls jsonb
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
      NULL::timestamptz AS reservation_expires_at,
      false AS is_scrap_intake,
      NULL::text AS scrap_intake_id,
      NULL::text AS scrap_intake_summary,
      NULL::text AS scrap_intake_notes,
      NULL::numeric AS scrap_intake_gold_eq_585,
      NULL::numeric AS scrap_intake_silver_eq_925,
      NULL::jsonb AS scrap_intake_photo_urls
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
      r.expires_at AS reservation_expires_at,
      false AS is_scrap_intake,
      NULL::text AS scrap_intake_id,
      NULL::text AS scrap_intake_summary,
      NULL::text AS scrap_intake_notes,
      NULL::numeric AS scrap_intake_gold_eq_585,
      NULL::numeric AS scrap_intake_silver_eq_925,
      NULL::jsonb AS scrap_intake_photo_urls
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
  scrap_intake_rows AS (
    SELECT
      s.id,
      ('scrap_intake_' || s.id::text) AS legacy_id,
      NULL::text AS product_id,
      ('SCRAP-' || upper(left(replace(s.id::text, '-', ''), 8))) AS sku,
      (
        'Акт приёмки лома · '
        || upper(left(replace(s.id::text, '-', ''), 8))
      ) AS product_name,
      COALESCE(s.gold_total_eq_585, 0) + COALESCE(s.silver_total_eq_925, 0) AS weight_grams,
      NULL::bigint AS list_price_krw,
      (-GREATEST(s.total_payout_krw, 0))::bigint AS price_krw,
      0 AS discount_percent,
      s.store_location,
      NULLIF(btrim(s.accepted_by_name), '') AS seller_name,
      NULLIF(btrim(s.accepted_by_code), '') AS seller_code,
      'cash'::text AS payment_method,
      s.created_at AS sold_at_utc,
      (s.created_at AT TIME ZONE 'Asia/Seoul')::date AS sold_date_kst,
      CASE
        WHEN jsonb_typeof(s.photo_urls) = 'array' AND jsonb_array_length(s.photo_urls) > 0
          THEN s.photo_urls ->> 0
        ELSE NULL
      END AS image_url,
      CASE
        WHEN COALESCE(s.gold_total_eq_585, 0) > 0
          AND COALESCE(s.silver_total_eq_925, 0) > 0 THEN 'other'
        WHEN COALESCE(s.gold_total_eq_585, 0) > 0 THEN 'gold'
        WHEN COALESCE(s.silver_total_eq_925, 0) > 0 THEN 'silver'
        ELSE 'other'
      END AS metal_category,
      'scrap_intake'::text AS source_system,
      NULL::text AS manufacturer,
      false AS can_return,
      NULL::text AS sale_batch_id,
      0::bigint AS scrap_trade_in_krw,
      NULL::bigint AS net_cash_delta_krw,
      false AS is_trade_in,
      false AS is_reservation_payment,
      NULL::text AS reservation_payment_type,
      NULL::text AS reservation_status,
      NULL::text AS reservation_customer_name,
      NULL::text AS reservation_customer_phone,
      NULL::text AS reservation_items_summary,
      false AS reservation_has_refund,
      NULL::timestamptz AS reservation_expires_at,
      true AS is_scrap_intake,
      s.id::text AS scrap_intake_id,
      public._scrap_intake_history_summary(
        s.gold_total_eq_585,
        s.silver_total_eq_925
      ) AS scrap_intake_summary,
      NULLIF(btrim(s.notes), '') AS scrap_intake_notes,
      s.gold_total_eq_585 AS scrap_intake_gold_eq_585,
      s.silver_total_eq_925 AS scrap_intake_silver_eq_925,
      CASE
        WHEN jsonb_typeof(s.photo_urls) = 'array' THEN s.photo_urls
        ELSE '[]'::jsonb
      END AS scrap_intake_photo_urls
    FROM public.scrap_metal_intakes AS s
    WHERE (s.created_at AT TIME ZONE 'Asia/Seoul')::date BETWEEN p_date_from AND p_date_to
      AND GREATEST(s.total_payout_krw, 0) > 0
      AND (
        upper(btrim(COALESCE(p_store, 'ALL'))) = 'ALL'
        OR public._norm_store_icn_ans(s.store_location) = upper(btrim(p_store))
      )
  ),
  merged AS (
    SELECT * FROM sales_rows
    UNION ALL
    SELECT * FROM reservation_rows
    UNION ALL
    SELECT * FROM scrap_intake_rows
  )
  SELECT *
  FROM merged
  ORDER BY sold_at_utc DESC NULLS LAST, legacy_id DESC
  LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 200), 1)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

COMMENT ON FUNCTION public.list_sales_history_report(date, date, text, integer, integer) IS
  'Лента продаж + брони + самостоятельная приёмка лома (отрицательная выплата из кассы).';

CREATE OR REPLACE FUNCTION public.get_sales_history_summary(
  p_date_from date,
  p_date_to date,
  p_store text DEFAULT 'ALL'
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH filtered AS (
    SELECT sh.*, public._sales_history_resolve_store(sh) AS resolved_store,
      COALESCE(p.weight_grams, NULLIF((sh.raw_legacy_payload ->> 'weight_grams')::numeric, 0), 0) AS w_g,
      COALESCE(sh.metal_category,
        public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
        public.classify_jewelry_metal_category(p.metal, p.metal_type), 'other') AS m_cat
    FROM public.sales_history AS sh
    LEFT JOIN public.products AS p ON p.id = sh.product_id
      OR (sh.product_id IS NULL AND p.sku = sh.sku)
    WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
      AND (upper(btrim(COALESCE(p_store, 'ALL'))) = 'ALL'
        OR public._sales_history_resolve_store(sh) = upper(btrim(p_store)))
  ),
  batch_scrap AS (
    SELECT sale_batch_id, max(scrap_trade_in_krw) AS scrap_krw
    FROM filtered
    WHERE sale_batch_id IS NOT NULL AND scrap_trade_in_krw > 0
    GROUP BY sale_batch_id
  ),
  standalone_scrap AS (
    SELECT
      COALESCE(sum(GREATEST(s.total_payout_krw, 0)), 0)::bigint AS payout_krw,
      COALESCE(count(*), 0)::bigint AS intake_count
    FROM public.scrap_metal_intakes AS s
    WHERE (s.created_at AT TIME ZONE 'Asia/Seoul')::date BETWEEN p_date_from AND p_date_to
      AND GREATEST(s.total_payout_krw, 0) > 0
      AND (
        upper(btrim(COALESCE(p_store, 'ALL'))) = 'ALL'
        OR public._norm_store_icn_ans(s.store_location) = upper(btrim(p_store))
      )
  ),
  agg AS (
    SELECT
      COALESCE(sum(f.price_krw) FILTER (WHERE f.price_krw > 0), 0) AS gross,
      COALESCE(count(*) FILTER (WHERE f.price_krw > 0), 0) AS total_count,
      COALESCE(sum(f.price_krw) FILTER (
        WHERE f.price_krw > 0
          AND COALESCE(f.migration_meta ->> 'cash_via', '') = 'reservation_payments'
      ), 0) AS booked_gross,
      COALESCE(sum(f.price_krw) FILTER (WHERE f.price_krw < 0), 0) AS returns_raw,
      COALESCE(count(*) FILTER (WHERE f.price_krw < 0), 0) AS returns_count,
      COALESCE(sum(f.w_g) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'gold'), 0) AS gold_w,
      COALESCE(sum(f.price_krw) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'gold'), 0) AS gold_sum,
      COALESCE(count(*) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'gold'), 0) AS gold_count,
      COALESCE(sum(f.w_g) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'silver'), 0) AS silver_w,
      COALESCE(sum(f.price_krw) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'silver'), 0) AS silver_sum,
      COALESCE(count(*) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'silver'), 0) AS silver_count,
      COALESCE(count(*) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'other'), 0) AS other_count
    FROM filtered AS f
  ),
  reservation_cash AS (
    SELECT COALESCE(sum(rp.amount_krw), 0) AS net_krw
    FROM public.reservation_payments AS rp
    WHERE (rp.created_at AT TIME ZONE 'Asia/Seoul')::date BETWEEN p_date_from AND p_date_to
      AND (
        upper(btrim(COALESCE(p_store, 'ALL'))) = 'ALL'
        OR public._norm_store_icn_ans(rp.branch) = upper(btrim(p_store))
      )
  ),
  scrap AS (
    SELECT
      COALESCE(sum(scrap_krw), 0) AS scrap_krw,
      COALESCE(count(*), 0) AS batch_count
    FROM batch_scrap
  )
  SELECT jsonb_build_object(
    'total_sum_krw', a.gross,
    'total_count', a.total_count,
    'gross_sales_krw', a.gross,
    'trade_in_scrap_krw', s.scrap_krw,
    'trade_in_batch_count', s.batch_count,
    'standalone_scrap_payout_krw', ss.payout_krw,
    'standalone_scrap_count', ss.intake_count,
    'reservation_cash_krw', r.net_krw,
    'reservations_net_krw', r.net_krw,
    'returns_sum_krw', (-a.returns_raw)::bigint,
    'returns_count', a.returns_count,
    'net_cash_krw',
      a.gross - a.booked_gross - s.scrap_krw - ss.payout_krw + r.net_krw + a.returns_raw,
    'shift_cash_krw',
      a.gross - a.booked_gross - s.scrap_krw - ss.payout_krw + r.net_krw + a.returns_raw,
    'gold_weight_grams', a.gold_w,
    'gold_sum_krw', a.gold_sum,
    'gold_count', a.gold_count,
    'silver_weight_grams', a.silver_w,
    'silver_sum_krw', a.silver_sum,
    'silver_count', a.silver_count,
    'other_count', a.other_count
  )
  FROM agg AS a
  CROSS JOIN reservation_cash AS r
  CROSS JOIN scrap AS s
  CROSS JOIN standalone_scrap AS ss;
$$;

CREATE OR REPLACE FUNCTION public.get_shift_cash_summary(
  p_date_from date,
  p_date_to date,
  p_branch text DEFAULT 'ALL',
  p_seller_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch text;
  v_seller text := NULLIF(btrim(COALESCE(p_seller_name, '')), '');
  v_rows   jsonb;
  v_shift  bigint;
  v_scrap  bigint;
  v_standalone_scrap bigint;
  v_sales_pos bigint;
  v_gross_all bigint;
  v_res    bigint;
  v_returns_raw bigint;
  v_returns_count bigint;
  v_cash   bigint := 0;
  v_card   bigint := 0;
  v_transfer bigint := 0;
BEGIN
  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_range');
  END IF;

  IF p_branch IS NULL OR btrim(p_branch) = '' OR upper(btrim(p_branch)) = 'ALL' THEN
    v_branch := NULL;
  ELSE
    v_branch := public._norm_store_icn_ans(p_branch);
    IF v_branch IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_branch');
    END IF;
  END IF;

  WITH movements AS (
    SELECT
      COALESCE(NULLIF(btrim(sh.payment_method), ''), 'unknown') AS method,
      sh.price_krw::numeric AS amount_krw
    FROM public.sales_history AS sh
    WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
      AND sh.price_krw > 0
      AND COALESCE(sh.migration_meta ->> 'cash_via', '') IS DISTINCT FROM 'reservation_payments'
      AND (v_branch IS NULL OR public._sales_history_resolve_store(sh) = v_branch)
      AND (
        v_seller IS NULL
        OR upper(btrim(COALESCE(sh.seller_name, ''))) = upper(v_seller)
        OR upper(btrim(COALESCE(sh.seller_code, ''))) = upper(v_seller)
      )
    UNION ALL
    SELECT rp.payment_method, rp.amount_krw::numeric
    FROM public.reservation_payments AS rp
    WHERE (rp.created_at AT TIME ZONE 'Asia/Seoul')::date BETWEEN p_date_from AND p_date_to
      AND (v_branch IS NULL OR rp.branch = v_branch)
      AND (
        v_seller IS NULL
        OR upper(btrim(COALESCE(rp.seller_name, ''))) = upper(v_seller)
        OR upper(btrim(COALESCE(rp.seller_code, ''))) = upper(v_seller)
      )
    UNION ALL
    SELECT
      COALESCE(NULLIF(btrim(sh.payment_method), ''), 'unknown'),
      sh.price_krw::numeric
    FROM public.sales_history AS sh
    WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
      AND sh.price_krw < 0
      AND (v_branch IS NULL OR public._sales_history_resolve_store(sh) = v_branch)
      AND (
        v_seller IS NULL
        OR upper(btrim(COALESCE(sh.seller_name, ''))) = upper(v_seller)
        OR upper(btrim(COALESCE(sh.seller_code, ''))) = upper(v_seller)
      )
    UNION ALL
    SELECT
      'cash'::text,
      (-GREATEST(s.total_payout_krw, 0))::numeric
    FROM public.scrap_metal_intakes AS s
    WHERE (s.created_at AT TIME ZONE 'Asia/Seoul')::date BETWEEN p_date_from AND p_date_to
      AND GREATEST(s.total_payout_krw, 0) > 0
      AND (v_branch IS NULL OR public._norm_store_icn_ans(s.store_location) = v_branch)
      AND (
        v_seller IS NULL
        OR upper(btrim(COALESCE(s.accepted_by_name, ''))) = upper(v_seller)
        OR upper(btrim(COALESCE(s.accepted_by_code, ''))) = upper(v_seller)
      )
  ),
  by_method AS (
    SELECT method, COALESCE(sum(amount_krw), 0)::bigint AS amount_krw
    FROM movements
    GROUP BY method
  )
  SELECT COALESCE(jsonb_object_agg(method, amount_krw), '{}'::jsonb)
  INTO v_rows
  FROM by_method;

  SELECT COALESCE(sum(sh.price_krw), 0)::bigint
  INTO v_sales_pos
  FROM public.sales_history AS sh
  WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
    AND sh.price_krw > 0
    AND COALESCE(sh.migration_meta ->> 'cash_via', '') IS DISTINCT FROM 'reservation_payments'
    AND (v_branch IS NULL OR public._sales_history_resolve_store(sh) = v_branch)
    AND (
      v_seller IS NULL
      OR upper(btrim(COALESCE(sh.seller_name, ''))) = upper(v_seller)
      OR upper(btrim(COALESCE(sh.seller_code, ''))) = upper(v_seller)
    );

  SELECT COALESCE(sum(sh.price_krw), 0)::bigint
  INTO v_gross_all
  FROM public.sales_history AS sh
  WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
    AND sh.price_krw > 0
    AND (v_branch IS NULL OR public._sales_history_resolve_store(sh) = v_branch)
    AND (
      v_seller IS NULL
      OR upper(btrim(COALESCE(sh.seller_name, ''))) = upper(v_seller)
      OR upper(btrim(COALESCE(sh.seller_code, ''))) = upper(v_seller)
    );

  SELECT COALESCE(sum(rp.amount_krw), 0)::bigint
  INTO v_res
  FROM public.reservation_payments AS rp
  WHERE (rp.created_at AT TIME ZONE 'Asia/Seoul')::date BETWEEN p_date_from AND p_date_to
    AND (v_branch IS NULL OR rp.branch = v_branch)
    AND (
      v_seller IS NULL
      OR upper(btrim(COALESCE(rp.seller_name, ''))) = upper(v_seller)
      OR upper(btrim(COALESCE(rp.seller_code, ''))) = upper(v_seller)
    );

  SELECT
    COALESCE(sum(sh.price_krw), 0)::bigint,
    COALESCE(count(*), 0)::bigint
  INTO v_returns_raw, v_returns_count
  FROM public.sales_history AS sh
  WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
    AND sh.price_krw < 0
    AND (v_branch IS NULL OR public._sales_history_resolve_store(sh) = v_branch)
    AND (
      v_seller IS NULL
      OR upper(btrim(COALESCE(sh.seller_name, ''))) = upper(v_seller)
      OR upper(btrim(COALESCE(sh.seller_code, ''))) = upper(v_seller)
    );

  SELECT COALESCE(sum(batch.scrap_krw), 0)::bigint
  INTO v_scrap
  FROM (
    SELECT max(sh.scrap_trade_in_krw) AS scrap_krw
    FROM public.sales_history AS sh
    WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
      AND sh.sale_batch_id IS NOT NULL
      AND sh.scrap_trade_in_krw > 0
      AND (v_branch IS NULL OR public._sales_history_resolve_store(sh) = v_branch)
      AND (
        v_seller IS NULL
        OR upper(btrim(COALESCE(sh.seller_name, ''))) = upper(v_seller)
        OR upper(btrim(COALESCE(sh.seller_code, ''))) = upper(v_seller)
      )
    GROUP BY sh.sale_batch_id
  ) AS batch;

  SELECT COALESCE(sum(GREATEST(s.total_payout_krw, 0)), 0)::bigint
  INTO v_standalone_scrap
  FROM public.scrap_metal_intakes AS s
  WHERE (s.created_at AT TIME ZONE 'Asia/Seoul')::date BETWEEN p_date_from AND p_date_to
    AND GREATEST(s.total_payout_krw, 0) > 0
    AND (v_branch IS NULL OR public._norm_store_icn_ans(s.store_location) = v_branch)
    AND (
      v_seller IS NULL
      OR upper(btrim(COALESCE(s.accepted_by_name, ''))) = upper(v_seller)
      OR upper(btrim(COALESCE(s.accepted_by_code, ''))) = upper(v_seller)
    );

  v_shift := COALESCE(v_sales_pos, 0)
    + COALESCE(v_res, 0)
    + COALESCE(v_returns_raw, 0)
    - COALESCE(v_scrap, 0)
    - COALESCE(v_standalone_scrap, 0);

  v_cash := COALESCE((v_rows ->> 'cash')::bigint, 0);
  v_card := COALESCE((v_rows ->> 'card')::bigint, 0);
  v_transfer := COALESCE((v_rows ->> 'transfer')::bigint, 0);

  RETURN jsonb_build_object(
    'ok', true,
    'branch', COALESCE(v_branch, 'ALL'),
    'seller', v_seller,
    'gross_sales_krw', COALESCE(v_gross_all, 0),
    'sales_cash_krw', COALESCE(v_sales_pos, 0),
    'shift_cash_krw', v_shift,
    'net_cash_krw', v_shift,
    'reservation_cash_krw', COALESCE(v_res, 0),
    'reservations_net_krw', COALESCE(v_res, 0),
    'returns_sum_krw', (-COALESCE(v_returns_raw, 0))::bigint,
    'returns_count', COALESCE(v_returns_count, 0),
    'trade_in_scrap_krw', COALESCE(v_scrap, 0),
    'standalone_scrap_payout_krw', COALESCE(v_standalone_scrap, 0),
    'reservation_sale_return_krw', COALESCE(v_returns_raw, 0),
    'cash_krw', v_cash,
    'card_krw', v_card,
    'transfer_krw', v_transfer,
    'by_method', COALESCE(v_rows, '{}'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_sales_history_report(date, date, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_sales_history_report(date, date, text, integer, integer)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_sales_history_summary(date, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_sales_history_summary(date, date, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_shift_cash_summary(date, date, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_shift_cash_summary(date, date, text, text)
  TO anon, authenticated, service_role;

COMMIT;