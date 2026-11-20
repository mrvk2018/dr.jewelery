-- 063: Сохранение карточки ADMIN (код 5 символов) + защита is_active + пересчёт комиссий POS.

BEGIN;

DROP FUNCTION IF EXISTS public.upsert_seller_by_admin(text, text, boolean);
DROP FUNCTION IF EXISTS public.upsert_seller_by_admin(text, text, boolean, numeric, numeric);
DROP FUNCTION IF EXISTS public.upsert_seller_by_admin(
  text, text, boolean, numeric, numeric, numeric, numeric, numeric, numeric
);
DROP FUNCTION IF EXISTS public.upsert_seller_by_admin(
  text, text, boolean, numeric, numeric, numeric, numeric, numeric, numeric, text, boolean
);

CREATE OR REPLACE FUNCTION public.upsert_seller_by_admin(
  p_promo_code text,
  p_name text,
  p_is_active boolean DEFAULT true,
  p_gold_commission_percent numeric DEFAULT 0,
  p_silver_commission_percent numeric DEFAULT 0,
  p_app_gold_commission_percent numeric DEFAULT 0,
  p_app_silver_commission_percent numeric DEFAULT 0,
  p_app_gold_buyer_discount_percent numeric DEFAULT 0,
  p_app_silver_buyer_discount_percent numeric DEFAULT 0,
  p_login_password text DEFAULT NULL,
  p_reset_pin boolean DEFAULT false
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
  v_name text;
  v_gold numeric(5, 2);
  v_silver numeric(5, 2);
  v_app_gold numeric(5, 2);
  v_app_silver numeric(5, 2);
  v_app_gold_disc numeric(5, 2);
  v_app_silver_disc numeric(5, 2);
  v_pwd text;
  v_is_active boolean;
  v_is_system_admin boolean;
BEGIN
  v_code := upper(btrim(COALESCE(p_promo_code, '')));
  v_name := btrim(COALESCE(p_name, ''));
  v_is_system_admin := (v_code = 'ADMIN');

  IF v_code = '' OR v_name = '' THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023',
            MESSAGE = 'promo_code и name обязательны';
  END IF;

  IF NOT v_is_system_admin
     AND (length(v_code) <> 6 OR v_code !~ '^[A-Z0-9]{6}$') THEN
    RAISE EXCEPTION 'invalid_promo_code'
      USING ERRCODE = '22023',
            MESSAGE = 'promo_code: ровно 6 символов A-Z или 0-9 (кроме системного ADMIN)';
  END IF;

  v_gold := round(COALESCE(p_gold_commission_percent, 0)::numeric, 2);
  v_silver := round(COALESCE(p_silver_commission_percent, 0)::numeric, 2);
  v_app_gold := round(COALESCE(p_app_gold_commission_percent, 0)::numeric, 2);
  v_app_silver := round(COALESCE(p_app_silver_commission_percent, 0)::numeric, 2);
  v_app_gold_disc := round(COALESCE(p_app_gold_buyer_discount_percent, 0)::numeric, 2);
  v_app_silver_disc := round(COALESCE(p_app_silver_buyer_discount_percent, 0)::numeric, 2);

  IF v_gold < 0 OR v_gold > 100
     OR v_silver < 0 OR v_silver > 100
     OR v_app_gold < 0 OR v_app_gold > 100
     OR v_app_silver < 0 OR v_app_silver > 100
     OR v_app_gold_disc < 0 OR v_app_gold_disc > 100
     OR v_app_silver_disc < 0 OR v_app_silver_disc > 100 THEN
    RAISE EXCEPTION 'invalid_commission'
      USING ERRCODE = '22023',
            MESSAGE = 'commission percent must be 0..100';
  END IF;

  v_pwd := NULLIF(btrim(COALESCE(p_login_password, '')), '');
  v_is_active := COALESCE(p_is_active, true);
  IF v_is_system_admin THEN
    v_is_active := true;
  END IF;

  INSERT INTO public.sellers (
    promo_code,
    name,
    is_active,
    gold_commission_percent,
    silver_commission_percent,
    app_gold_commission_percent,
    app_silver_commission_percent,
    app_gold_buyer_discount_percent,
    app_silver_buyer_discount_percent,
    login_password,
    pin_code
  )
  VALUES (
    v_code,
    v_name,
    v_is_active,
    v_gold,
    v_silver,
    v_app_gold,
    v_app_silver,
    v_app_gold_disc,
    v_app_silver_disc,
    v_pwd,
    CASE WHEN COALESCE(p_reset_pin, false) THEN NULL ELSE NULL END
  )
  ON CONFLICT (promo_code) DO UPDATE SET
    name = EXCLUDED.name,
    is_active = CASE
      WHEN v_is_system_admin THEN true
      ELSE EXCLUDED.is_active
    END,
    gold_commission_percent = EXCLUDED.gold_commission_percent,
    silver_commission_percent = EXCLUDED.silver_commission_percent,
    app_gold_commission_percent = EXCLUDED.app_gold_commission_percent,
    app_silver_commission_percent = EXCLUDED.app_silver_commission_percent,
    app_gold_buyer_discount_percent = EXCLUDED.app_gold_buyer_discount_percent,
    app_silver_buyer_discount_percent = EXCLUDED.app_silver_buyer_discount_percent,
    login_password = CASE
      WHEN v_pwd IS NOT NULL THEN v_pwd
      ELSE public.sellers.login_password
    END,
    pin_code = CASE
      WHEN COALESCE(p_reset_pin, false) THEN NULL
      ELSE public.sellers.pin_code
    END;

  IF v_is_system_admin THEN
    UPDATE public.sales_history AS sh
    SET
      commission_percent = public.seller_commission_rate_for_metal(
        v_gold,
        v_silver,
        COALESCE(NULLIF(btrim(sh.metal_category), ''), 'other')
      ),
      commission_krw = (
        CASE
          WHEN sh.price_krw < 0 THEN -1
          ELSE 1
        END
      ) * round(
        abs(sh.price_krw)::numeric
          * public.seller_commission_rate_for_metal(
              v_gold,
              v_silver,
              COALESCE(NULLIF(btrim(sh.metal_category), ''), 'other')
            )
          / 100.0
      )::integer
    WHERE upper(btrim(COALESCE(sh.seller_code, ''))) = 'ADMIN'
      AND sh.price_krw <> 0;
  END IF;

  RETURN true;
END;
$$;

COMMENT ON FUNCTION public.upsert_seller_by_admin(
  text, text, boolean, numeric, numeric, numeric, numeric, numeric, numeric, text, boolean
) IS
  'Админка персонала: upsert sellers; ADMIN (5 символов) — is_active всегда true, пересчёт commission по sales_history.';

REVOKE ALL ON FUNCTION public.upsert_seller_by_admin(
  text, text, boolean, numeric, numeric, numeric, numeric, numeric, numeric, text, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_seller_by_admin(
  text, text, boolean, numeric, numeric, numeric, numeric, numeric, numeric, text, boolean
) TO anon, authenticated, service_role;

COMMIT;