-- Repair: remote may have save_app_marketing_settings with legacy parameter names.
-- PostgreSQL forbids CREATE OR REPLACE when IN parameter names change (42P13).

BEGIN;

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

GRANT EXECUTE ON FUNCTION public.save_app_marketing_settings(boolean, integer)
  TO anon, authenticated;

COMMIT;
