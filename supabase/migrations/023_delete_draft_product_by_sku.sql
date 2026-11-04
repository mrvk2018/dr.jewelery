-- Dr. Jewelry — удаление черновика приёмки (SECURITY DEFINER, обход RLS).
-- Контракт Flutter: AdminCatalogRpc.deleteDraftBySku + p_admin_email.

BEGIN;

CREATE OR REPLACE FUNCTION public.delete_draft_product_by_sku(
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

  DELETE FROM public.products
  WHERE sku = v_sku
    AND stock_quantity = 0
    AND status IN ('hidden', 'active');

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_draft_product_by_sku(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_draft_product_by_sku(text, text) TO anon, authenticated;

COMMIT;
