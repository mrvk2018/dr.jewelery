-- 079: возвраты (price_krw < 0) вычитаются из кассы смены и разбивки по оплате.
BEGIN;

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
    'reservation_cash_krw', r.net_krw,
    'reservations_net_krw', r.net_krw,
    'returns_sum_krw', (-a.returns_raw)::bigint,
    'returns_count', a.returns_count,
    'net_cash_krw',
      a.gross - a.booked_gross - s.scrap_krw + r.net_krw + a.returns_raw,
    'shift_cash_krw',
      a.gross - a.booked_gross - s.scrap_krw + r.net_krw + a.returns_raw,
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
  CROSS JOIN scrap AS s;
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

  v_shift := COALESCE(v_sales_pos, 0)
    + COALESCE(v_res, 0)
    + COALESCE(v_returns_raw, 0)
    - COALESCE(v_scrap, 0);

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
    'reservation_sale_return_krw', COALESCE(v_returns_raw, 0),
    'cash_krw', v_cash,
    'card_krw', v_card,
    'transfer_krw', v_transfer,
    'by_method', COALESCE(v_rows, '{}'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_shift_cash_summary(date, date, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_shift_cash_summary(date, date, text, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_sales_history_summary(date, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_sales_history_summary(date, date, text)
  TO anon, authenticated, service_role;

COMMIT;