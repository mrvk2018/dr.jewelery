-- Dr. Jewelry — расширение products (001/002) + RPC checkout
-- Безопасно: IF NOT EXISTS, name/description без DROP

BEGIN;

-- 1. Добавление недостающих колонок DrJaw / Flutter
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS weight_grams numeric(10, 4);
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS image_url text;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS warehouse_attributes jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS old_price integer NOT NULL DEFAULT 0;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS discount_percent integer NOT NULL DEFAULT 0;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS metal text;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS "insert" text;

-- 2. Обеспечение контракта JSONB без DROP
ALTER TABLE public.products ALTER COLUMN name SET DEFAULT '{}'::jsonb;
ALTER TABLE public.products ALTER COLUMN description SET DEFAULT '{}'::jsonb;

-- 3. Обновление CHECK констрейнта для статусов витрины
UPDATE public.products SET status = 'hidden' WHERE status IS NULL OR status NOT IN ('active', 'sold', 'hidden', 'reserved');
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_status_check;
ALTER TABLE public.products ADD CONSTRAINT products_status_check CHECK (status IN ('active', 'sold', 'hidden', 'reserved'));

-- 4. RPC функция бронирования для TossPayments с защитой от race condition
CREATE OR REPLACE FUNCTION public.reserve_product_for_checkout(p_id text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_status text;
BEGIN
  IF p_id IS NULL OR btrim(p_id) = '' THEN RETURN false; END IF;
  SELECT p.status INTO v_status FROM public.products AS p WHERE p.id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_status IS DISTINCT FROM 'active' THEN RETURN false; END IF;
  UPDATE public.products SET status = 'sold', stock_quantity = 0 WHERE id = p_id;
  RETURN true;
END; $$;

-- 5. RPC функция проверки остатка
CREATE OR REPLACE FUNCTION public.check_sklad_availability(p_sku text)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT p.stock_quantity FROM public.products AS p WHERE p.sku = p_sku AND p.status = 'active' LIMIT 1), 0);
$$;

GRANT EXECUTE ON FUNCTION public.reserve_product_for_checkout(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_sklad_availability(text) TO anon, authenticated;

COMMIT;
