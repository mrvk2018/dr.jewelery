-- Админ-витрина: фасетный фильтр — OR внутри «Металл» и «Категория», AND между группами.

BEGIN;

DROP FUNCTION IF EXISTS public.get_advanced_faceted_products(
  text[], text[], numeric, numeric, numeric, numeric
);

CREATE OR REPLACE FUNCTION public.showroom_product_metal_text(p public.products)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT lower(
    btrim(COALESCE(p.metal, '')) || ' ' || btrim(COALESCE(p.metal_type, ''))
  );
$$;

CREATE OR REPLACE FUNCTION public.showroom_metal_facet_match(
  p public.products,
  facet text
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  m text;
  f text;
BEGIN
  m := public.showroom_product_metal_text(p);
  f := lower(btrim(COALESCE(facet, '')));
  IF f = '' THEN
    RETURN false;
  END IF;

  CASE f
    WHEN 'золото' THEN
      RETURN m ~ 'золото'
        OR ((m ~ '585' OR m ~ '750') AND m !~ 'сереб');
    WHEN 'красное золото' THEN
      RETURN m ~ 'красн'
        OR m ~ '585[[:space:]]*красн'
        OR m ~ 'золото\([^)]+\)[[:space:]]*красн';
    WHEN 'жёлтое золото' THEN
      RETURN m ~ 'ж[её]лт'
        OR m ~ '585[[:space:]]*ж[её]лт'
        OR m ~ 'золото\([^)]+\)[[:space:]]*ж[её]лт';
    WHEN 'белое золото' THEN
      RETURN m ~ 'бел'
        OR m ~ '585[[:space:]]*бел'
        OR m ~ 'золото\([^)]+\)[[:space:]]*бел';
    WHEN 'серебро' THEN
      RETURN m ~ 'сереб' OR m ~ '925';
    ELSE
      RETURN m LIKE '%' || f || '%';
  END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.showroom_category_facet_match(
  p public.products,
  facet text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
PARALLEL SAFE
AS $$
DECLARE
  c text;
  f text;
BEGIN
  c := lower(btrim(COALESCE(p.category, '')));
  f := lower(btrim(COALESCE(facet, '')));
  IF f = '' THEN
    RETURN false;
  END IF;

  CASE f
    WHEN 'кольцо' THEN
      RETURN c LIKE '%кольц%' OR c LIKE '%обручаль%';
    WHEN 'серьги' THEN
      RETURN c LIKE '%серьг%' OR c LIKE '%пуссет%' OR c LIKE '%кафф%' OR c LIKE '%конго%';
    WHEN 'цепь' THEN
      RETURN c LIKE '%цеп%' OR c LIKE '%гайтан%';
    WHEN 'подвеска' THEN
      RETURN c LIKE '%подвес%' OR c LIKE '%крест%' OR c LIKE '%икон%';
    WHEN 'браслет (женский)' THEN
      RETURN c LIKE '%браслет (женский)%'
        OR (c LIKE '%браслет%' AND c LIKE '%жен%');
    WHEN 'браслет (мужской)' THEN
      RETURN c LIKE '%браслет (мужской)%'
        OR (c LIKE '%браслет%' AND c LIKE '%муж%');
    ELSE
      RETURN c LIKE '%' || f || '%';
  END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_advanced_faceted_products(
  metal_tags text[],
  category_tags text[],
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
  v_metal    text[] := COALESCE(metal_tags, '{}'::text[]);
  v_category text[] := COALESCE(category_tags, '{}'::text[]);
  v_adv      text[] := COALESCE(advanced_tags, '{}'::text[]);
BEGIN
  RETURN QUERY
  SELECT p.*
  FROM public.products AS p
  CROSS JOIN LATERAL (
    SELECT CASE
      WHEN p.weight_grams IS NULL THEN NULL::numeric
      WHEN COALESCE(p.metal, p.metal_type, '') ILIKE '%золото%'
        OR COALESCE(p.metal, p.metal_type, '') ~ '585'
        OR COALESCE(p.metal, p.metal_type, '') ~ '750' THEN
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
  ORDER BY p.sku;
END;
$$;

COMMENT ON FUNCTION public.get_advanced_faceted_products(
  text[], text[], text[], numeric, numeric, numeric, numeric
) IS
  'Фасетная витрина админки: OR по metal_tags и category_tags, AND с ценой и advanced_tags.';

REVOKE ALL ON FUNCTION public.get_advanced_faceted_products(
  text[], text[], text[], numeric, numeric, numeric, numeric
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_advanced_faceted_products(
  text[], text[], text[], numeric, numeric, numeric, numeric
) TO anon, authenticated;

COMMIT;
