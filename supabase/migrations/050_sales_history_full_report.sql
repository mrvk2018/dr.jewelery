-- 050: отчёт «История продаж» — колонки, POS, триггер, RPC списка и сводки.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Колонки sales_history
-- ---------------------------------------------------------------------------
ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS payment_method text,
  ADD COLUMN IF NOT EXISTS store_location text,
  ADD COLUMN IF NOT EXISTS list_price_krw bigint,
  ADD COLUMN IF NOT EXISTS discount_percent integer NOT NULL DEFAULT 0;

ALTER TABLE public.sales_history DROP CONSTRAINT IF EXISTS sales_history_store_location_check;
ALTER TABLE public.sales_history
  ADD CONSTRAINT sales_history_store_location_check
  CHECK (
    store_location IS NULL
    OR upper(btrim(store_location)) IN ('ICN', 'ANS')
  );

ALTER TABLE public.sales_history DROP CONSTRAINT IF EXISTS sales_history_discount_percent_check;
ALTER TABLE public.sales_history
  ADD CONSTRAINT sales_history_discount_percent_check
  CHECK (discount_percent >= 0 AND discount_percent <= 100);

COMMENT ON COLUMN public.sales_history.payment_method IS
  'POS: cash | card | transfer';
COMMENT ON COLUMN public.sales_history.store_location IS
  'Точка продажи на момент sale (ICN | ANS).';
COMMENT ON COLUMN public.sales_history.list_price_krw IS
  'Витринная цена до скидки (KRW).';
COMMENT ON COLUMN public.sales_history.discount_percent IS
  'Скидка POS / витрина на момент продажи, %.';

CREATE OR REPLACE FUNCTION public._sales_history_resolve_store(p_row public.sales_history)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT upper(btrim(COALESCE(
    NULLIF(btrim(p_row.store_location), ''),
    NULLIF(btrim(p_row.raw_legacy_payload ->> 'store_location'), ''),
    CASE
      WHEN lower(btrim(COALESCE(p_row.migration_meta ->> 'mart', ''))) IN ('d.y №2', 'ansan', 'ans', 'ансан')
        OR btrim(COALESCE(p_row.migration_meta ->> 'mart', '')) = 'D.Y №2' THEN 'ANS'
      WHEN btrim(COALESCE(p_row.migration_meta ->> 'mart', '')) <> '' THEN 'ICN'
      ELSE NULL
    END
  )));
$$;

-- Бэкфилл store / list / discount из payload
UPDATE public.sales_history AS sh
SET
  store_location = COALESCE(
    NULLIF(btrim(sh.store_location), ''),
    public._norm_store_icn_ans(NULLIF(btrim(sh.raw_legacy_payload ->> 'store_location'), '')),
    CASE
      WHEN lower(btrim(COALESCE(sh.migration_meta ->> 'mart', ''))) LIKE '%№2%'
        OR lower(btrim(COALESCE(sh.migration_meta ->> 'mart', ''))) LIKE '%ансан%' THEN 'ANS'
      WHEN btrim(COALESCE(sh.migration_meta ->> 'mart', '')) <> '' THEN 'ICN'
      ELSE NULL
    END
  ),
  list_price_krw = COALESCE(
    sh.list_price_krw,
    (sh.raw_legacy_payload ->> 'old_price')::bigint,
    (sh.raw_legacy_payload ->> 'sale_price')::bigint,
    sh.price_krw
  ),
  discount_percent = COALESCE(
    sh.discount_percent,
    (sh.raw_legacy_payload ->> 'discount_percent')::integer,
    0
  )
WHERE sh.price_krw IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2) log_future_sale_to_history — снимок store / list / discount
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_future_sale_to_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_legacy_id        text;
  v_image_url        text;
  v_price_krw        bigint;
  v_list_krw         bigint;
  v_discount         integer;
  v_store            text;
  v_payload          jsonb;
  v_sold_at_utc      timestamptz;
  v_sold_kst         date;
  v_metal_category   text;
  v_seller_code      text;
  v_seller_name      text;
  v_commission_pct   numeric(5, 2);
  v_commission_krw   integer;
  v_product_name     text;
