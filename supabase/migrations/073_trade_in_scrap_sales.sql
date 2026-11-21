-- 073: POS Trade-In — sale_batch_id, атомарная продажа + акт лома, округление лома вниз до 1 000 ₩.
BEGIN;

-- ---------------------------------------------------------------------------
-- Колонки связи
-- ---------------------------------------------------------------------------
ALTER TABLE public.scrap_metal_intakes
  ADD COLUMN IF NOT EXISTS sale_batch_id text,
  ADD COLUMN IF NOT EXISTS is_trade_in boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_scrap_metal_intakes_sale_batch
  ON public.scrap_metal_intakes (sale_batch_id)
  WHERE sale_batch_id IS NOT NULL;

COMMENT ON COLUMN public.scrap_metal_intakes.sale_batch_id IS
  'POS batch (pos_* uuid) для Trade-In; один акт на чек.';
COMMENT ON COLUMN public.scrap_metal_intakes.is_trade_in IS
  'Акт создан вместе с POS-продажей (не осиротевший черновик).';

ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS sale_batch_id text,
  ADD COLUMN IF NOT EXISTS scrap_trade_in_krw bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS net_cash_delta_krw bigint;

CREATE INDEX IF NOT EXISTS idx_sales_history_sale_batch
  ON public.sales_history (sale_batch_id)
  WHERE sale_batch_id IS NOT NULL;

COMMENT ON COLUMN public.sales_history.sale_batch_id IS
  'Общий id POS-чека (совпадает с migration_meta.pos_order_id).';
COMMENT ON COLUMN public.sales_history.scrap_trade_in_krw IS
  'Зачёт лома по чеку (дублируется на строках batch; в отчётах — max по batch).';
COMMENT ON COLUMN public.sales_history.net_cash_delta_krw IS
  'Чистый расчёт: сумма изделий − лом (+ клиент платит / − доплата).';

-- ---------------------------------------------------------------------------
-- Округление лома вниз до 1 000 ₩
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.round_krw_down_1000(p_amount numeric)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN coalesce(p_amount, 0) <= 0 THEN 0
    ELSE (floor(p_amount / 1000.0) * 1000)::integer
  END;
$$;

CREATE OR REPLACE FUNCTION public._scrap_payout_split(
  p_total_eq numeric,
  p_offset numeric,
  p_standard_rate integer,
  p_tradein_rate integer
)
RETURNS TABLE(
  tradein_paid_grams numeric,
  standard_paid_grams numeric,
  payout_krw integer
)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_total numeric := GREATEST(COALESCE(p_total_eq, 0), 0);
  v_offset numeric := GREATEST(COALESCE(p_offset, 0), 0);
  v_tradein numeric;
  v_standard numeric;
  v_raw integer;
BEGIN
  v_tradein := LEAST(v_offset, v_total);
  v_standard := GREATEST(v_total - v_tradein, 0);
  tradein_paid_grams := round(v_tradein, 4);
  standard_paid_grams := round(v_standard, 4);
  v_raw := GREATEST(
    round(v_tradein * GREATEST(COALESCE(p_tradein_rate, 0), 0))::integer
    + round(v_standard * GREATEST(COALESCE(p_standard_rate, 0), 0))::integer,
    0
  );
  payout_krw := public.round_krw_down_1000(v_raw);
  RETURN NEXT;
END;
$$;

-- ---------------------------------------------------------------------------
-- archive_admin_pos_sale + optional Trade-In scrap payload
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.archive_admin_pos_sale(jsonb, text, text, text);

