-- Ставки продавца для заказов из приложения (комиссия / скидка покупателю по металлу).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) sellers: ставки приложения
-- ---------------------------------------------------------------------------
ALTER TABLE public.sellers
  ADD COLUMN IF NOT EXISTS app_gold_commission_percent numeric(5, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS app_silver_commission_percent numeric(5, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS app_gold_buyer_discount_percent numeric(5, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS app_silver_buyer_discount_percent numeric(5, 2) NOT NULL DEFAULT 0;

ALTER TABLE public.sellers DROP CONSTRAINT IF EXISTS sellers_app_gold_commission_range;
ALTER TABLE public.sellers
  ADD CONSTRAINT sellers_app_gold_commission_range
  CHECK (app_gold_commission_percent >= 0 AND app_gold_commission_percent <= 100);

ALTER TABLE public.sellers DROP CONSTRAINT IF EXISTS sellers_app_silver_commission_range;
ALTER TABLE public.sellers
  ADD CONSTRAINT sellers_app_silver_commission_range
  CHECK (app_silver_commission_percent >= 0 AND app_silver_commission_percent <= 100);

ALTER TABLE public.sellers DROP CONSTRAINT IF EXISTS sellers_app_gold_buyer_discount_range;
ALTER TABLE public.sellers
  ADD CONSTRAINT sellers_app_gold_buyer_discount_range
  CHECK (app_gold_buyer_discount_percent >= 0 AND app_gold_buyer_discount_percent <= 100);

ALTER TABLE public.sellers DROP CONSTRAINT IF EXISTS sellers_app_silver_buyer_discount_range;
ALTER TABLE public.sellers
  ADD CONSTRAINT sellers_app_silver_buyer_discount_range
  CHECK (app_silver_buyer_discount_percent >= 0 AND app_silver_buyer_discount_percent <= 100);

COMMENT ON COLUMN public.sellers.app_gold_commission_percent IS
  'Бонус продавцу за продажу золота через приложение (промокод), %.';
COMMENT ON COLUMN public.sellers.app_silver_commission_percent IS
  'Бонус продавцу за продажу серебра через приложение (промокод), %.';
COMMENT ON COLUMN public.sellers.app_gold_buyer_discount_percent IS
  'Скидка покупателю на золото по промокоду продавца, %.';
COMMENT ON COLUMN public.sellers.app_silver_buyer_discount_percent IS
  'Скидка покупателю на серебро по промокоду продавца, %.';

-- ---------------------------------------------------------------------------
-- 2) upsert_seller_by_admin — 6 ставок (магазин + приложение)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.upsert_seller_by_admin(text, text, boolean);
DROP FUNCTION IF EXISTS public.upsert_seller_by_admin(text, text, boolean, numeric, numeric);

CREATE OR REPLACE FUNCTION public.upsert_seller_by_admin(
  p_promo_code text,
  p_name text,
  p_is_active boolean DEFAULT true,
  p_gold_commission_percent numeric DEFAULT 0,
  p_silver_commission_percent numeric DEFAULT 0,
  p_app_gold_commission_percent numeric DEFAULT 0,
  p_app_silver_commission_percent numeric DEFAULT 0,
  p_app_gold_buyer_discount_percent numeric DEFAULT 0,
  p_app_silver_buyer_discount_percent numeric DEFAULT 0
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code varchar(50);
  v_name varchar(255);
  v_gold numeric(5, 2);
  v_silver numeric(5, 2);
  v_app_gold numeric(5, 2);
  v_app_silver numeric(5, 2);
  v_app_gold_disc numeric(5, 2);
  v_app_silver_disc numeric(5, 2);
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

  v_gold := round(coalesce(p_gold_commission_percent, 0)::numeric, 2);
  v_silver := round(coalesce(p_silver_commission_percent, 0)::numeric, 2);
  v_app_gold := round(coalesce(p_app_gold_commission_percent, 0)::numeric, 2);
  v_app_silver := round(coalesce(p_app_silver_commission_percent, 0)::numeric, 2);
  v_app_gold_disc := round(coalesce(p_app_gold_buyer_discount_percent, 0)::numeric, 2);
  v_app_silver_disc := round(coalesce(p_app_silver_buyer_discount_percent, 0)::numeric, 2);

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

  INSERT INTO public.sellers (
    promo_code,
    name,
    is_active,
    gold_commission_percent,
    silver_commission_percent,
    app_gold_commission_percent,
    app_silver_commission_percent,
    app_gold_buyer_discount_percent,
    app_silver_buyer_discount_percent
  )
  VALUES (
    v_code,
    v_name,
    coalesce(p_is_active, true),
    v_gold,
    v_silver,
    v_app_gold,
    v_app_silver,
    v_app_gold_disc,
    v_app_silver_disc
  )
  ON CONFLICT (promo_code) DO UPDATE SET
    name = EXCLUDED.name,
    is_active = EXCLUDED.is_active,
    gold_commission_percent = EXCLUDED.gold_commission_percent,
    silver_commission_percent = EXCLUDED.silver_commission_percent,
    app_gold_commission_percent = EXCLUDED.app_gold_commission_percent,
    app_silver_commission_percent = EXCLUDED.app_silver_commission_percent,
    app_gold_buyer_discount_percent = EXCLUDED.app_gold_buyer_discount_percent,
    app_silver_buyer_discount_percent = EXCLUDED.app_silver_buyer_discount_percent;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_seller_by_admin(
  text,
  text,
  boolean,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric
) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) apply_seller_referral_promo — скидки по металлу
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_seller_referral_promo(p_promo_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid              uuid := auth.uid();
  v_code             varchar(50);
  v_referred         varchar(50);
  v_active           boolean;
  v_name             varchar(255);
  v_buyer_bonus      integer;
  v_app_gold_disc    numeric(5, 2);
  v_app_silver_disc  numeric(5, 2);
  v_use_app_discount boolean;
  v_gold_discount    integer;
  v_silver_discount  integer;
  v_updated          uuid;
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

  SELECT
    s.buyer_bonus_percent,
    s.is_active,
    s.name,
    s.app_gold_buyer_discount_percent,
    s.app_silver_buyer_discount_percent
  INTO
    v_buyer_bonus,
    v_active,
    v_name,
    v_app_gold_disc,
    v_app_silver_disc
  FROM public.sellers AS s
  WHERE s.promo_code = v_code;

  IF NOT FOUND OR NOT COALESCE(v_active, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_code');
  END IF;

  v_buyer_bonus := GREATEST(COALESCE(v_buyer_bonus, 0), 0);
  v_name := COALESCE(btrim(v_name), '');

  v_use_app_discount :=
    COALESCE(v_app_gold_disc, 0) > 0
    OR COALESCE(v_app_silver_disc, 0) > 0;

  IF v_use_app_discount THEN
    v_gold_discount := GREATEST(round(COALESCE(v_app_gold_disc, 0))::integer, 0);
    v_silver_discount := GREATEST(round(COALESCE(v_app_silver_disc, 0))::integer, 0);
  ELSE
    v_gold_discount := v_buyer_bonus;
    v_silver_discount := v_buyer_bonus;
  END IF;

  IF v_referred IS NOT NULL AND v_referred <> v_code THEN
    RETURN jsonb_build_object(
      'ok', true,
      'already_referred', true,
      'discount_percent', 0,
      'gold_discount_percent', 0,
      'silver_discount_percent', 0,
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
    'gold_discount_percent', v_gold_discount,
    'silver_discount_percent', v_silver_discount,
    'discount_percent', GREATEST(v_gold_discount, v_silver_discount),
    'seller_code', v_code,
    'seller_name', v_name
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.apply_seller_referral_promo(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4) log_future_sale_to_history — комиссия по ставкам приложения
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_future_sale_to_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_legacy_id        text;
  v_image_url        text;
  v_price_krw        bigint;
  v_payload          jsonb;
  v_sold_at_utc      timestamptz;
  v_sold_kst         date;
  v_metal_category   text;
  v_seller_code      text;
  v_seller_name      text;
  v_commission_pct   numeric(5, 2);
  v_commission_krw   integer;
  v_product_name     text;
  v_resolved         record;
BEGIN
  IF NOT (
    (NEW.stock_quantity = 0 AND COALESCE(OLD.stock_quantity, 0) > 0)
    OR (NEW.status = 'sold' AND OLD.status IS DISTINCT FROM 'sold')
  ) THEN
    RETURN NEW;
  END IF;

  v_legacy_id := 'pwa_id_' || NEW.id;
  v_sold_at_utc := timezone('utc', now());
  v_sold_kst := (timezone('Asia/Seoul', now()))::date;
  v_payload := row_to_json(NEW)::jsonb;
  v_price_krw := COALESCE(NEW.sale_price, 0)::bigint;

  v_metal_category := public.classify_jewelry_metal_category(
    NULLIF(btrim(NEW.metal), ''),
    NULLIF(btrim(NEW.metal_type), '')
  );

  v_product_name := COALESCE(
    NULLIF(btrim(NEW.name ->> 'ru'), ''),
    NULLIF(btrim(NEW.name ->> 'ko'), ''),
    NULLIF(btrim(NEW.name ->> 'en'), ''),
    NULLIF(btrim(NEW.sku), '')
  );

  v_seller_code := NULL;
  v_seller_name := NULL;
  v_commission_pct := 0;
  v_commission_krw := 0;

  SELECT r.seller_code, r.seller_name
  INTO v_seller_code, v_seller_name
  FROM public.resolve_seller_for_product_sale(NEW.id, NEW.sku, v_product_name) AS r
  LIMIT 1;

  IF v_seller_code IS NOT NULL THEN
    SELECT
      public.seller_commission_rate_for_metal(
        s.app_gold_commission_percent,
        s.app_silver_commission_percent,
        v_metal_category
      ),
      s.name
    INTO v_commission_pct, v_seller_name
    FROM public.sellers AS s
    WHERE s.promo_code = upper(v_seller_code);

    v_commission_krw := round(
      (v_price_krw::numeric * COALESCE(v_commission_pct, 0) / 100.0)
    )::integer;
  END IF;

  v_image_url := NULLIF(btrim(COALESCE(NEW.image_url, '')), '');
  IF v_image_url IS NULL
     AND v_payload ? 'additional_images'
     AND jsonb_typeof(v_payload -> 'additional_images') = 'array'
     AND jsonb_array_length(v_payload -> 'additional_images') > 0
  THEN
    v_image_url := NULLIF(btrim(v_payload -> 'additional_images' ->> 0), '');
  END IF;

  INSERT INTO public.sales_history (
    legacy_id,
    sku,
    product_id,
    price_krw,
    sold_at_utc,
    sold_date_kst,
    image_url,
    photo_status,
    import_batch_id,
    source_system,
    raw_legacy_payload,
    migration_meta,
    seller_code,
    seller_name,
    metal_category,
    commission_percent,
    commission_krw
  )
  VALUES (
    v_legacy_id,
    NEW.sku,
    NEW.id,
    v_price_krw,
    v_sold_at_utc,
    v_sold_kst,
    v_image_url,
    'success',
    '00000000-0000-0000-0000-000000000000'::uuid,
    'pwa_store',
    v_payload,
    jsonb_build_object(
      'source_system', 'pwa_store',
      'logged_by', 'trg_log_pwa_sale',
      'product_id', NEW.id,
      'sold_at_utc', v_sold_at_utc,
      'sold_date_kst', v_sold_kst::text
    ),
    v_seller_code,
    v_seller_name,
    v_metal_category,
    COALESCE(v_commission_pct, 0),
    COALESCE(v_commission_krw, 0)
  )
  ON CONFLICT (legacy_id) DO NOTHING;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.log_future_sale_to_history() IS
  'AFTER UPDATE products: sold/stock 0 → sales_history; комиссия продавца по app_* ставкам.';

COMMIT;