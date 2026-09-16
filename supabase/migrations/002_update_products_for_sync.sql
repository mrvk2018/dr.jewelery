-- Dr. Jewelry — статус товара для синхронизации со складом и блокировки SKU при оплате
-- active: доступен на витрине | reserved: забронирован на время оплаты | sold: продан через приложение

BEGIN;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'reserved', 'sold'));

COMMENT ON COLUMN public.products.status IS
  'Витрина/SKU: active — доступен; reserved — забронирован при checkout; sold — продан. Склад Items.Status («В наличии») задаёт начальную active при sync.';

CREATE INDEX IF NOT EXISTS products_status_idx ON public.products (status);

-- Витрина: клиент читает только активные позиции (reserved/sold скрыты).
DROP POLICY IF EXISTS products_public_select ON public.products;

CREATE POLICY products_public_select
  ON public.products
  FOR SELECT
  TO anon, authenticated
  USING (status = 'active');

COMMIT;
