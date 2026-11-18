-- 049: продажа в sales_history только при status → sold; поиск продаж без подмены даты updated_at.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Триггер: не логировать stock_quantity → 0 без status = sold
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
  v_payload          jsonb;
  v_sold_at_utc      timestamptz;
  v_sold_kst         date;
  v_metal_category   text;
  v_seller_code      text;
  v_seller_name      text;
  v_commission_pct   numeric(5, 2);
  v_commission_krw   integer;
  v_product_name     text;
  v_resolved         record;
BEGIN
  IF NOT (NEW.status = 'sold' AND OLD.status IS DISTINCT FROM 'sold') THEN
    RETURN NEW;
  END IF;

  v_legacy_id := 'pwa_id_' || NEW.id;
  v_sold_at_utc := timezone('utc', now());
  v_sold_kst := (timezone('Asia/Seoul', now()))::date;
  v_payload := row_to_json(NEW)::jsonb;
  v_price_krw := COALESCE(NEW.sale_price, 0)::bigint;

  v_metal_category := public.classify_jewelry_metal_category(
    NULLIF(btrim(NEW.metal), ''),
    NULLIF(btrim(NEW.metal_type), '')
  );

  v_product_name := COALESCE(
    NULLIF(btrim(NEW.name ->> 'ru'), ''),
    NULLIF(btrim(NEW.name ->> 'ko'), ''),
    NULLIF(btrim(NEW.name ->> 'en'), ''),
    NULLIF(btrim(NEW.sku), '')
  );

  v_seller_code := NULL;
  v_seller_name := NULL;
  v_commission_pct := 0;
  v_commission_krw := 0;

  SELECT r.seller_code, r.seller_name
  INTO v_seller_code, v_seller_name
  FROM public.resolve_seller_for_product_sale(NEW.id, NEW.sku, v_product_name) AS r
  LIMIT 1;

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
  IF v_image_url IS NULL
     AND v_payload ? 'additional_images'
     AND jsonb_typeof(v_payload -> 'additional_images') = 'array'
     AND jsonb_array_length(v_payload -> 'additional_images') > 0
  THEN
    v_image_url := NULLIF(btrim(v_payload -> 'additional_images' ->> 0), '');
  END IF;

  INSERT INTO public.sales_history (
    legacy_id,
    sku,
    product_id,
    price_krw,
    sold_at_utc,
    sold_date_kst,
    image_url,
    photo_status,
    import_batch_id,
    source_system,
    raw_legacy_payload,
    migration_meta,
    seller_code,
    seller_name,
    metal_category,
    commission_percent,
    commission_krw
  )
  VALUES (
    v_legacy_id,
    NEW.sku,
    NEW.id,
    v_price_krw,
    v_sold_at_utc,
    v_sold_kst,
    v_image_url,
    'success',
    '00000000-0000-0000-0000-000000000000'::uuid,
    'pwa_store',
    v_payload,
    jsonb_build_object(
      'source_system', 'pwa_store',
      'logged_by', 'trg_log_pwa_sale',
      'product_id', NEW.id,
      'sold_at_utc', v_sold_at_utc,
      'sold_date_kst', v_sold_kst::text
    ),
    v_seller_code,
    v_seller_name,
    v_metal_category,
    COALESCE(v_commission_pct, 0),
    COALESCE(v_commission_krw, 0)
  )
  ON CONFLICT (legacy_id) DO NOTHING;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.log_future_sale_to_history() IS
  'AFTER UPDATE products: только status→sold → sales_history; stock_quantity→0 без sold не логируется.';

