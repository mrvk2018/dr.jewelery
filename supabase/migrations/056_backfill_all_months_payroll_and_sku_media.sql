-- 056: Полный бэкфилл seller_code/комиссий + DrJaw media fallbacks (sku LATERAL).
-- Применить целиком в Supabase SQL Editor (после 034/054/055).

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) Безопасный парсинг веса из DrJaw payload
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.safe_jsonb_numeric(p_val text)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_val IS NULL OR btrim(p_val) = '' THEN NULL
    WHEN btrim(p_val) ~ '^-?[0-9]+(\.[0-9]+)?$' THEN btrim(p_val)::numeric
    ELSE NULL
  END;
$$;

CREATE OR REPLACE FUNCTION public.sales_history_payload_weight_grams(p_payload jsonb)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    public.safe_jsonb_numeric(p_payload ->> 'weight_grams'),
    public.safe_jsonb_numeric(p_payload ->> 'Weight'),
    CASE
      WHEN jsonb_typeof(p_payload -> 'Weight') = 'number' THEN
        public.safe_jsonb_numeric((p_payload -> 'Weight')::text)
      ELSE NULL
    END
  );
$$;

-- ---------------------------------------------------------------------------
-- 1) Бэкфилл seller_code / commission за ВСЮ историю
-- ---------------------------------------------------------------------------
WITH candidates AS (
  SELECT
    sh.id,
    sh.seller_name AS orig_name,
    sh.price_krw,
    r.promo_code,
    r.name AS resolved_name,
    r.gold_commission_percent,
    r.silver_commission_percent,
    COALESCE(
      sh.metal_category,
      public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
      'other'
    ) AS m_cat
  FROM public.sales_history AS sh
  CROSS JOIN LATERAL public.resolve_seller_by_name(sh.seller_name) AS r
  WHERE NULLIF(btrim(sh.seller_code), '') IS NULL
    AND NULLIF(btrim(sh.seller_name), '') IS NOT NULL
    AND r.promo_code IS NOT NULL
)
UPDATE public.sales_history AS sh
SET
  seller_code = c.promo_code,
  seller_name = CASE
    WHEN c.promo_code = 'ADMIN'
         AND lower(btrim(c.orig_name)) IN ('андрей', 'наталья')
      THEN btrim(c.orig_name)
    ELSE c.resolved_name
  END,
  metal_category = c.m_cat,
  commission_percent = CASE
    WHEN c.promo_code = 'ADMIN' THEN 0::numeric
    ELSE public.seller_commission_rate_for_metal(
      c.gold_commission_percent,
      c.silver_commission_percent,
      c.m_cat
    )
  END,
  commission_krw = CASE
    WHEN c.promo_code = 'ADMIN' THEN 0
    ELSE round(
      c.price_krw::numeric
        * public.seller_commission_rate_for_metal(
            c.gold_commission_percent,
            c.silver_commission_percent,
            c.m_cat
          ) / 100.0
    )::integer
  END
FROM candidates AS c
WHERE sh.id = c.id;

-- ---------------------------------------------------------------------------
-- 2) get_my_seller_sales_details — sku LATERAL + Type/Weight fallbacks
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_my_seller_sales_details(text, date, date);