CREATE OR REPLACE FUNCTION public.archive_admin_pos_sale(
  p_lines jsonb,
  p_seller_name text DEFAULT NULL,
  p_payment_method text DEFAULT NULL,
  p_seller_code text DEFAULT NULL,
  p_scrap_payload jsonb DEFAULT NULL,
  p_trade_in_net_cash_delta_krw integer DEFAULT NULL,
  p_trade_in_scrap_total_krw integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line jsonb;
  v_pid text;
  v_discount integer;
  v_row public.products%ROWTYPE;
  v_list bigint;
  v_final bigint;
  v_store text;
  v_payment text;
  v_seller text;
  v_metal text;
  v_sold bigint := 0;
  v_order_id text;
  v_history_id uuid;
  v_code_input text;
  v_seller_code text;
  v_resolved_name text;
  v_gold_pct numeric;
  v_silver_pct numeric;
  v_display_seller_name text;
  v_commission_pct numeric;
  v_commission_krw integer;
  v_gold_items jsonb;
  v_silver_items jsonb;
  v_gold_total numeric;
  v_silver_total numeric;
  v_gold_split record;
  v_silver_split record;
  v_scrap_total integer := 0;
  v_net_delta integer;
  v_scrap_id uuid;
  v_has_scrap boolean := false;
BEGIN
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array'
     OR jsonb_array_length(p_lines) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'empty_cart');
  END IF;

  v_seller := NULLIF(btrim(COALESCE(p_seller_name, '')), '');
  v_payment := NULLIF(btrim(COALESCE(p_payment_method, '')), '');
  IF v_payment IS NOT NULL
     AND v_payment NOT IN ('cash', 'card', 'transfer') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_payment_method');
  END IF;
  IF v_seller IS NULL OR v_payment IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'seller_and_payment_required');
  END IF;

  v_code_input := NULLIF(upper(btrim(COALESCE(p_seller_code, ''))), '');
  IF v_code_input IS NOT NULL THEN
    SELECT s.promo_code, s.name, s.gold_commission_percent, s.silver_commission_percent
    INTO v_seller_code, v_resolved_name, v_gold_pct, v_silver_pct
    FROM public.sellers AS s
    WHERE s.promo_code = v_code_input AND s.is_active;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'seller_not_found');
    END IF;
  ELSE
    SELECT r.promo_code, r.name, r.gold_commission_percent, r.silver_commission_percent
    INTO v_seller_code, v_resolved_name, v_gold_pct, v_silver_pct
    FROM public.resolve_seller_by_name(v_seller) AS r
    LIMIT 1;
    IF v_seller_code IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'seller_not_resolved');
    END IF;
  END IF;

  v_display_seller_name := CASE
    WHEN v_seller_code = 'ADMIN' THEN v_seller
    ELSE COALESCE(v_resolved_name, v_seller)
  END;

  v_order_id := 'pos_' || replace(gen_random_uuid()::text, '-', '');
  v_has_scrap := p_scrap_payload IS NOT NULL
    AND jsonb_typeof(p_scrap_payload) = 'object';

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_pid := NULLIF(btrim(COALESCE(v_line ->> 'product_id', '')), '');
    IF v_pid IS NULL THEN CONTINUE; END IF;

    v_discount := LEAST(GREATEST(COALESCE((v_line ->> 'discount_percent')::integer, 0), 0), 100);

    SELECT * INTO v_row FROM public.products AS p WHERE p.id = v_pid FOR UPDATE;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', format('product_not_found:%s', v_pid));
    END IF;
    IF v_row.status NOT IN ('active', 'reserved', 'hidden') THEN
      RETURN jsonb_build_object('ok', false, 'error', format('product_unavailable:%s', v_pid));
    END IF;

    v_list := public.round_krw_up_1000(GREATEST(COALESCE(v_row.sale_price, 0), 0)::numeric)::bigint;
    v_final := public.round_krw_up_1000(v_list::numeric * (100 - v_discount) / 100.0)::bigint;
    v_store := public._norm_store_icn_ans(v_row.store_location);
    v_metal := public.classify_jewelry_metal_category(
      NULLIF(btrim(v_row.metal), ''),
      NULLIF(btrim(v_row.metal_type), '')
    );
    v_commission_pct := public.seller_commission_rate_for_metal(v_gold_pct, v_silver_pct, v_metal);
    v_commission_krw := public.seller_commission_krw(v_final, v_list, v_commission_pct);

    UPDATE public.products SET status = 'sold', stock_quantity = 0, updated_at = now()
    WHERE id = v_pid;

    SELECT sh.id INTO v_history_id FROM public.sales_history AS sh
    WHERE sh.product_id = v_pid
    ORDER BY sh.sold_at_utc DESC NULLS LAST, sh.legacy_id DESC
    LIMIT 1;

    IF v_history_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', format('sales_history_missing_after_trigger:%s', v_pid));
    END IF;

    UPDATE public.sales_history AS sh SET
      price_krw = v_final,
      list_price_krw = v_list,
      discount_percent = v_discount,
      payment_method = v_payment,
      seller_code = v_seller_code,
      seller_name = v_display_seller_name,
      store_location = v_store,
      metal_category = v_metal,
      commission_percent = COALESCE(v_commission_pct, 0),
      commission_krw = COALESCE(v_commission_krw, 0),
      sale_batch_id = v_order_id,
      migration_meta = COALESCE(sh.migration_meta, '{}'::jsonb) || jsonb_build_object(
        'pos_order_id', v_order_id,
        'pos_seller_name', v_seller,
        'pos_seller_code', v_seller_code,
        'pos_payment_method', v_payment,
        'logged_by', 'archive_admin_pos_sale',
        'trade_in', v_has_scrap
      )
    WHERE sh.id = v_history_id;
  END LOOP;

  v_sold := jsonb_array_length(p_lines);

  IF v_has_scrap THEN
    v_gold_items := public._scrap_norm_items(
      COALESCE(p_scrap_payload -> 'gold_items', '[]'::jsonb), 585, 'equivalent_585_weight');
    v_silver_items := public._scrap_norm_items(
      COALESCE(p_scrap_payload -> 'silver_items', '[]'::jsonb), 925, 'equivalent_925_weight');
    v_gold_total := public._scrap_total_eq(v_gold_items, 'equivalent_585_weight');
    v_silver_total := public._scrap_total_eq(v_silver_items, 'equivalent_925_weight');

    SELECT * INTO v_gold_split FROM public._scrap_payout_split(
      v_gold_total,
      COALESCE((p_scrap_payload ->> 'gold_purchase_offset_grams')::numeric, 0),
      COALESCE((p_scrap_payload ->> 'gold_standard_rate_krw')::integer, 0),
      COALESCE((p_scrap_payload ->> 'gold_tradein_rate_krw')::integer, 0));
    SELECT * INTO v_silver_split FROM public._scrap_payout_split(
      v_silver_total,
      COALESCE((p_scrap_payload ->> 'silver_purchase_offset_grams')::numeric, 0),
      COALESCE((p_scrap_payload ->> 'silver_standard_rate_krw')::integer, 0),
      COALESCE((p_scrap_payload ->> 'silver_tradein_rate_krw')::integer, 0));

    v_scrap_total := public.round_krw_down_1000(
      (v_gold_split.payout_krw + v_silver_split.payout_krw)::numeric);

    IF p_trade_in_scrap_total_krw IS NOT NULL AND p_trade_in_scrap_total_krw > 0 THEN
      v_scrap_total := public.round_krw_down_1000(p_trade_in_scrap_total_krw::numeric);
    END IF;

    v_net_delta := p_trade_in_net_cash_delta_krw;

    INSERT INTO public.scrap_metal_intakes (
      store_location, accepted_by_code, accepted_by_name, notes, photo_urls, status,
      gold_items, gold_total_eq_585, gold_standard_rate_krw, gold_tradein_rate_krw,
      gold_purchase_offset_grams, gold_tradein_paid_grams, gold_standard_paid_grams, gold_payout_krw,
      silver_items, silver_total_eq_925, silver_standard_rate_krw, silver_tradein_rate_krw,
      silver_purchase_offset_grams, silver_tradein_paid_grams, silver_standard_paid_grams, silver_payout_krw,
      total_payout_krw, sale_batch_id, is_trade_in
    ) VALUES (
      upper(btrim(COALESCE(p_scrap_payload ->> 'store_location', 'ICN'))),
      NULLIF(btrim(COALESCE(p_scrap_payload ->> 'accepted_by_code', '')), ''),
      btrim(COALESCE(p_scrap_payload ->> 'accepted_by_name', 'POS Trade-In')),
      NULLIF(btrim(COALESCE(p_scrap_payload ->> 'notes', '')), ''),
      COALESCE(p_scrap_payload -> 'photo_urls', '[]'::jsonb),
      'in_stock',
      v_gold_items, v_gold_total,
      GREATEST(COALESCE((p_scrap_payload ->> 'gold_standard_rate_krw')::integer, 0), 0),
      GREATEST(COALESCE((p_scrap_payload ->> 'gold_tradein_rate_krw')::integer, 0), 0),
      GREATEST(COALESCE((p_scrap_payload ->> 'gold_purchase_offset_grams')::numeric, 0), 0),
      v_gold_split.tradein_paid_grams, v_gold_split.standard_paid_grams, v_gold_split.payout_krw,
      v_silver_items, v_silver_total,
      GREATEST(COALESCE((p_scrap_payload ->> 'silver_standard_rate_krw')::integer, 0), 0),
      GREATEST(COALESCE((p_scrap_payload ->> 'silver_tradein_rate_krw')::integer, 0), 0),
      GREATEST(COALESCE((p_scrap_payload ->> 'silver_purchase_offset_grams')::numeric, 0), 0),
      v_silver_split.tradein_paid_grams, v_silver_split.standard_paid_grams, v_silver_split.payout_krw,
      v_scrap_total, v_order_id, true
    ) RETURNING id INTO v_scrap_id;

    UPDATE public.sales_history AS sh SET
      scrap_trade_in_krw = v_scrap_total,
      net_cash_delta_krw = v_net_delta,
      migration_meta = COALESCE(sh.migration_meta, '{}'::jsonb) || jsonb_build_object(
        'trade_in_scrap_id', v_scrap_id::text,
        'trade_in_scrap_krw', v_scrap_total,
        'trade_in_net_cash_delta_krw', v_net_delta
      )
    WHERE sh.sale_batch_id = v_order_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'order_id', v_order_id,
    'lines', v_sold,
    'seller_code', v_seller_code,
    'scrap_total_krw', CASE WHEN v_has_scrap THEN v_scrap_total ELSE NULL END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.archive_admin_pos_sale(jsonb, text, text, text, jsonb, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.archive_admin_pos_sale(jsonb, text, text, text, jsonb, integer, integer)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- get_sales_history_summary — расшифровка Trade-In
-- ---------------------------------------------------------------------------
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
  )
  SELECT jsonb_build_object(
    'total_sum_krw', COALESCE(sum(f.price_krw) FILTER (WHERE f.price_krw > 0), 0),
    'total_count', COALESCE(count(*) FILTER (WHERE f.price_krw > 0), 0)::bigint,
    'gross_sales_krw', COALESCE(sum(f.price_krw) FILTER (WHERE f.price_krw > 0), 0),
    'trade_in_scrap_krw', COALESCE((SELECT sum(scrap_krw) FROM batch_scrap), 0),
    'trade_in_batch_count', COALESCE((SELECT count(*) FROM batch_scrap), 0)::bigint,
    'net_cash_krw', COALESCE(sum(f.price_krw) FILTER (WHERE f.price_krw > 0), 0)
      - COALESCE((SELECT sum(scrap_krw) FROM batch_scrap), 0),
    'gold_weight_grams', COALESCE(sum(f.w_g) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'gold'), 0),
    'gold_sum_krw', COALESCE(sum(f.price_krw) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'gold'), 0),
    'gold_count', COALESCE(count(*) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'gold'), 0)::bigint,
    'silver_weight_grams', COALESCE(sum(f.w_g) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'silver'), 0),
    'silver_sum_krw', COALESCE(sum(f.price_krw) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'silver'), 0),
    'silver_count', COALESCE(count(*) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'silver'), 0)::bigint,
    'other_count', COALESCE(count(*) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'other'), 0)::bigint
  )
  FROM filtered AS f;
