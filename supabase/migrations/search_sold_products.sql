-- RPC: комбинированный поиск проданных позиций (stock_quantity = 0), без полной выгрузки каталога.

BEGIN;

CREATE OR REPLACE FUNCTION public.search_sold_products(
  p_sku text DEFAULT NULL,
  p_weight numeric DEFAULT NULL,
  p_days_limit int DEFAULT NULL
)
RETURNS TABLE (
  id text,
  sku text,
  name text,
  weight_grams numeric,
  size_value text,
  metal_type text,
  price_krw int,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (
    (p_sku IS NULL OR btrim(p_sku) = '')
    AND p_weight IS NULL
    AND p_days_limit IS NULL
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id::text,
    p.sku::text,
    COALESCE(NULLIF(btrim(p.notes), ''), p.sku)::text AS name,
    p.weight_grams,
    p.size_value::text,
    p.metal_type::text,
    COALESCE(p.sale_price, 0)::int AS price_krw,
    p.updated_at
  FROM public.products p
  WHERE p.stock_quantity = 0
    AND (
      p_sku IS NULL
      OR btrim(p_sku) = ''
      OR p.sku ILIKE '%' || btrim(p_sku) || '%'
    )
    AND (p_weight IS NULL OR p.weight_grams = p_weight)
    AND (
      p_days_limit IS NULL
      OR p.updated_at >= NOW() - (p_days_limit || ' days')::interval
    )
  ORDER BY p.updated_at DESC
  LIMIT 200;
END;
$$;

REVOKE ALL ON FUNCTION public.search_sold_products(text, numeric, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_sold_products(text, numeric, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_sold_products(text, numeric, int) TO service_role;

COMMIT;
