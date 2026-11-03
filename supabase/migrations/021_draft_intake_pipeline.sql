-- Dr. Jewelry — приёмка черновиков: hidden + stock 0, RPC поиск/активация (обход SELECT/UPDATE RLS).

BEGIN;

CREATE OR REPLACE FUNCTION public.search_draft_products(search_query text DEFAULT '')
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  q text := btrim(COALESCE(search_query, ''));
  w numeric;
  w_raw text;
BEGIN
  w_raw := NULLIF(regexp_replace(q, '[^0-9.,]', '', 'g'), '');
  IF w_raw IS NOT NULL THEN
    BEGIN
      w := replace(w_raw, ',', '.')::numeric;
    EXCEPTION
      WHEN others THEN
        w := NULL;
    END;
  END IF;

  RETURN QUERY
  SELECT to_jsonb(p.*)
  FROM public.products AS p
  WHERE p.stock_quantity = 0
    AND p.status IN ('hidden', 'active')
    AND (
      q = ''
      OR p.sku ILIKE '%' || q || '%'
      OR COALESCE(p.metal_type, p.metal, '') ILIKE '%' || q || '%'
      OR COALESCE(p.gem_inserts, p."insert", '') ILIKE '%' || q || '%'
      OR COALESCE(p.notes, '') ILIKE '%' || q || '%'
      OR (w IS NOT NULL AND p.weight_grams IS NOT NULL AND p.weight_grams = w)
    )
  ORDER BY p.updated_at DESC NULLS LAST, p.sku
  LIMIT 500;
END;
$$;

CREATE OR REPLACE FUNCTION public.activate_draft_product_by_sku(
  p_sku text,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sku text := btrim(COALESCE(p_sku, ''));
BEGIN
  IF v_sku = '' THEN
    RETURN false;
  END IF;
  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN false;
  END IF;

  UPDATE public.products
  SET
    status = 'active',
    stock_quantity = 1,
    updated_at = now()
  WHERE sku = v_sku
    AND stock_quantity = 0
    AND status IN ('hidden', 'active');

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.activate_all_draft_products(
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN 0;
  END IF;

  WITH updated AS (
    UPDATE public.products
    SET
      status = 'active',
      stock_quantity = 1,
      updated_at = now()
    WHERE stock_quantity = 0
      AND status IN ('hidden', 'active')
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_count FROM updated;

  RETURN COALESCE(v_count, 0);
END;
$$;

REVOKE ALL ON FUNCTION public.search_draft_products(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.activate_draft_product_by_sku(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.activate_all_draft_products(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.search_draft_products(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.activate_draft_product_by_sku(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.activate_all_draft_products(text) TO anon, authenticated;

COMMIT;
