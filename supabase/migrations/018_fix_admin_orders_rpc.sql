-- Обновление RPC функции для чтения заказов админом с поддержкой полей адреса из 013

BEGIN;

CREATE OR REPLACE FUNCTION public.get_all_orders_for_admin(p_admin_email text)
RETURNS SETOF public.orders
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT o.*
  FROM public.orders o
  -- Оставляем базовую проверку на email админа
  WHERE p_admin_email = 'dr.jewelry.korea@gmail.com'
  ORDER BY o.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_all_orders_for_admin(text) TO authenticated;

COMMIT;
