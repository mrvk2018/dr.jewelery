-- Staff upsert for admin panel (PIN-gated UI; no JWT email check).

BEGIN;

DROP FUNCTION IF EXISTS public.upsert_seller_by_admin(text, text, boolean);

CREATE OR REPLACE FUNCTION public.upsert_seller_by_admin(
  p_promo_code text,
  p_name text,
  p_is_active boolean DEFAULT true
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code varchar(50);
  v_name varchar(255);
BEGIN
  v_code := upper(trim(both from coalesce(p_promo_code, '')));
  v_name := trim(both from coalesce(p_name, ''));

  IF v_code = '' OR v_name = '' THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023',
            MESSAGE = 'promo_code и name обязательны';
  END IF;

  IF length(v_code) <> 6 OR v_code !~ '^[A-Z0-9]{6}$' THEN
    RAISE EXCEPTION 'invalid_promo_code'
      USING ERRCODE = '22023',
            MESSAGE = 'promo_code: ровно 6 символов A-Z или 0-9';
  END IF;

  INSERT INTO public.sellers (promo_code, name, is_active)
  VALUES (v_code, v_name, coalesce(p_is_active, true))
  ON CONFLICT (promo_code) DO UPDATE SET
    name = EXCLUDED.name,
    is_active = EXCLUDED.is_active;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_seller_by_admin(text, text, boolean)
  TO anon, authenticated;

COMMIT;
