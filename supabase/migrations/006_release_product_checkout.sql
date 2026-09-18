-- Отмена брони после неуспешной/отменённой оплаты Toss (возврат в витрину).

BEGIN;

CREATE OR REPLACE FUNCTION public.release_product_checkout(p_id text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_id IS NULL OR btrim(p_id) = '' THEN RETURN false; END IF;
  UPDATE public.products
  SET status = 'active',
      stock_quantity = CASE WHEN stock_quantity <= 0 THEN 1 ELSE stock_quantity END
  WHERE id = p_id
    AND status = 'sold';
  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.release_product_checkout(text) TO anon, authenticated;

COMMIT;
