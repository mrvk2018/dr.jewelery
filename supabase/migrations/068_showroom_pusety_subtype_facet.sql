-- 068: подвид «пусеты» + гвоздики DrJaw, homoglyph Latin «c» → кириллица в фасетах.
BEGIN;

CREATE OR REPLACE FUNCTION public.product_facet_search_blob(p public.products)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(
    coalesce(p.category, '') || ' ' ||
    coalesce(p.name::text, '') || ' ' ||
    coalesce(p.description::text, '') || ' ' ||
    coalesce(p.notes, '') || ' ' ||
    coalesce(p."insert", '') || ' ' ||
    coalesce(p.gem_inserts::text, '')
  );
$$;

CREATE OR REPLACE FUNCTION public.facet_homoglyph_normalize(t text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(
    regexp_replace(
      coalesce(t, ''),
      'пус[cсСC]ет',
      'пуссет',
      'gi'
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.showroom_advanced_facet_match(
  p public.products,
  facet text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
PARALLEL SAFE
AS $$
DECLARE
  f text;
  blob text;
BEGIN
  f := lower(btrim(coalesce(facet, '')));
  IF f = '' THEN
    RETURN false;
  END IF;

  blob := public.facet_homoglyph_normalize(public.product_facet_search_blob(p));

  IF f = 'без вставок' THEN
    RETURN (
      coalesce(nullif(btrim(p.gem_inserts::text), ''), nullif(btrim(p."insert"), ''), '') = ''
      OR coalesce(nullif(btrim(p.gem_inserts::text), ''), nullif(btrim(p."insert"), ''), '') IN ('—', '-')
      OR coalesce(p."insert", '') ILIKE '%без вставок%'
      OR coalesce(p."insert", '') ILIKE '%без камней%'
      OR coalesce(p.gem_inserts::text, '') ILIKE '%без вставок%'
      OR coalesce(p.gem_inserts::text, '') ILIKE '%без камней%'
    );
  END IF;

  IF f IN ('пусеты', 'пусет', 'пуссет') THEN
    RETURN blob ~ '(пусс?ет|гвозд)';
  END IF;

  IF f = 'гвозд' OR f LIKE 'гвозд%' THEN
    RETURN blob ~ 'гвозд';
  END IF;

  IF f = 'продёвки' THEN
    RETURN blob ~ '(продёв|продев)';
  END IF;

  RETURN blob LIKE '%' || f || '%';
END;
$$;

COMMENT ON FUNCTION public.showroom_advanced_facet_match(public.products, text) IS
  'Фильтр «Дополнительно» / подвид: пусеты (гвозд), homoglyph пус[c]ет, продёвки.';

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
  blob text;
  f text;
BEGIN
  c := lower(btrim(coalesce(p.category, '')));
  blob := public.facet_homoglyph_normalize(public.product_facet_search_blob(p));
  f := lower(btrim(coalesce(facet, '')));
  IF f = '' THEN
    RETURN false;
  END IF;

  CASE f
    WHEN 'кольцо' THEN
      RETURN c LIKE '%кольц%' OR blob LIKE '%кольц%' OR blob LIKE '%обручаль%';
    WHEN 'серьги' THEN
      RETURN blob ~ '(серьг|пусс?ет|гвозд|кафф|конго|продёв|продев)';
    WHEN 'цепь' THEN
      RETURN c LIKE '%цеп%' OR blob LIKE '%цеп%';
    WHEN 'подвески', 'подвеска' THEN
      RETURN c LIKE '%подвес%' OR blob LIKE '%подвес%'
        OR blob LIKE '%икон%';
    WHEN 'крест' THEN
      RETURN c LIKE '%крест%' OR blob LIKE '%крест%';
    WHEN 'колье' THEN
      RETURN c LIKE '%колье%' OR blob LIKE '%колье%';
    WHEN 'браслет' THEN
      RETURN c LIKE '%браслет%' OR blob LIKE '%браслет%';
    WHEN 'браслет (женский)' THEN
      RETURN c LIKE '%браслет (женский)%' OR blob LIKE '%браслет (женский)%'
        OR (c LIKE '%браслет%' AND c LIKE '%жен%')
        OR (blob LIKE '%браслет%' AND blob LIKE '%жен%');
    WHEN 'браслет (мужской)' THEN
      RETURN c LIKE '%браслет (мужский)%' OR blob LIKE '%браслет (мужский)%'
        OR (c LIKE '%браслет%' AND c LIKE '%муж%')
        OR (blob LIKE '%браслет%' AND blob LIKE '%муж%');
    WHEN 'пирсинг' THEN
      RETURN c LIKE '%пирсинг%' OR blob LIKE '%пирсинг%';
    WHEN 'гайтан' THEN
      RETURN c LIKE '%гайтан%' OR blob LIKE '%гайтан%';
    WHEN 'брошь' THEN
      RETURN c LIKE '%брош%' OR blob LIKE '%брош%';
    ELSE
      RETURN c LIKE '%' || f || '%' OR blob LIKE '%' || f || '%';
  END CASE;
END;
$$;

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
          AND public.showroom_advanced_facet_match(p, tag)
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

REVOKE ALL ON FUNCTION public.get_advanced_faceted_products(
  text[], text[], text[], numeric, numeric, numeric, numeric, numeric, text, text, text
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_advanced_faceted_products(
  text[], text[], text[], numeric, numeric, numeric, numeric, numeric, text, text, text
) TO anon, authenticated, service_role;

COMMIT;