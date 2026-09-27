-- Заказы v2: корейский адрес доставки + статус in_transit

BEGIN;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS shipping_postal_code text,
  ADD COLUMN IF NOT EXISTS shipping_road_address text,
  ADD COLUMN IF NOT EXISTS shipping_detail_address text,
  ADD COLUMN IF NOT EXISTS recipient_name text,
  ADD COLUMN IF NOT EXISTS recipient_phone text;

COMMENT ON COLUMN public.orders.shipping_postal_code IS 'Почтовый индекс KR (5 цифр).';
COMMENT ON COLUMN public.orders.shipping_road_address IS 'Дорожный адрес (Daum roadAddress).';
COMMENT ON COLUMN public.orders.shipping_detail_address IS 'Детальный адрес (квартира, этаж).';
COMMENT ON COLUMN public.orders.recipient_name IS 'Получатель на момент checkout.';
COMMENT ON COLUMN public.orders.recipient_phone IS 'Телефон получателя KR.';

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
  CHECK (status IN ('new', 'paid', 'in_transit', 'delivered'));

COMMENT ON COLUMN public.orders.status IS 'new | paid | in_transit | delivered';

-- RLS: клиент пишет свой заказ; authenticated читает/обновляет для админ-панели (MVP).
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS orders_select_authenticated ON public.orders;
CREATE POLICY orders_select_authenticated
  ON public.orders
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS orders_insert_own ON public.orders;
CREATE POLICY orders_insert_own
  ON public.orders
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS orders_update_authenticated ON public.orders;
CREATE POLICY orders_update_authenticated
  ON public.orders
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

COMMIT;