CREATE OR REPLACE FUNCTION public.get_my_seller_sales_details(
  p_promo_code text,
  p_date_from date,
  p_date_to date
)
RETURNS TABLE (
  sale_id text,
  sold_at timestamptz,
  sold_date_kst date,
  sku text,
  product_name text,
  metal_category text,
  metal_label text,
  weight_grams numeric,
  price_krw integer,
  commission_percent numeric,
  commission_krw integer,
  is_return boolean,
  image_url text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
BEGIN
  v_code := upper(btrim(COALESCE(p_promo_code, '')));
  IF v_code = '' OR v_code = 'ADMIN' THEN
    RAISE EXCEPTION 'invalid_promo_code'
      USING ERRCODE = '28000',
            MESSAGE = 'Код продавца недоступен для личного отчёта';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.sellers AS s
    WHERE s.promo_code = v_code AND s.is_active
  ) THEN
    RAISE EXCEPTION 'seller_inactive'
      USING ERRCODE = '28000',
            MESSAGE = 'Продавец не найден или деактивирован';
  END IF;

  RETURN QUERY
  SELECT
    sh.id::text AS sale_id,
    sh.sold_at_utc AS sold_at,
    sh.sold_date_kst,
    sh.sku,
    COALESCE(
      NULLIF(btrim(p.name ->> 'ru'), ''),
      NULLIF(btrim(p.name ->> 'ko'), ''),
      NULLIF(btrim(p.name ->> 'en'), ''),
      NULLIF(btrim(p_sku.name ->> 'ru'), ''),
      NULLIF(btrim(p_sku.name ->> 'ko'), ''),
      NULLIF(btrim(p_sku.name ->> 'en'), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'Type'), ''),
      NULLIF(btrim(sh.sku), '')
    ) AS product_name,
    COALESCE(
      sh.metal_category,
      public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
      'other'
    ) AS metal_category,
    COALESCE(
      NULLIF(btrim(p.metal_type), ''),
      NULLIF(btrim(p.metal), ''),
      NULLIF(btrim(p_sku.metal_type), ''),
      NULLIF(btrim(p_sku.metal), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'metal_type'), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'metal'), '')
    ) AS metal_label,
    COALESCE(
      p.weight_grams,
      p_sku.weight_grams,
      public.sales_history_payload_weight_grams(sh.raw_legacy_payload)
    ) AS weight_grams,
    sh.price_krw::integer,
    sh.commission_percent,
    sh.commission_krw,
    (sh.price_krw < 0) AS is_return,
    COALESCE(
      public.product_primary_image_url(p),
      public.product_primary_image_url(p_sku),
      NULLIF(btrim(sh.image_url), ''),
      CASE
        WHEN jsonb_typeof(sh.raw_legacy_payload -> 'additional_images') = 'array'
          AND jsonb_array_length(sh.raw_legacy_payload -> 'additional_images') > 0 THEN
          NULLIF(btrim(sh.raw_legacy_payload -> 'additional_images' ->> 0), '')
        ELSE NULL
      END,
      NULLIF(btrim(sh.raw_legacy_payload ->> 'image_url'), '')
    ) AS image_url
  FROM public.sales_history AS sh
  LEFT JOIN public.products AS p ON p.id = sh.product_id
  LEFT JOIN LATERAL (
    SELECT ps.*
    FROM public.products AS ps
    WHERE NULLIF(btrim(sh.sku), '') IS NOT NULL
      AND upper(btrim(ps.sku)) = upper(btrim(sh.sku))
    ORDER BY
      (public.product_primary_image_url(ps) IS NOT NULL) DESC,
      ps.updated_at DESC NULLS LAST
    LIMIT 1
  ) AS p_sku ON true
  WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
    AND upper(btrim(sh.seller_code)) = v_code
  ORDER BY sh.sold_at_utc DESC NULLS LAST, sh.legacy_id DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_seller_sales_details(text, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_seller_sales_details(text, date, date)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) get_seller_sales_details — те же fallbacks (админ детализация)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_seller_sales_details(text, date, date);

