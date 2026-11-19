-- 055: Личный кабинет продавца — RPC только для своего promo_code.
-- Применить целиком в Supabase SQL Editor (после 034/054).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) get_my_seller_payroll_summary — одна строка сводки по promo_code
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_seller_payroll_summary(
  p_promo_code text,
  p_date_from date,
  p_date_to date
)
RETURNS TABLE (
  promo_code text,
  seller_name text,
  is_active boolean,
  gold_commission_percent numeric,
  silver_commission_percent numeric,
  gold_sales_count bigint,
  gold_sales_krw bigint,
  gold_commission_krw bigint,
  silver_sales_count bigint,
  silver_sales_krw bigint,
  silver_commission_krw bigint,
  returns_count bigint,
  returns_commission_krw bigint,
  total_commission_krw bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
BEGIN
  v_code := upper(btrim(COALESCE(p_promo_code, '')));
  IF v_code = '' OR v_code = 'ADMIN' THEN
    RAISE EXCEPTION 'invalid_promo_code'
      USING ERRCODE = '28000',
            MESSAGE = 'Код продавца недоступен для личного отчёта';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.sellers AS s
    WHERE s.promo_code = v_code AND s.is_active
  ) THEN
    RAISE EXCEPTION 'seller_inactive'
      USING ERRCODE = '28000',
            MESSAGE = 'Продавец не найден или деактивирован';
  END IF;

  RETURN QUERY
  SELECT g.*
  FROM public.get_seller_payroll_summary(p_date_from, p_date_to) AS g
  WHERE g.promo_code = v_code;
END;
$$;

COMMENT ON FUNCTION public.get_my_seller_payroll_summary(text, date, date) IS
  'Личный кабинет: сводка зарплаты одного активного продавца (не ADMIN).';

REVOKE ALL ON FUNCTION public.get_my_seller_payroll_summary(text, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_seller_payroll_summary(text, date, date)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) get_my_seller_sales_details — операции продавца + sold_date_kst (KST)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_seller_sales_details(
  p_promo_code text,
  p_date_from date,
  p_date_to date
)
RETURNS TABLE (
  sale_id text,
  sold_at timestamptz,
  sold_date_kst date,
  sku text,
  product_name text,
  metal_category text,
  metal_label text,
  weight_grams numeric,
  price_krw integer,
  commission_percent numeric,
  commission_krw integer,
  is_return boolean,
  image_url text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
BEGIN
  v_code := upper(btrim(COALESCE(p_promo_code, '')));
  IF v_code = '' OR v_code = 'ADMIN' THEN
    RAISE EXCEPTION 'invalid_promo_code'
      USING ERRCODE = '28000',
            MESSAGE = 'Код продавца недоступен для личного отчёта';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.sellers AS s
    WHERE s.promo_code = v_code AND s.is_active
  ) THEN
    RAISE EXCEPTION 'seller_inactive'
      USING ERRCODE = '28000',
            MESSAGE = 'Продавец не найден или деактивирован';
  END IF;

  RETURN QUERY
  SELECT
    sh.id::text AS sale_id,
    sh.sold_at_utc AS sold_at,
    sh.sold_date_kst,
    sh.sku,
    COALESCE(
      NULLIF(btrim(p.name ->> 'ru'), ''),
      NULLIF(btrim(p.name ->> 'ko'), ''),
      NULLIF(btrim(p.name ->> 'en'), ''),
      sh.sku
    ) AS product_name,
    COALESCE(
      sh.metal_category,
      public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
      'other'
    ) AS metal_category,
    COALESCE(
      NULLIF(btrim(p.metal_type), ''),
      NULLIF(btrim(p.metal), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'metal_type'), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'metal'), '')
    ) AS metal_label,
    COALESCE(
      p.weight_grams,
      (sh.raw_legacy_payload ->> 'weight_grams')::numeric
    ) AS weight_grams,
    sh.price_krw::integer,
    sh.commission_percent,
    sh.commission_krw,
    (sh.price_krw < 0) AS is_return,
    COALESCE(
      public.product_primary_image_url(p),
      NULLIF(btrim(sh.image_url), ''),
      CASE
        WHEN jsonb_typeof(sh.raw_legacy_payload -> 'additional_images') = 'array'
          AND jsonb_array_length(sh.raw_legacy_payload -> 'additional_images') > 0 THEN
          NULLIF(btrim(sh.raw_legacy_payload -> 'additional_images' ->> 0), '')
        ELSE NULL
      END,
      NULLIF(btrim(sh.raw_legacy_payload ->> 'image_url'), '')
    ) AS image_url
  FROM public.sales_history AS sh
  LEFT JOIN public.products AS p
    ON p.id = sh.product_id
    OR (sh.product_id IS NULL AND p.sku = sh.sku)
  WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
    AND upper(btrim(sh.seller_code)) = v_code
  ORDER BY sh.sold_at_utc DESC NULLS LAST, sh.legacy_id DESC;
END;
$$;

COMMENT ON FUNCTION public.get_my_seller_sales_details(text, date, date) IS
  'Личный кабинет: детализация продаж/возвратов продавца за период (sold_date_kst).';

REVOKE ALL ON FUNCTION public.get_my_seller_sales_details(text, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_seller_sales_details(text, date, date)
  TO anon, authenticated, service_role;

COMMIT;