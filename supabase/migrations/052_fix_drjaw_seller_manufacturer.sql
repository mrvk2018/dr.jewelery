-- 052: DrJaw — Manager = производитель; seller_name только POS, не из Items.Manager.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Очистка ошибочного seller_name на исторических DrJaw
-- ---------------------------------------------------------------------------
UPDATE public.sales_history AS sh
SET seller_name = NULL
WHERE sh.legacy_id NOT LIKE 'pwa_id_%'
  AND (
    COALESCE(sh.source_system, sh.migration_meta ->> 'source_system', '') ILIKE 'drjaw'
    OR sh.migration_meta ? 'etl_version'
    OR sh.legacy_id ~ '^[0-9]+$'
  );

-- ---------------------------------------------------------------------------
-- 2) list_sales_history_report — manufacturer + seller без Manager
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