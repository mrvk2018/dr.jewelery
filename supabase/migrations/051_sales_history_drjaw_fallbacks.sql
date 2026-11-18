-- 051: DrJaw fallbacks в отчёте истории продаж + бэкфилл колонок из payload / products.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Классификация металла: PascalCase DrJaw (Metall)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.classify_metal_from_sales_payload(p_payload jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT public.classify_jewelry_metal_category(
    COALESCE(
      NULLIF(btrim(p_payload ->> 'metal'), ''),
      NULLIF(btrim(p_payload ->> 'Metall'), '')
    ),
    NULLIF(btrim(p_payload ->> 'metal_type'), '')
  );
$$;

-- ---------------------------------------------------------------------------
-- 2) Точка продажи: store_location + Mart / migration_meta.mart
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._sales_history_resolve_store(p_row public.sales_history)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT upper(btrim(COALESCE(
    NULLIF(btrim(p_row.store_location), ''),
    public._norm_store_icn_ans(NULLIF(btrim(p_row.raw_legacy_payload ->> 'store_location'), '')),
    CASE
      WHEN lower(btrim(COALESCE(p_row.raw_legacy_payload ->> 'Mart', ''))) LIKE '%№2%'
        OR lower(btrim(COALESCE(p_row.raw_legacy_payload ->> 'Mart', ''))) LIKE '%ансан%'
        OR btrim(COALESCE(p_row.raw_legacy_payload ->> 'Mart', '')) = 'D.Y №2' THEN 'ANS'
      WHEN btrim(COALESCE(p_row.raw_legacy_payload ->> 'Mart', '')) <> '' THEN 'ICN'
      ELSE NULL
    END,
    CASE
      WHEN lower(btrim(COALESCE(p_row.migration_meta ->> 'mart', ''))) IN ('d.y №2', 'ansan', 'ans', 'ансан')
        OR btrim(COALESCE(p_row.migration_meta ->> 'mart', '')) = 'D.Y №2' THEN 'ANS'
      WHEN btrim(COALESCE(p_row.migration_meta ->> 'mart', '')) <> '' THEN 'ICN'
      ELSE NULL
    END
  )));
$$;

-- ---------------------------------------------------------------------------
-- 3) Бэкфилл DrJaw (идемпотентно)
-- ---------------------------------------------------------------------------
UPDATE public.sales_history AS sh
SET
  source_system = COALESCE(NULLIF(btrim(sh.source_system), ''), 'DrJaw'),
  product_id = COALESCE(
    NULLIF(btrim(sh.product_id), ''),
  (SELECT p.id::text FROM public.products AS p WHERE p.id = sh.legacy_id LIMIT 1),
    (SELECT p.id::text FROM public.products AS p WHERE p.sku = sh.sku LIMIT 1),
    CASE WHEN sh.legacy_id ~ '^[0-9]+$' THEN sh.legacy_id ELSE NULL END
  ),
  store_location = COALESCE(
    NULLIF(upper(btrim(sh.store_location)), ''),
    CASE
      WHEN lower(btrim(COALESCE(sh.raw_legacy_payload ->> 'Mart', sh.migration_meta ->> 'mart', ''))) LIKE '%№2%'
        OR lower(btrim(COALESCE(sh.raw_legacy_payload ->> 'Mart', sh.migration_meta ->> 'mart', ''))) LIKE '%ансан%'
        OR btrim(COALESCE(sh.raw_legacy_payload ->> 'Mart', sh.migration_meta ->> 'mart', '')) = 'D.Y №2' THEN 'ANS'
      WHEN btrim(COALESCE(sh.raw_legacy_payload ->> 'Mart', sh.migration_meta ->> 'mart', '')) <> '' THEN 'ICN'
      ELSE NULL
    END
  ),
  seller_name = COALESCE(
    NULLIF(btrim(sh.seller_name), ''),
    NULLIF(btrim(sh.raw_legacy_payload ->> 'Manager'), ''),
    NULLIF(btrim(sh.migration_meta ->> 'manager'), '')
  ),
  metal_category = COALESCE(
    NULLIF(
      CASE
        WHEN sh.metal_category IN ('gold', 'silver') THEN sh.metal_category
        ELSE NULL
      END,
      ''
    ),
    NULLIF(public.classify_metal_from_sales_payload(sh.raw_legacy_payload), 'other'),
    public.classify_jewelry_metal_category(
      (SELECT p.metal FROM public.products p WHERE p.id = sh.product_id OR p.sku = sh.sku LIMIT 1),
      (SELECT p.metal_type FROM public.products p WHERE p.id = sh.product_id OR p.sku = sh.sku LIMIT 1)
    ),
    sh.metal_category,
    'other'
  ),
  discount_percent = CASE
    WHEN COALESCE(sh.discount_percent, 0) > 0 THEN sh.discount_percent
    WHEN COALESCE(NULLIF(btrim(sh.raw_legacy_payload ->> 'Bonus'), ''), '0')::integer > 0
      THEN LEAST(GREATEST((sh.raw_legacy_payload ->> 'Bonus')::integer, 0), 100)
    ELSE COALESCE(sh.discount_percent, 0)
  END,
  list_price_krw = CASE
    WHEN COALESCE(sh.list_price_krw, 0) > sh.price_krw THEN sh.list_price_krw
    WHEN COALESCE(NULLIF(btrim(sh.raw_legacy_payload ->> 'Bonus'), ''), '0')::integer > 0
      AND COALESCE(sh.price_krw, 0) > 0 THEN
      round(
        sh.price_krw::numeric * 100.0
        / (100 - LEAST(GREATEST((sh.raw_legacy_payload ->> 'Bonus')::integer, 0), 99))
      )::bigint
    ELSE COALESCE(sh.list_price_krw, sh.price_krw)
  END