$$;

-- ---------------------------------------------------------------------------
-- list_sales_history_report — Trade-In поля
-- ---------------------------------------------------------------------------
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
  is_trade_in boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, storage
AS $$
  WITH base AS (
    SELECT sh.*, public._sales_history_resolve_store(sh) AS resolved_store,
      COALESCE(p.weight_grams, p_sku.weight_grams) AS p_weight,
      COALESCE(p.status, p_sku.status) AS p_status,
      COALESCE(
        NULLIF(btrim(p.name ->> 'ru'), ''),
        NULLIF(btrim(p.name ->> 'ko'), ''),
        NULLIF(btrim(sh.sku), '')
      ) AS p_name,
      COALESCE(public.product_primary_image_url(p), public.product_primary_image_url(p_sku),
        public.product_storage_image_url_by_sku(sh.sku)) AS resolved_image_url,
      COALESCE(sh.metal_category,
        public.classify_jewelry_metal_category(COALESCE(p.metal, p_sku.metal), COALESCE(p.metal_type, p_sku.metal_type)),
        'other') AS resolved_metal_category
    FROM public.sales_history AS sh
    LEFT JOIN public.products AS p ON p.id = sh.product_id
    LEFT JOIN LATERAL (
      SELECT ps.* FROM public.products AS ps
      WHERE NULLIF(btrim(sh.sku), '') IS NOT NULL AND upper(btrim(ps.sku)) = upper(btrim(sh.sku))
      ORDER BY ps.updated_at DESC NULLS LAST LIMIT 1
    ) AS p_sku ON true
    WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
      AND (upper(btrim(COALESCE(p_store, 'ALL'))) = 'ALL'
        OR public._sales_history_resolve_store(sh) = upper(btrim(p_store)))
  )
  SELECT b.id, b.legacy_id, b.product_id, b.sku, b.p_name AS product_name,
    COALESCE(b.p_weight, public.sales_history_payload_weight_grams(b.raw_legacy_payload)) AS weight_grams,
    COALESCE(b.list_price_krw, b.price_krw) AS list_price_krw,
    b.price_krw, COALESCE(b.discount_percent, 0), b.resolved_store AS store_location,
    NULLIF(btrim(b.seller_name), ''), b.seller_code, b.payment_method,
    b.sold_at_utc, b.sold_date_kst, b.resolved_image_url AS image_url,
    b.resolved_metal_category AS metal_category, b.source_system,
    NULLIF(btrim(b.raw_legacy_payload ->> 'Manager'), '') AS manufacturer,
  (
      b.price_krw > 0 AND b.legacy_id LIKE 'pwa_id_%'
      AND COALESCE(b.source_system, '') IS DISTINCT FROM 'DrJaw'
      AND b.p_status = 'sold'
      AND NOT EXISTS (
        SELECT 1 FROM public.sales_history AS r
        WHERE (r.migration_meta ->> 'reverses_legacy_id') = b.legacy_id
          AND COALESCE(r.migration_meta ->> 'type', '') = 'return')
    ) AS can_return,
    b.sale_batch_id,
    b.scrap_trade_in_krw,
    b.net_cash_delta_krw,
    (b.scrap_trade_in_krw > 0 OR coalesce(b.migration_meta ->> 'trade_in', '') = 'true') AS is_trade_in
  FROM base AS b
  ORDER BY b.sold_at_utc DESC NULLS LAST, b.legacy_id DESC
  LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 200), 1)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

REVOKE ALL ON FUNCTION public.list_sales_history_report(date, date, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_sales_history_report(date, date, text, integer, integer)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_sales_history_summary(date, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_sales_history_summary(date, date, text)
  TO anon, authenticated, service_role;

COMMIT;