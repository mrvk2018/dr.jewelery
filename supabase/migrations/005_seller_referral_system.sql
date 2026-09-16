-- Dr. Jewelry — реферальная система продавцов (промокод / seller_code на заказе)
-- В репозитории до 004 существует только public.products; profiles/orders создаются при отсутствии.

BEGIN;

-- ---------------------------------------------------------------------------
-- public.profiles (профиль клиента, привязка к auth.users)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id         uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS referred_by_seller varchar(50);

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS bonus_balance integer NOT NULL DEFAULT 0;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_bonus_balance_nonneg;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_bonus_balance_nonneg CHECK (bonus_balance >= 0);

COMMENT ON COLUMN public.profiles.referred_by_seller IS
  'ID или промокод продавца, который привёл клиента (реферал).';
COMMENT ON COLUMN public.profiles.bonus_balance IS
  'Бонусный баланс клиента (KRW), напр. 50 000 за ввод промокода.';

CREATE INDEX IF NOT EXISTS profiles_referred_by_seller_idx
  ON public.profiles (referred_by_seller)
  WHERE referred_by_seller IS NOT NULL;

-- ---------------------------------------------------------------------------
-- public.orders (заказы; seller_code фиксируется на момент покупки)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.orders (
  id         text PRIMARY KEY,
  user_id    uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS seller_code varchar(50);

COMMENT ON COLUMN public.orders.seller_code IS
  'Промокод/ID продавца на момент оплаты; не меняется при смене referred_by_seller у клиента.';

CREATE INDEX IF NOT EXISTS orders_seller_code_idx
  ON public.orders (seller_code)
  WHERE seller_code IS NOT NULL;

-- ---------------------------------------------------------------------------
-- public.sellers (Картотека продавцов и блогеров соцсетей)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sellers (
  promo_code VARCHAR(50) PRIMARY KEY,
  name       VARCHAR(255) NOT NULL,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Добавляем внешний ключ (Foreign Key) к таблице профилей для строгой связи
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS fk_profiles_referred_by_seller;
ALTER TABLE public.profiles
  ADD CONSTRAINT fk_profiles_referred_by_seller
  FOREIGN KEY (referred_by_seller) REFERENCES public.sellers (promo_code) ON DELETE SET NULL;

COMMIT;