BEGIN
  IF NOT (NEW.status = 'sold' AND OLD.status IS DISTINCT FROM 'sold') THEN
    RETURN NEW;
  END IF;

  v_legacy_id := 'pwa_id_' || NEW.id;
  v_sold_at_utc := timezone('utc', now());
  v_sold_kst := (timezone('Asia/Seoul', now()))::date;
  v_payload := row_to_json(NEW)::jsonb;
  v_list_krw := GREATEST(COALESCE(NEW.old_price, NEW.sale_price, 0), 0)::bigint;
  v_discount := GREATEST(COALESCE(NEW.discount_percent, 0), 0);
  v_price_krw := GREATEST(COALESCE(NEW.sale_price, 0), 0)::bigint;
  v_store := public._norm_store_icn_ans(NEW.store_location);

  v_metal_category := public.classify_jewelry_metal_category(
    NULLIF(btrim(NEW.metal), ''),
    NULLIF(btrim(NEW.metal_type), '')
  );

  v_product_name := COALESCE(
    NULLIF(btrim(NEW.name ->> 'ru'), ''),
    NULLIF(btrim(NEW.name ->> 'ko'), ''),
    NULLIF(btrim(NEW.sku), '')
  );

  SELECT r.seller_code, r.seller_name
  INTO v_seller_code, v_seller_name
  FROM public.resolve_seller_for_product_sale(NEW.id, NEW.sku, v_product_name) AS r
  LIMIT 1;

  v_commission_pct := 0;
  v_commission_krw := 0;
  IF v_seller_code IS NOT NULL THEN
    SELECT
      public.seller_commission_rate_for_metal(
        s.app_gold_commission_percent,
        s.app_silver_commission_percent,
        v_metal_category
      ),
      s.name
    INTO v_commission_pct, v_seller_name
    FROM public.sellers AS s
    WHERE s.promo_code = upper(v_seller_code);

    v_commission_krw := round(
      (v_price_krw::numeric * COALESCE(v_commission_pct, 0) / 100.0)
    )::integer;
  END IF;

  v_image_url := NULLIF(btrim(COALESCE(NEW.image_url, '')), '');

  INSERT INTO public.sales_history (
    legacy_id, sku, product_id, price_krw, list_price_krw, discount_percent,
    store_location, payment_method,
    sold_at_utc, sold_date_kst, image_url, photo_status, import_batch_id,
    source_system, raw_legacy_payload, migration_meta,
    seller_code, seller_name, metal_category, commission_percent, commission_krw
  )
  VALUES (
    v_legacy_id, NEW.sku, NEW.id, v_price_krw, v_list_krw, v_discount,
    v_store, NULL,
    v_sold_at_utc, v_sold_kst, v_image_url, 'success',
    '00000000-0000-0000-0000-000000000000'::uuid,
    'pwa_store', v_payload,
    jsonb_build_object(
      'source_system', 'pwa_store',
      'logged_by', 'trg_log_pwa_sale',
      'product_id', NEW.id,
      'store_location', v_store,
      'sold_at_utc', v_sold_at_utc,
      'sold_date_kst', v_sold_kst::text
    ),
    v_seller_code, v_seller_name, v_metal_category,
    COALESCE(v_commission_pct, 0), COALESCE(v_commission_krw, 0)
  )
  ON CONFLICT (legacy_id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3) archive_admin_pos_sale — POS-касса
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.archive_admin_pos_sale(
  p_sale_lines jsonb,
  p_seller_name text DEFAULT NULL,
  p_payment_method text DEFAULT NULL
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
  v_legacy text;
  v_sold bigint := 0;
  v_order_id text;
BEGIN
  IF p_sale_lines IS NULL OR jsonb_typeof(p_sale_lines) <> 'array'
     OR jsonb_array_length(p_sale_lines) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'empty_cart');
  END IF;

  v_payment := NULLIF(btrim(COALESCE(p_payment_method, '')), '');
  v_order_id := 'pos_' || replace(gen_random_uuid()::text, '-', '');

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_sale_lines) LOOP
    v_pid := NULLIF(btrim(COALESCE(v_line ->> 'product_id', '')), '');
    IF v_pid IS NULL THEN
      CONTINUE;
    END IF;

    v_discount := GREATEST(
      COALESCE((v_line ->> 'discount_percent')::integer, 0),
      0
    );
    v_discount := LEAST(v_discount, 100);

    SELECT * INTO v_row
    FROM public.products AS p
  WHERE p.id = v_pid
    FOR UPDATE;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', format('product_not_found:%s', v_pid));
    END IF;

    IF v_row.status NOT IN ('active', 'reserved', 'hidden') THEN
      RETURN jsonb_build_object('ok', false, 'error', format('product_unavailable:%s', v_pid));
    END IF;

    v_list := GREATEST(COALESCE(v_row.sale_price, 0), 0)::bigint;
    v_final := round(v_list::numeric * (100 - v_discount) / 100.0)::bigint;
    v_store := public._norm_store_icn_ans(v_row.store_location);

    UPDATE public.products AS p
    SET
      status = 'sold',
      stock_quantity = 0,
      updated_at = now()
    WHERE p.id = v_pid;

    v_legacy := 'pwa_id_' || v_pid;

    UPDATE public.sales_history AS sh
    SET
      price_krw = v_final,
      list_price_krw = v_list,
      discount_percent = v_discount,
      payment_method = v_payment,
      store_location = v_store
    WHERE sh.legacy_id = v_legacy;
  END LOOP;

  v_sold := jsonb_array_length(p_sale_lines);

  RETURN jsonb_build_object(
    'ok', true,
    'order_id', v_order_id,
    'lines', v_sold
  );
