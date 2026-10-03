-- Процентная скидка продавца (checkout) вместо фиксированного buyer_bonus_krw в RPC.

BEGIN;

ALTER TABLE public.sellers
  ADD COLUMN IF NOT EXISTS buyer_bonus_percent integer NOT NULL DEFAULT 0;

ALTER TABLE public.sellers DROP CONSTRAINT IF EXISTS sellers_buyer_bonus_percent_range;
ALTER TABLE public.sellers
  ADD CONSTRAINT sellers_buyer_bonus_percent_range
  CHECK (buyer_bonus_percent >= 0 AND buyer_bonus_percent <= 100);

COMMENT ON COLUMN public.sellers.buyer_bonus_percent IS
  'Процент скидки покупателю при оплате с промокодом этого продавца (checkout).';

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
  v_percent   integer;
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

  SELECT s.buyer_bonus_percent, s.is_active
  INTO v_percent, v_active
  FROM public.sellers AS s
  WHERE s.promo_code = v_code;

  IF NOT FOUND OR NOT COALESCE(v_active, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_code');
  END IF;

  v_percent := GREATEST(COALESCE(v_percent, 0), 0);

  IF v_referred IS NOT NULL AND v_referred <> v_code THEN
    RETURN jsonb_build_object(
      'ok', true,
      'already_referred', true,
      'discount_percent', 0,
      'message',
      'У вас уже привязан другой промокод продавца'
    );
  END IF;

  IF v_referred IS NULL THEN
    UPDATE public.profiles
    SET referred_by_seller = v_code
    WHERE id = v_uid
      AND referred_by_seller IS NULL
    RETURNING id INTO v_updated;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'already_referred', false,
    'discount_percent', v_percent,
    'seller_code', v_code
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.apply_seller_referral_promo(text) TO authenticated;

COMMIT;