WHERE (
  COALESCE(sh.source_system, sh.migration_meta ->> 'source_system', '') ILIKE 'drjaw'
  OR sh.migration_meta ? 'etl_version'
  OR sh.legacy_id ~ '^[0-9]+$'
)
AND sh.legacy_id NOT LIKE 'pwa_id_%';

UPDATE public.sales_history AS sh
SET metal_category = COALESCE(NULLIF(btrim(sh.metal_category), ''), 'other')
WHERE metal_category IS NULL;

-- ---------------------------------------------------------------------------
-- 4) list_sales_history_report — DrJaw fallbacks
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
        NULLIF(btrim(sh.raw_legacy_payload ->> 'Type'), ''),
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
      ) AS resolved_image_url,
      COALESCE(
        NULLIF(btrim(sh.seller_name), ''),
        NULLIF(btrim(sh.raw_legacy_payload ->> 'Manager'), ''),
        NULLIF(btrim(sh.migration_meta ->> 'manager'), '')
      ) AS resolved_seller_name,
      COALESCE(
        sh.metal_category,
        public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
        public.classify_jewelry_metal_category(p.metal, p.metal_type),
        'other'
      ) AS resolved_metal_category
    FROM public.sales_history AS sh
    LEFT JOIN public.products AS p ON p.id = sh.product_id
      OR (sh.product_id IS NULL AND p.sku = sh.sku)
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
      NULLIF((b.raw_legacy_payload ->> 'Weight'), '')::numeric,
      NULLIF((b.raw_legacy_payload ->> 'weight_grams'), '')::numeric
    ) AS weight_grams,
    COALESCE(b.list_price_krw, b.price_krw) AS list_price_krw,
    b.price_krw,
    COALESCE(b.discount_percent, 0) AS discount_percent,
    b.resolved_store AS store_location,
    b.resolved_seller_name AS seller_name,
    b.seller_code,
    b.payment_method,
    b.sold_at_utc,
    b.sold_date_kst,
    b.resolved_image_url AS image_url,
    b.resolved_metal_category AS metal_category,
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
-- 5) get_sales_history_summary — DrJaw fallbacks
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
        NULLIF((sh.raw_legacy_payload ->> 'Weight'), '')::numeric,
        NULLIF((sh.raw_legacy_payload ->> 'weight_grams'), '')::numeric,
        0
      ) AS w_g,
      COALESCE(
        sh.metal_category,
        public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
        public.classify_jewelry_metal_category(p.metal, p.metal_type),
        'other'
      ) AS m_cat
    FROM public.sales_history AS sh
    LEFT JOIN public.products AS p ON p.id = sh.product_id
      OR (sh.product_id IS NULL AND p.sku = sh.sku)
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