-- 067: Фильтр витрины по размеру (size_value / available_sizes) в get_advanced_faceted_products.
BEGIN;

CREATE OR REPLACE FUNCTION public.product_size_facet_match(
  p_size_value numeric,
  p_available_sizes jsonb,
  p_query text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  WITH normalized_query AS (
    SELECT NULLIF(replace(btrim(COALESCE(p_query, '')), ',', '.'), '') AS q
  ),
  effective AS (
    SELECT COALESCE(
      NULLIF(p_size_value, 0),
      public._product_first_positive_size_from_array(p_available_sizes)
    ) AS sz
  )
  SELECT CASE
    WHEN (SELECT q FROM normalized_query) IS NULL THEN true
    WHEN (SELECT sz FROM effective) IS NULL THEN false
    ELSE replace((SELECT sz FROM effective)::text, ',', '.') LIKE
      (SELECT q FROM normalized_query) || '%'
  END;
$$;

COMMENT ON FUNCTION public.product_size_facet_match(numeric, jsonb, text) IS
  'Префиксный поиск размера: 17 → 17, 17.0, 17.5; 50 → 50, 50.00 (size_value / available_sizes).';

DROP FUNCTION IF EXISTS public.get_advanced_faceted_products(
  text[],
  text[],
  text[],
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text
);

CREATE OR REPLACE FUNCTION public.get_advanced_faceted_products(
  metal_tags text[],
  category_tags text[],
  advanced_tags text[],
  min_price numeric,
  max_price numeric,
  gold_gram_price numeric,
  silver_gram_price numeric,
  exact_weight numeric DEFAULT NULL,
  sku_query text DEFAULT NULL,
  p_store_location text DEFAULT NULL,
  size_query text DEFAULT NULL
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
  v_store    text := NULLIF(upper(btrim(COALESCE(p_store_location, ''))), '');
BEGIN
  RETURN QUERY
  SELECT p.*
  FROM public.products AS p
  CROSS JOIN LATERAL (
    SELECT CASE
      WHEN p.sale_price IS NOT NULL AND p.sale_price > 0 THEN
        public.round_krw_up_1000(p.sale_price::numeric)
      WHEN p.weight_grams IS NULL THEN NULL::numeric
      WHEN COALESCE(p.metal, p.metal_type, '') ILIKE '%золото%'
        OR COALESCE(p.metal, p.metal_type, '') ~ '585'
        OR COALESCE(p.metal, p.metal_type, '') ~ '750' THEN
        public.round_krw_up_1000(p.weight_grams * gold_gram_price)
      WHEN COALESCE(p.metal, p.metal_type, '') ILIKE '%серебр%'
        OR COALESCE(p.metal, p.metal_type, '') ~ '925' THEN
        public.round_krw_up_1000(p.weight_grams * silver_gram_price)
      ELSE NULL::numeric
    END AS effective_price
  ) AS pr
  WHERE p.stock_quantity > 0
    AND COALESCE(p.status, 'active') = 'active'
    AND (
      v_store IS NULL
      OR upper(btrim(COALESCE(p.store_location, 'ICN'))) = v_store
    )
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
            CASE
              WHEN lower(btrim(tag)) = 'без вставок' THEN (
                COALESCE(NULLIF(btrim(p.gem_inserts::text), ''), NULLIF(btrim(p."insert"), ''), '') = ''
                OR COALESCE(NULLIF(btrim(p.gem_inserts::text), ''), NULLIF(btrim(p."insert"), ''), '') IN ('—', '-')
                OR COALESCE(p."insert", '') ILIKE '%без вставок%'
                OR COALESCE(p."insert", '') ILIKE '%без камней%'
                OR COALESCE(p.gem_inserts::text, '') ILIKE '%без вставок%'
                OR COALESCE(p.gem_inserts::text, '') ILIKE '%без камней%'
              )
              ELSE (
                COALESCE(p."insert", '') ILIKE '%' || tag || '%'
                OR COALESCE(p.gem_inserts::text, '') ILIKE '%' || tag || '%'
                OR COALESCE(p.notes, '') ILIKE '%' || tag || '%'
                OR COALESCE(p.name::text, '') ILIKE '%' || tag || '%'
                OR COALESCE(p.category, '') ILIKE '%' || tag || '%'
              )
            END
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
    AND public.product_size_facet_match(
      p.size_value,
      p.available_sizes,
      size_query
    )
  ORDER BY p.sku;
END;
$$;

COMMENT ON FUNCTION public.get_advanced_faceted_products(
  text[], text[], text[], numeric, numeric, numeric, numeric, numeric, text, text, text
) IS
  'Фасетная витрина админки: цена, металл, категория, вес, SKU, магазин, размер.';

REVOKE ALL ON FUNCTION public.get_advanced_faceted_products(
  text[], text[], text[], numeric, numeric, numeric, numeric, numeric, text, text, text
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_advanced_faceted_products(
  text[], text[], text[], numeric, numeric, numeric, numeric, numeric, text, text, text
) TO anon, authenticated, service_role;

COMMIT;