END;
$$;

REVOKE ALL ON FUNCTION public.archive_admin_pos_sale(jsonb, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.archive_admin_pos_sale(jsonb, text, text)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) list_sales_history_report
-- ---------------------------------------------------------------------------
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
  can_return boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH base AS (
    SELECT
      sh.*,
      public._sales_history_resolve_store(sh) AS resolved_store,
      p.weight_grams AS p_weight,
      COALESCE(
        NULLIF(btrim(p.name ->> 'ru'), ''),
        NULLIF(btrim(p.name ->> 'ko'), ''),
        NULLIF(btrim(p.name ->> 'en'), ''),
        NULLIF(btrim(sh.sku), '')
      ) AS p_name,
      p.status AS p_status,
      COALESCE(
        NULLIF(btrim(sh.image_url), ''),
        NULLIF(btrim(p.image_url), ''),
        NULLIF(btrim(p.images[1]), ''),
        CASE
          WHEN COALESCE(array_length(p.additional_images, 1), 0) > 0 THEN
            NULLIF(btrim(p.additional_images[1]), '')
          ELSE NULL
        END
      ) AS resolved_image_url
    FROM public.sales_history AS sh
    LEFT JOIN public.products AS p ON p.id = sh.product_id
    WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
      AND (
        upper(btrim(COALESCE(p_store, 'ALL'))) = 'ALL'
        OR public._sales_history_resolve_store(sh) = upper(btrim(p_store))
      )
  )
  SELECT
    b.id,
    b.legacy_id,
    b.product_id,
    b.sku,
    b.p_name AS product_name,
    COALESCE(
      b.p_weight,
      (b.raw_legacy_payload ->> 'weight_grams')::numeric
    ) AS weight_grams,
    COALESCE(b.list_price_krw, b.price_krw) AS list_price_krw,
    b.price_krw,
    COALESCE(b.discount_percent, 0) AS discount_percent,
    b.resolved_store AS store_location,
    b.seller_name,
    b.seller_code,
    b.payment_method,
    b.sold_at_utc,
    b.sold_date_kst,
    b.resolved_image_url AS image_url,
    b.metal_category,
    b.source_system,
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
    ) AS can_return
  FROM base AS b
  ORDER BY b.sold_at_utc DESC NULLS LAST, b.legacy_id DESC
  LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 200), 1)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

-- ---------------------------------------------------------------------------
-- 5) get_sales_history_summary
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
    SELECT
      sh.*,
      public._sales_history_resolve_store(sh) AS resolved_store,
      COALESCE(
        p.weight_grams,
        (sh.raw_legacy_payload ->> 'weight_grams')::numeric,
        0
      ) AS w_g,
      COALESCE(
        sh.metal_category,
        public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
        'other'
      ) AS m_cat
    FROM public.sales_history AS sh
    LEFT JOIN public.products AS p ON p.id = sh.product_id
    WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
      AND (
        upper(btrim(COALESCE(p_store, 'ALL'))) = 'ALL'
        OR public._sales_history_resolve_store(sh) = upper(btrim(p_store))
      )
  )
  SELECT jsonb_build_object(
    'total_sum_krw', COALESCE(sum(f.price_krw) FILTER (WHERE f.price_krw > 0), 0),
    'total_count', COALESCE(count(*) FILTER (WHERE f.price_krw > 0), 0)::bigint,
    'gold_weight_grams', COALESCE(sum(f.w_g) FILTER (
      WHERE f.price_krw > 0 AND f.m_cat = 'gold'
    ), 0),
    'gold_sum_krw', COALESCE(sum(f.price_krw) FILTER (
      WHERE f.price_krw > 0 AND f.m_cat = 'gold'
    ), 0),
    'gold_count', COALESCE(count(*) FILTER (
      WHERE f.price_krw > 0 AND f.m_cat = 'gold'
    ), 0)::bigint,
    'silver_weight_grams', COALESCE(sum(f.w_g) FILTER (
      WHERE f.price_krw > 0 AND f.m_cat = 'silver'
    ), 0),
    'silver_sum_krw', COALESCE(sum(f.price_krw) FILTER (
      WHERE f.price_krw > 0 AND f.m_cat = 'silver'
    ), 0),
    'silver_count', COALESCE(count(*) FILTER (
      WHERE f.price_krw > 0 AND f.m_cat = 'silver'
    ), 0)::bigint,
    'other_count', COALESCE(count(*) FILTER (
      WHERE f.price_krw > 0 AND f.m_cat = 'other'
    ), 0)::bigint
  )
  FROM filtered AS f;
$$;

REVOKE ALL ON FUNCTION public.list_sales_history_report(date, date, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_sales_history_report(date, date, text, integer, integer)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_sales_history_summary(date, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_sales_history_summary(date, date, text)
  TO anon, authenticated, service_role;

COMMIT;