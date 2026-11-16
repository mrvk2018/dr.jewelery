-- Точка хранения товара: Инчхон (ICN) / Ансан (ANS).

BEGIN;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS store_location text NOT NULL DEFAULT 'ICN';

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_store_location_check;
ALTER TABLE public.products
  ADD CONSTRAINT products_store_location_check
  CHECK (store_location IN ('ICN', 'ANS'));

COMMENT ON COLUMN public.products.store_location IS
  'Физическая точка: ICN (Инчхон), ANS (Ансан). Sync из Items.Mart + ручной ввод.';

-- Бэкфилл из warehouse_attributes / legacy store_location
UPDATE public.products AS p
SET store_location = 'ANS'
WHERE
  btrim(COALESCE(p.warehouse_attributes->>'original_mart', '')) = 'D.Y №2'
  OR lower(btrim(COALESCE(p.warehouse_attributes->>'original_mart', ''))) LIKE '%№2%'
  OR lower(btrim(COALESCE(p.warehouse_attributes->>'original_mart', ''))) LIKE '%d.y%'
  OR lower(btrim(COALESCE(p.store_location, ''))) IN ('ans', 'ansan', 'ансан');

UPDATE public.products AS p
SET store_location = 'ICN'
WHERE
  btrim(COALESCE(p.warehouse_attributes->>'original_mart', '')) = 'Основной магазин'
  OR (
    btrim(COALESCE(p.warehouse_attributes->>'original_mart', '')) <> ''
    AND btrim(COALESCE(p.warehouse_attributes->>'original_mart', '')) IS DISTINCT FROM 'D.Y №2'
    AND lower(btrim(COALESCE(p.warehouse_attributes->>'original_mart', ''))) NOT LIKE '%№2%'
    AND lower(btrim(COALESCE(p.warehouse_attributes->>'original_mart', ''))) NOT LIKE '%d.y%'
    AND p.store_location IS DISTINCT FROM 'ANS'
  );

UPDATE public.products
SET store_location = 'ICN'
WHERE store_location IS NULL
   OR btrim(store_location) = ''
   OR upper(btrim(store_location)) NOT IN ('ICN', 'ANS');

CREATE INDEX IF NOT EXISTS idx_products_store_location
  ON public.products (store_location);

DROP FUNCTION IF EXISTS public.get_advanced_faceted_products(
  text[], text[], text[], numeric, numeric, numeric, numeric, numeric, text
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
  p_store_location text DEFAULT NULL
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
  ORDER BY p.sku;
END;
$$;

COMMENT ON FUNCTION public.get_advanced_faceted_products(
  text[], text[], text[], numeric, numeric, numeric, numeric, numeric, text, text
) IS
  'Фасетная витрина админки + фильтр store_location (ICN/ANS).';

REVOKE ALL ON FUNCTION public.get_advanced_faceted_products(
  text[], text[], text[], numeric, numeric, numeric, numeric, numeric, text, text
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_advanced_faceted_products(
  text[], text[], text[], numeric, numeric, numeric, numeric, numeric, text, text
) TO anon, authenticated, service_role;

COMMIT;