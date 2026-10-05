-- Удаление аккаунта покупателя (Apple 5.1.1(v) / Google Play Account Deletion).

BEGIN;

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  DELETE FROM public.orders WHERE user_id = v_uid;
  DELETE FROM public.profiles WHERE id = v_uid;
  DELETE FROM auth.users WHERE id = v_uid;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;

COMMIT;
