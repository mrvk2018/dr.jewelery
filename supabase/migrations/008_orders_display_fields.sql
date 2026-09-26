-- Поля для истории заказов в профиле (OrderItem / fromSupabase).

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS product_name text,
  ADD COLUMN IF NOT EXISTS amount integer NOT NULL DEFAULT 0 CHECK (amount >= 0),
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'new',
  ADD COLUMN IF NOT EXISTS customer_name text;

COMMENT ON COLUMN public.orders.product_name IS 'Название позиции или сводка по заказу для UI.';
COMMENT ON COLUMN public.orders.amount IS 'Сумма заказа, KRW.';
COMMENT ON COLUMN public.orders.status IS 'new | paid | delivered';
