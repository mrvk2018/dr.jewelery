-- Dr. Jewelry — бонусы продавцов, app_settings, welcome trigger, RPC реферала

BEGIN;

ALTER TABLE public.sellers
  ADD COLUMN IF NOT EXISTS buyer_bonus_krw integer NOT NULL DEFAULT 0;

ALTER TABLE public.sellers DROP CONSTRAINT IF EXISTS sellers_buyer_bonus_krw_nonneg;
ALTER TABLE public.sellers
  ADD CONSTRAINT sellers_buyer_bonus_krw_nonneg CHECK (buyer_bonus_krw >= 0);

COMMENT ON COLUMN public.sellers.buyer_bonus_krw IS
  'Скидка покупателю (KRW) при первой привязке промокода продавца на checkout.';

-- ---------------------------------------------------------------------------
-- public.app_settings (singleton)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_settings (
  id                     smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  welcome_bonus_enabled  boolean NOT NULL DEFAULT false,
  welcome_bonus_amount   integer NOT NULL DEFAULT 0,
  updated_at             timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.app_settings DROP CONSTRAINT IF EXISTS app_settings_welcome_amount_nonneg;
ALTER TABLE public.app_settings
  ADD CONSTRAINT app_settings_welcome_amount_nonneg CHECK (welcome_bonus_amount >= 0);

INSERT INTO public.app_settings (id)
VALUES (1)
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- RLS profiles / app_settings
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profiles_select_own ON public.profiles;
CREATE POLICY profiles_select_own
  ON public.profiles FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
CREATE POLICY profiles_update_own
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS profiles_insert_own ON public.profiles;
CREATE POLICY profiles_insert_own
  ON public.profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_settings_public_select ON public.app_settings;
CREATE POLICY app_settings_public_select
  ON public.app_settings FOR SELECT
  TO anon, authenticated
  USING (true);

-- ---------------------------------------------------------------------------
-- Новый пользователь auth → profiles + welcome bonus
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enabled boolean := false;
  v_amount  integer := 0;
  v_bonus   integer := 0;
BEGIN
  SELECT welcome_bonus_enabled, welcome_bonus_amount
  INTO v_enabled, v_amount
  FROM public.app_settings
  WHERE id = 1;

  IF COALESCE(v_enabled, false) AND COALESCE(v_amount, 0) > 0 THEN
    v_bonus := v_amount;
  END IF;

  INSERT INTO public.profiles (id, bonus_balance)
  VALUES (NEW.id, v_bonus)
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ---------------------------------------------------------------------------
-- RPC: применение промокода продавца (anti-abuse на сервере)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_seller_referral_promo(p_promo_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_code      varchar(50);
  v_referred  varchar(50);
  v_bonus     integer;
  v_active    boolean;
  v_updated   uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'not_authenticated'
    );
  END IF;

  v_code := upper(btrim(replace(COALESCE(p_promo_code, ''), ' ', '')));
  IF v_code = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'empty_code');
  END IF;

  INSERT INTO public.profiles (id)
  VALUES (v_uid)
  ON CONFLICT (id) DO NOTHING;

  SELECT referred_by_seller INTO v_referred
  FROM public.profiles
  WHERE id = v_uid;

  IF v_referred IS NOT NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'already_referred', true,
      'discount_krw', 0,
      'message',
      'Промокод применен для привязки к продавцу, но приветственный бонус уже был получен вами ранее'
    );
  END IF;

  SELECT s.buyer_bonus_krw, s.is_active
  INTO v_bonus, v_active
  FROM public.sellers AS s
  WHERE s.promo_code = v_code;

  IF NOT FOUND OR NOT COALESCE(v_active, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_code');
  END IF;

  UPDATE public.profiles
  SET referred_by_seller = v_code
  WHERE id = v_uid
    AND referred_by_seller IS NULL
  RETURNING id INTO v_updated;

  IF v_updated IS NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'already_referred', true,
      'discount_krw', 0,
      'message',
      'Промокод применен для привязки к продавцу, но приветственный бонус уже был получен вами ранее'
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'already_referred', false,
    'discount_krw', GREATEST(COALESCE(v_bonus, 0), 0),
    'seller_code', v_code
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.apply_seller_referral_promo(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: маркетинг (админ-панель, тот же контур что sellers upsert)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.save_app_marketing_settings(boolean, integer);

CREATE OR REPLACE FUNCTION public.save_app_marketing_settings(
  p_welcome_bonus_enabled boolean,
  p_welcome_bonus_amount integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.app_settings (
    id,
    welcome_bonus_enabled,
    welcome_bonus_amount,
    updated_at
  )
  VALUES (
    1,
    COALESCE(p_welcome_bonus_enabled, false),
    GREATEST(COALESCE(p_welcome_bonus_amount, 0), 0),
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    welcome_bonus_enabled = EXCLUDED.welcome_bonus_enabled,
    welcome_bonus_amount = EXCLUDED.welcome_bonus_amount,
    updated_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_app_marketing_settings(boolean, integer) TO anon, authenticated;

COMMIT;
