-- 066: list_price_krw = витринная sale_price/price, НЕ маркетинговый old_price (зачёркнутая цена).
-- Применить в Supabase SQL Editor (после 064).

BEGIN;

-- Витринная цена до POS/промо-скидки в чеке: только sale_price | price.
CREATE OR REPLACE FUNCTION public.product_showroom_list_price_krw(
  p_sale_price integer,
  p_price integer
)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT GREATEST(
    COALESCE(
      NULLIF(p_sale_price, 0),
      NULLIF(p_price, 0),
      0
    ),
    0
  )::bigint;
$$;

COMMENT ON FUNCTION public.product_showroom_list_price_krw(integer, integer) IS
  'База list_price_krw / комиссии: реальная витринная цена (sale_price), без marketing old_price.';

COMMENT ON COLUMN public.sales_history.list_price_krw IS
  'Витринная цена изделия (sale_price/price) до скидки в чеке; не marketing old_price.';

-- ---------------------------------------------------------------------------
-- log_future_sale_to_history (PWA / приложение → sold)
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
  v_list_krw         bigint;
  v_discount         integer;
  v_store            text;
  v_payload          jsonb;
  v_sold_at_utc      timestamptz;
  v_sold_kst         date;
  v_metal_category   text;
  v_seller_code      text;
  v_seller_name      text;
  v_commission_pct   numeric(5, 2);
  v_commission_krw   integer;
  v_product_name     text;
  v_suffix           text;
  v_gallery_slots    jsonb;
BEGIN
  IF NOT (NEW.status = 'sold' AND OLD.status IS DISTINCT FROM 'sold') THEN
    RETURN NEW;
  END IF;

  v_legacy_id := 'pwa_id_' || NEW.id;
  IF EXISTS (
    SELECT 1 FROM public.sales_history AS sh WHERE sh.legacy_id = v_legacy_id
  ) THEN
    v_suffix := floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint::text;
    v_legacy_id := 'pwa_id_' || NEW.id || '_' || v_suffix;
  END IF;

  v_sold_at_utc := timezone('utc', now());
  v_sold_kst := (timezone('Asia/Seoul', now()))::date;
  v_payload := row_to_json(NEW)::jsonb;
  v_list_krw := public.round_krw_up_1000(
    public.product_showroom_list_price_krw(NEW.sale_price, NEW.price)::numeric
  )::bigint;
  v_discount := GREATEST(COALESCE(NEW.discount_percent, 0), 0);
  v_price_krw := public.round_krw_up_1000(
    GREATEST(COALESCE(NEW.sale_price, 0), 0)::numeric
  )::bigint;
  v_store := public._norm_store_icn_ans(NEW.store_location);

  v_metal_category := public.classify_jewelry_metal_category(
    NULLIF(btrim(NEW.metal), ''),
    NULLIF(btrim(NEW.metal_type), '')
  );

  v_product_name := COALESCE(
    NULLIF(btrim(NEW.name ->> 'ru'), ''),
    NULLIF(btrim(NEW.name ->> 'ko'), ''),
    NULLIF(btrim(NEW.sku), '')
  );

  SELECT r.seller_code, r.seller_name
  INTO v_seller_code, v_seller_name
  FROM public.resolve_seller_for_product_sale(NEW.id, NEW.sku, v_product_name) AS r
  LIMIT 1;

  v_commission_pct := 0;
  v_commission_krw := 0;
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

    v_commission_krw := public.seller_commission_krw(
      v_price_krw,
      v_list_krw,
      v_commission_pct
    );
  END IF;

  v_gallery_slots := public._product_gallery_slots_from_row(NEW);
  v_image_url := COALESCE(
    CASE
      WHEN public._product_storage_url_is_primary_slot(NEW.image_url, NEW.sku) THEN
        NULLIF(btrim(NEW.image_url), '')
      ELSE NULL
    END,
    public._product_gallery_slot0_url(v_gallery_slots),
    public.product_storage_image_url_by_sku(NEW.sku)
  );

  INSERT INTO public.sales_history (
    legacy_id, sku, product_id, price_krw, list_price_krw, discount_percent,
    store_location, payment_method,
    sold_at_utc, sold_date_kst, image_url, photo_status, import_batch_id,
    source_system, raw_legacy_payload, migration_meta,
    seller_code, seller_name, metal_category, commission_percent, commission_krw
  )
  VALUES (
    v_legacy_id,
    NEW.sku,
    NEW.id,
    v_price_krw,
    v_list_krw,
    v_discount,
    v_store,
    NULL,
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
      'store_location', v_store,
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

-- ---------------------------------------------------------------------------
-- Бэкфилл: list_price = marketing old_price → sale_price из payload / product
-- ---------------------------------------------------------------------------
WITH candidates AS (
  SELECT
    sh.id,
    public.product_showroom_list_price_krw(
      COALESCE(
        (sh.raw_legacy_payload ->> 'sale_price')::integer,
        p.sale_price
      ),
      COALESCE(
        (sh.raw_legacy_payload ->> 'price')::integer,
        p.price
      )
    ) AS showroom_list
  FROM public.sales_history AS sh
  LEFT JOIN public.products AS p ON p.id = sh.product_id
  WHERE sh.price_krw > 0
    AND COALESCE(sh.list_price_krw, 0) > sh.price_krw
    AND COALESCE(
      (sh.raw_legacy_payload ->> 'old_price')::bigint,
      0
    ) = COALESCE(sh.list_price_krw, 0)
    AND COALESCE(
      (sh.raw_legacy_payload ->> 'old_price')::bigint,
      0
    ) >
      COALESCE(
        NULLIF((sh.raw_legacy_payload ->> 'sale_price')::bigint, 0),
        NULLIF((sh.raw_legacy_payload ->> 'price')::bigint, 0),
        sh.price_krw
      )
),
fixed AS (
  UPDATE public.sales_history AS sh
  SET list_price_krw = GREATEST(c.showroom_list, sh.price_krw)
  FROM candidates AS c
  WHERE sh.id = c.id
    AND c.showroom_list IS NOT NULL
    AND c.showroom_list > 0
    AND c.showroom_list < COALESCE(sh.list_price_krw, 0)
  RETURNING sh.id
)
UPDATE public.sales_history AS sh
SET commission_krw = public.seller_commission_krw(
  sh.price_krw,
  sh.list_price_krw,
  sh.commission_percent
)
FROM fixed AS f
WHERE sh.id = f.id
  AND COALESCE(sh.commission_percent, 0) <> 0;

COMMIT;