CREATE OR REPLACE FUNCTION public.get_seller_sales_details(
  p_seller_code text,
  p_date_from date,
  p_date_to date
)
RETURNS TABLE (
  sale_id text,
  sold_at timestamptz,
  sku text,
  product_name text,
  metal_category text,
  metal_label text,
  weight_grams numeric,
  price_krw integer,
  commission_percent numeric,
  commission_krw integer,
  is_return boolean,
  image_url text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    sh.id::text AS sale_id,
    sh.sold_at_utc AS sold_at,
    sh.sku,
    COALESCE(
      NULLIF(btrim(p.name ->> 'ru'), ''),
      NULLIF(btrim(p.name ->> 'ko'), ''),
      NULLIF(btrim(p.name ->> 'en'), ''),
      NULLIF(btrim(p_sku.name ->> 'ru'), ''),
      NULLIF(btrim(p_sku.name ->> 'ko'), ''),
      NULLIF(btrim(p_sku.name ->> 'en'), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'Type'), ''),
      NULLIF(btrim(sh.sku), '')
    ) AS product_name,
    COALESCE(
      sh.metal_category,
      public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
      'other'
    ) AS metal_category,
    COALESCE(
      NULLIF(btrim(p.metal_type), ''),
      NULLIF(btrim(p.metal), ''),
      NULLIF(btrim(p_sku.metal_type), ''),
      NULLIF(btrim(p_sku.metal), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'metal_type'), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'metal'), '')
    ) AS metal_label,
    COALESCE(
      p.weight_grams,
      p_sku.weight_grams,
      public.sales_history_payload_weight_grams(sh.raw_legacy_payload)
    ) AS weight_grams,
    sh.price_krw::integer,
    sh.commission_percent,
    sh.commission_krw,
    (sh.price_krw < 0) AS is_return,
    COALESCE(
      public.product_primary_image_url(p),
      public.product_primary_image_url(p_sku),
      NULLIF(btrim(sh.image_url), ''),
      CASE
        WHEN jsonb_typeof(sh.raw_legacy_payload -> 'additional_images') = 'array'
          AND jsonb_array_length(sh.raw_legacy_payload -> 'additional_images') > 0 THEN
          NULLIF(btrim(sh.raw_legacy_payload -> 'additional_images' ->> 0), '')
        ELSE NULL
      END,
      NULLIF(btrim(sh.raw_legacy_payload ->> 'image_url'), '')
    ) AS image_url
  FROM public.sales_history AS sh
  LEFT JOIN public.products AS p ON p.id = sh.product_id
  LEFT JOIN LATERAL (
    SELECT ps.*
    FROM public.products AS ps
    WHERE NULLIF(btrim(sh.sku), '') IS NOT NULL
      AND upper(btrim(ps.sku)) = upper(btrim(sh.sku))
    ORDER BY
      (public.product_primary_image_url(ps) IS NOT NULL) DESC,
      ps.updated_at DESC NULLS LAST
    LIMIT 1
  ) AS p_sku ON true
  WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
    AND (
      (
        upper(btrim(p_seller_code)) = '__UNASSIGNED__'
        AND NULLIF(btrim(sh.seller_code), '') IS NULL
      )
      OR upper(btrim(sh.seller_code)) = upper(btrim(p_seller_code))
    )
  ORDER BY sh.sold_at_utc DESC NULLS LAST, sh.legacy_id DESC;
$$;

REVOKE ALL ON FUNCTION public.get_seller_sales_details(text, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_seller_sales_details(text, date, date)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) list_sales_history_report — sku LATERAL + безопасный Weight
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
      COALESCE(p.weight_grams, p_sku.weight_grams) AS p_weight,
      COALESCE(p.status, p_sku.status) AS p_status,
      COALESCE(
        NULLIF(btrim(p.name ->> 'ru'), ''),
        NULLIF(btrim(p.name ->> 'ko'), ''),
        NULLIF(btrim(p.name ->> 'en'), ''),
        NULLIF(btrim(p_sku.name ->> 'ru'), ''),
        NULLIF(btrim(p_sku.name ->> 'ko'), ''),
        NULLIF(btrim(p_sku.name ->> 'en'), ''),
        NULLIF(btrim(sh.raw_legacy_payload ->> 'Type'), ''),
        NULLIF(btrim(sh.sku), '')
      ) AS p_name,
      COALESCE(
        NULLIF(btrim(sh.image_url), ''),
        NULLIF(btrim(p.image_url), ''),
        NULLIF(btrim(p.images[1]), ''),
        CASE
          WHEN COALESCE(array_length(p.additional_images, 1), 0) > 0 THEN
            NULLIF(btrim(p.additional_images[1]), '')
          ELSE NULL
        END,
        public.product_primary_image_url(p_sku),
        NULLIF(btrim(p_sku.image_url), ''),
        CASE
          WHEN COALESCE(array_length(p_sku.additional_images, 1), 0) > 0 THEN
            NULLIF(btrim(p_sku.additional_images[1]), '')
          ELSE NULL
        END
      ) AS resolved_image_url,
      COALESCE(
        sh.metal_category,
        public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
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
      ORDER BY
        (public.product_primary_image_url(ps) IS NOT NULL) DESC,
        ps.updated_at DESC NULLS LAST
      LIMIT 1
    ) AS p_sku ON true
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
      public.sales_history_payload_weight_grams(b.raw_legacy_payload)
    ) AS weight_grams,
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
    CASE
      WHEN b.legacy_id NOT LIKE 'pwa_id_%' THEN
        NULLIF(btrim(b.raw_legacy_payload ->> 'Manager'), '')
      ELSE NULL
    END AS manufacturer,
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

REVOKE ALL ON FUNCTION public.list_sales_history_report(date, date, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_sales_history_report(date, date, text, integer, integer)
  TO anon, authenticated, service_role;

COMMIT;