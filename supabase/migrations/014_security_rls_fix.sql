-- Закрытие MVP RLS на orders: покупатель видит только свои строки; админ — полный доступ.

BEGIN;

DROP POLICY IF EXISTS orders_select_authenticated ON public.orders;
DROP POLICY IF EXISTS orders_update_authenticated ON public.orders;

CREATE POLICY orders_customer_select
  ON public.orders
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY orders_admin_all
  ON public.orders
  FOR ALL
  TO authenticated
  USING (auth.jwt() ->> 'email' = 'dr.jewelry.korea@gmail.com')
  WITH CHECK (auth.jwt() ->> 'email' = 'dr.jewelry.korea@gmail.com');

COMMIT;
