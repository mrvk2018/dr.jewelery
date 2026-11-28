-- 057: resolve_seller_by_name — составные подписи POS («Имя · CODE», «Имя - CODE»).
-- Применить целиком в Supabase SQL Editor (после 054).

BEGIN;

CREATE OR REPLACE FUNCTION public.resolve_seller_by_name(p_name text)
RETURNS TABLE (
  promo_code text,
  name text,
  gold_commission_percent numeric,
  silver_commission_percent numeric
)
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_raw      text;
  v_left     text;
  v_right    text;
  v_left_norm text;
  v_row      public.sellers%ROWTYPE;
BEGIN
  v_raw := btrim(COALESCE(p_name, ''));
  IF v_raw = '' THEN
    RETURN;
  END IF;

  v_left := v_raw;
  v_right := NULL;

  IF v_raw ~ '\s*·\s*' THEN
    v_left := btrim(regexp_replace(v_raw, '\s*·\s*.*$', ''));
    v_right := upper(btrim(regexp_replace(v_raw, '^.*\s*·\s*', '')));
  ELSIF v_raw ~ '\s-\s*' THEN
    v_left := btrim(regexp_replace(v_raw, '\s-\s*.*$', ''));
    v_right := upper(btrim(regexp_replace(v_raw, '^.*\s-\s*', '')));
  END IF;

  IF v_right IS NOT NULL AND v_right <> '' THEN
    SELECT s.*
    INTO v_row
    FROM public.sellers AS s
    WHERE s.promo_code = v_right
      AND s.is_active
    LIMIT 1;

    IF FOUND THEN
      RETURN QUERY
      SELECT
        v_row.promo_code::text,
        v_row.name::text,
        v_row.gold_commission_percent,
        v_row.silver_commission_percent;
      RETURN;
    END IF;
  END IF;

  SELECT s.*
  INTO v_row
  FROM public.sellers AS s
  WHERE s.promo_code = upper(v_raw)
    AND s.is_active
  LIMIT 1;

  IF FOUND THEN
    RETURN QUERY
    SELECT
      v_row.promo_code::text,
      v_row.name::text,
      v_row.gold_commission_percent,
      v_row.silver_commission_percent;
    RETURN;
  END IF;

  v_left_norm := lower(btrim(COALESCE(NULLIF(v_left, ''), v_raw)));

  IF v_left_norm IN ('андрей', 'наталья') THEN
    RETURN QUERY
    SELECT
      s.promo_code::text,
      s.name::text,
      s.gold_commission_percent,
      s.silver_commission_percent
    FROM public.sellers AS s
    WHERE s.promo_code = 'ADMIN'
      AND s.is_active;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    s.promo_code::text,
    s.name::text,
    s.gold_commission_percent,
    s.silver_commission_percent
  FROM public.sellers AS s
  WHERE lower(btrim(s.name)) = v_left_norm
    AND s.is_active;
END;
$$;

COMMENT ON FUNCTION public.resolve_seller_by_name(text) IS
  'POS/payroll: seller_name → sellers; поддержка «Имя · CODE», чистого promo_code, Андрей/Наталья → ADMIN.';

/*
-- Проверка после применения (ожидается по 1 строке на каждый ввод):
SELECT * FROM public.resolve_seller_by_name('Администратор');
SELECT * FROM public.resolve_seller_by_name('Администратор - ADMIN');
SELECT * FROM public.resolve_seller_by_name('Администратор · ADMIN');
SELECT * FROM public.resolve_seller_by_name('ADMIN');
SELECT * FROM public.resolve_seller_by_name('Андрей');
SELECT * FROM public.resolve_seller_by_name('Люда - QWER75');
*/

COMMIT;