-- ---------------------------------------------------------------------------
-- 2) search_sold_products: архив без sales_history — без даты sold_at (не updated_at)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.search_sold_products(
  p_sku text DEFAULT NULL,
  p_weight numeric DEFAULT NULL,
  p_days_limit integer DEFAULT NULL,
  p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT NULL
)
RETURNS TABLE (
  id text,
  sku text,
  name text,
  weight_grams numeric,
  size_value text,
  metal_type text,
  price_krw int,
  sold_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH sale_rows AS (
    SELECT
      COALESCE(p.id, sh.product_id)::text AS product_id,
      COALESCE(p.sku, sh.sku)::text AS product_sku,
      COALESCE(
        NULLIF(btrim(p.notes), ''),
        NULLIF(btrim(p.name ->> 'ru'), ''),
        NULLIF(btrim(p.name ->> 'ko'), ''),
        NULLIF(btrim(p.name::text), ''),
        COALESCE(p.sku, sh.sku)
      )::text AS display_name,
      p.weight_grams,
      p.size_value::text AS size_value,
      COALESCE(NULLIF(btrim(p.metal_type), ''), NULLIF(btrim(p.metal), ''))::text
        AS metal_type,
      COALESCE(sh.price_krw, p.sale_price, 0)::int AS sale_price_krw,
      sh.sold_at_utc AS sold_at_ts
    FROM public.sales_history AS sh
    LEFT JOIN public.products AS p
      ON p.id = sh.product_id
      OR (sh.product_id IS NULL AND p.sku = sh.sku)
    WHERE sh.price_krw > 0
      AND NOT EXISTS (
        SELECT 1
        FROM public.sales_history AS r
        WHERE (r.migration_meta ->> 'reverses_legacy_id') = sh.legacy_id
          AND COALESCE(r.migration_meta ->> 'type', '') = 'return'
      )

    UNION ALL

    SELECT
      p.id::text AS product_id,
      p.sku::text AS product_sku,
      COALESCE(
        NULLIF(btrim(p.notes), ''),
        NULLIF(btrim(p.name ->> 'ru'), ''),
        NULLIF(btrim(p.name ->> 'ko'), ''),
        NULLIF(btrim(p.name::text), ''),
        p.sku
      )::text AS display_name,
      p.weight_grams,
      p.size_value::text AS size_value,
      COALESCE(NULLIF(btrim(p.metal_type), ''), NULLIF(btrim(p.metal), ''))::text
        AS metal_type,
      COALESCE(p.sale_price, 0)::int AS sale_price_krw,
      NULL::timestamptz AS sold_at_ts
    FROM public.products AS p
    WHERE (p.status = 'sold' OR COALESCE(p.stock_quantity, 0) = 0)
      AND NOT EXISTS (
        SELECT 1
        FROM public.sales_history AS sh
        WHERE sh.price_krw > 0
          AND (sh.product_id = p.id OR sh.sku = p.sku)
          AND NOT EXISTS (
            SELECT 1
            FROM public.sales_history AS r
            WHERE (r.migration_meta ->> 'reverses_legacy_id') = sh.legacy_id
              AND COALESCE(r.migration_meta ->> 'type', '') = 'return'
          )
      )
  ),
  deduped AS (
    SELECT DISTINCT ON (lower(btrim(s.product_sku)))
      s.product_id,
      s.product_sku,
      s.display_name,
      s.weight_grams,
      s.size_value,
      s.metal_type,
      s.sale_price_krw,
      s.sold_at_ts
    FROM sale_rows AS s
    WHERE btrim(COALESCE(s.product_sku, '')) <> ''
    ORDER BY lower(btrim(s.product_sku)), s.sold_at_ts DESC NULLS LAST
  )
  SELECT
    d.product_id,
    d.product_sku,
    d.display_name,
    d.weight_grams,
    d.size_value,
    d.metal_type,
    d.sale_price_krw,
    d.sold_at_ts,
    d.sold_at_ts AS updated_at
  FROM deduped AS d
  WHERE (
    NULLIF(btrim(p_sku), '') IS NULL
    OR d.product_sku ILIKE ('%' || btrim(p_sku) || '%')
  )
  AND (
    p_weight IS NULL
    OR (
      d.weight_grams IS NOT NULL
      AND ROUND(d.weight_grams, 2) = ROUND(p_weight, 2)
    )
  )
  AND (
    p_date_from IS NULL
    OR (
      d.sold_at_ts IS NOT NULL
      AND (timezone('Asia/Seoul', d.sold_at_ts))::date >= p_date_from
    )
  )
  AND (
    p_date_to IS NULL
    OR (
      d.sold_at_ts IS NOT NULL
      AND (timezone('Asia/Seoul', d.sold_at_ts))::date <= p_date_to
    )
  )
  AND (
    p_date_from IS NOT NULL
    OR p_date_to IS NOT NULL
    OR p_days_limit IS NULL
    OR (
      d.sold_at_ts IS NOT NULL
      AND d.sold_at_ts >= NOW() - (p_days_limit || ' days')::interval
    )
  )
  ORDER BY d.sold_at_ts DESC NULLS LAST
  LIMIT 200;
END;
$$;

COMMENT ON FUNCTION public.search_sold_products(text, numeric, integer, date, date) IS
  'Возврат: sales_history + sold без history; даты только при sold_at_ts IS NOT NULL (не products.updated_at).';

COMMIT;