-- Админ-витрина: base_tags по metal/category + stock_quantity/status вместо quantity.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_advanced_faceted_products(
  base_tags text[],
  advanced_tags text[],
  min_price numeric,
  max_price numeric,
  gold_gram_price numeric,
  silver_gram_price numeric
)
RETURNS SETOF public.products
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_base text[] := COALESCE(base_tags, '{}'::text[]);
  v_adv  text[] := COALESCE(advanced_tags, '{}'::text[]);
BEGIN
  RETURN QUERY
  SELECT p.*
  FROM public.products AS p
  CROSS JOIN LATERAL (
    SELECT CASE
      WHEN p.weight_grams IS NULL THEN NULL::numeric
      WHEN COALESCE(p.metal, p.metal_type, '') ILIKE '%золото%'
        OR COALESCE(p.metal, p.metal_type, '') ~ '585' THEN
        p.weight_grams * gold_gram_price
      WHEN COALESCE(p.metal, p.metal_type, '') ILIKE '%серебр%'
        OR COALESCE(p.metal, p.metal_type, '') ~ '925' THEN
        p.weight_grams * silver_gram_price
      ELSE NULL::numeric
    END AS retail_price
  ) AS pr
  WHERE p.stock_quantity > 0
    AND COALESCE(p.status, 'active') = 'active'
    AND (
      min_price IS NULL AND max_price IS NULL
      OR (
        pr.retail_price IS NOT NULL
        AND (min_price IS NULL OR pr.retail_price >= min_price)
        AND (max_price IS NULL OR pr.retail_price <= max_price)
      )
    )
    AND (
      cardinality(v_base) = 0
      OR EXISTS (
        SELECT 1
        FROM unnest(v_base) AS t(tag)
        WHERE btrim(tag) <> ''
          AND (
            p.sku ILIKE '%' || tag || '%'
            OR COALESCE(p.metal, '') ILIKE '%' || tag || '%'
            OR COALESCE(p.metal_type, '') ILIKE '%' || tag || '%'
            OR COALESCE(p.category, '') ILIKE '%' || tag || '%'
            OR COALESCE(p.notes, '') ILIKE '%' || tag || '%'
          )
      )
    )
    AND (
      cardinality(v_adv) = 0
      OR EXISTS (
        SELECT 1
        FROM unnest(v_adv) AS t(tag)
        WHERE btrim(tag) <> ''
          AND (
            COALESCE(p.notes, '') ILIKE '%' || tag || '%'
            OR COALESCE(p.gem_inserts::text, '') ILIKE '%' || tag || '%'
            OR COALESCE(p."insert", '') ILIKE '%' || tag || '%'
          )
      )
    )
  ORDER BY p.sku;
END;
$$;

REVOKE ALL ON FUNCTION public.get_advanced_faceted_products(
  text[], text[], numeric, numeric, numeric, numeric
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_advanced_faceted_products(
  text[], text[], numeric, numeric, numeric, numeric
) TO anon, authenticated;

COMMIT;
