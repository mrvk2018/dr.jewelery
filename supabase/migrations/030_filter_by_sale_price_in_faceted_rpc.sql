-- Админ-витрина: фильтр «От/До» по sale_price (fallback: вес × курс).

BEGIN;

CREATE OR REPLACE FUNCTION public.get_advanced_faceted_products(
  metal_tags text[],
  category_tags text[],
  advanced_tags text[],
  min_price numeric,
  max_price numeric,
  gold_gram_price numeric,
  silver_gram_price numeric,
  exact_weight numeric DEFAULT NULL,
  sku_query text DEFAULT NULL
)
RETURNS SETOF public.products
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_metal    text[] := COALESCE(metal_tags, '{}'::text[]);
  v_category text[] := COALESCE(category_tags, '{}'::text[]);
  v_adv      text[] := COALESCE(advanced_tags, '{}'::text[]);
BEGIN
  RETURN QUERY
  SELECT p.*
  FROM public.products AS p
  CROSS JOIN LATERAL (
    SELECT CASE
      WHEN p.sale_price IS NOT NULL AND p.sale_price > 0 THEN p.sale_price::numeric
      WHEN p.weight_grams IS NULL THEN NULL::numeric
      WHEN COALESCE(p.metal, p.metal_type, '') ILIKE '%золото%'
        OR COALESCE(p.metal, p.metal_type, '') ~ '585'
        OR COALESCE(p.metal, p.metal_type, '') ~ '750' THEN
        p.weight_grams * gold_gram_price
      WHEN COALESCE(p.metal, p.metal_type, '') ILIKE '%серебр%'
        OR COALESCE(p.metal, p.metal_type, '') ~ '925' THEN
        p.weight_grams * silver_gram_price
      ELSE NULL::numeric
    END AS effective_price
  ) AS pr
  WHERE p.stock_quantity > 0
    AND COALESCE(p.status, 'active') = 'active'
    AND (
      min_price IS NULL AND max_price IS NULL
      OR (
        (min_price IS NULL OR (pr.effective_price IS NOT NULL AND pr.effective_price >= min_price))
        AND (max_price IS NULL OR (pr.effective_price IS NOT NULL AND pr.effective_price <= max_price))
      )
    )
    AND (
      cardinality(v_metal) = 0
      OR EXISTS (
        SELECT 1
        FROM unnest(v_metal) AS t(tag)
        WHERE btrim(tag) <> ''
          AND public.showroom_metal_facet_match(p, tag)
      )
    )
    AND (
      cardinality(v_category) = 0
      OR EXISTS (
        SELECT 1
        FROM unnest(v_category) AS t(tag)
        WHERE btrim(tag) <> ''
          AND public.showroom_category_facet_match(p, tag)
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
    AND (
      exact_weight IS NULL
      OR (
        p.weight_grams IS NOT NULL
        AND ROUND(p.weight_grams, 2) = ROUND(exact_weight, 2)
      )
    )
    AND (
      NULLIF(BTRIM(sku_query), '') IS NULL
      OR p.sku ILIKE ('%' || BTRIM(sku_query) || '%')
    )
  ORDER BY p.sku;
END;
$$;

COMMENT ON FUNCTION public.get_advanced_faceted_products(
  text[], text[], text[], numeric, numeric, numeric, numeric, numeric, text
) IS
  'Фасетная витрина: min/max по sale_price, иначе вес×курс; OR metal/category, exact_weight, sku_query.';

COMMIT;