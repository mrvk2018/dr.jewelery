-- Dr. Jewelry — ручная продажа из админ-PWA без прямого PATCH products (обход RLS + GRANT).
-- Причина 403: 001_create_products — только GRANT SELECT; UPDATE запрещён на уровне GRANT/RLS.
-- Админка после PIN не логинит Supabase Auth (сессия anon или anonymous JWT), не dr.jewelry email.
-- Прямой UPDATE + .select('id') дополнительно ломается: SELECT RLS status = 'active', строка уже sold.

BEGIN;

-- Убрать экспериментальные политики, если добавляли вручную в SQL Editor.
DROP POLICY IF EXISTS products_authenticated_update ON public.products;
DROP POLICY IF EXISTS products_admin_update ON public.products;
DROP POLICY IF EXISTS products_mark_sold_update ON public.products;

CREATE OR REPLACE FUNCTION public.mark_product_sold_manual(
  p_product_id text,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
BEGIN
  IF p_product_id IS NULL OR btrim(p_product_id) = '' THEN
    RETURN false;
  END IF;

  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN false;
  END IF;

  SELECT p.status
  INTO v_status
  FROM public.products AS p
  WHERE p.id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_status NOT IN ('active', 'reserved', 'hidden') THEN
    RETURN false;
  END IF;

  UPDATE public.products
  SET
    status = 'sold',
    stock_quantity = 0,
    updated_at = now()
  WHERE id = p_product_id;

  RETURN true;
END;
$$;

COMMENT ON FUNCTION public.mark_product_sold_manual(text, text) IS
  'Админ «Продано»: status=sold, stock=0. SECURITY DEFINER → триггер trg_log_pwa_sale → sales_history.';

REVOKE ALL ON FUNCTION public.mark_product_sold_manual(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_product_sold_manual(text, text) TO anon, authenticated;

-- Триггер истории: владелец postgres, чтобы INSERT в sales_history не упирался в RLS сессии клиента.
ALTER FUNCTION public.log_future_sale_to_history() OWNER TO postgres;

COMMIT;
