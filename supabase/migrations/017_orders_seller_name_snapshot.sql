-- Снимок имени продавца на заказе + seller_name в ответе apply_seller_referral_promo.

BEGIN;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS seller_name varchar(255);

COMMENT ON COLUMN public.orders.seller_name IS
  'Имя продавца на момент заказа (учёт продаж по продавцам).';

CREATE OR REPLACE FUNCTION public.orders_snapshot_seller_name()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.seller_code IS NOT NULL AND btrim(NEW.seller_code) <> '' THEN
    IF NEW.seller_name IS NULL OR btrim(NEW.seller_name) = '' THEN
      SELECT s.name INTO NEW.seller_name
      FROM public.sellers AS s
      WHERE s.promo_code = NEW.seller_code;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_snapshot_seller_name_trg ON public.orders;
CREATE TRIGGER orders_snapshot_seller_name_trg
  BEFORE INSERT OR UPDATE OF seller_code, seller_name ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.orders_snapshot_seller_name();

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
  v_name      varchar(255);
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

  SELECT s.buyer_bonus_percent, s.is_active, s.name
  INTO v_percent, v_active, v_name
  FROM public.sellers AS s
  WHERE s.promo_code = v_code;

  IF NOT FOUND OR NOT COALESCE(v_active, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_code');
  END IF;

  v_percent := GREATEST(COALESCE(v_percent, 0), 0);
  v_name := COALESCE(btrim(v_name), '');

  IF v_referred IS NOT NULL AND v_referred <> v_code THEN
    RETURN jsonb_build_object(
      'ok', true,
      'already_referred', true,
      'discount_percent', 0,
      'seller_code', v_code,
      'seller_name', v_name,
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
    'seller_code', v_code,
    'seller_name', v_name
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.apply_seller_referral_promo(text) TO authenticated;

UPDATE public.orders AS o
SET seller_name = s.name
FROM public.sellers AS s
WHERE o.seller_code = s.promo_code
  AND o.seller_code IS NOT NULL
  AND btrim(o.seller_code) <> ''
  AND (o.seller_name IS NULL OR btrim(o.seller_name) = '');

COMMIT;
