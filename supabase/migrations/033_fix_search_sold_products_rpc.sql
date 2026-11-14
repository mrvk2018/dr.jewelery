-- Поиск продаж для возврата: sales_history + products.sold, даты KST, AND-фильтры.

BEGIN;

DROP FUNCTION IF EXISTS public.search_sold_products(text, numeric, integer);
DROP FUNCTION IF EXISTS public.search_sold_products(text, numeric, int);
DROP FUNCTION IF EXISTS public.search_sold_products(text, numeric, integer, date, date);

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
      COALESCE(p.updated_at, timezone('utc', now())) AS sold_at_ts
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
    OR (timezone('Asia/Seoul', d.sold_at_ts))::date >= p_date_from
  )
  AND (
    p_date_to IS NULL
    OR (timezone('Asia/Seoul', d.sold_at_ts))::date <= p_date_to
  )
  AND (
    p_date_from IS NOT NULL
    OR p_date_to IS NOT NULL
    OR p_days_limit IS NULL
    OR d.sold_at_ts >= NOW() - (p_days_limit || ' days')::interval
  )
  ORDER BY d.sold_at_ts DESC NULLS LAST
  LIMIT 200;
END;
$$;

COMMENT ON FUNCTION public.search_sold_products(text, numeric, integer, date, date) IS
  'Возврат: продажи из sales_history и products.sold; AND-фильтры SKU/вес/период/даты.';

REVOKE ALL ON FUNCTION public.search_sold_products(text, numeric, integer, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.search_sold_products(text, numeric, integer, date, date)
  TO anon, authenticated, service_role;

COMMIT;