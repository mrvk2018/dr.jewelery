-- Бронирование перед Toss: статус reserved (не reservation) + updated_at (010).

BEGIN;

CREATE OR REPLACE FUNCTION public.reserve_product_for_checkout(p_id text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
BEGIN
  IF p_id IS NULL OR btrim(p_id) = '' THEN
    RETURN false;
  END IF;

  SELECT p.status
  INTO v_status
  FROM public.products AS p
  WHERE p.id = p_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_status IS DISTINCT FROM 'active' THEN
    RETURN false;
  END IF;

  UPDATE public.products
  SET
    status = 'reserved',
    stock_quantity = 0,
    updated_at = now()
  WHERE id = p_id;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reserve_product_for_checkout(text) TO anon, authenticated;

COMMIT;
