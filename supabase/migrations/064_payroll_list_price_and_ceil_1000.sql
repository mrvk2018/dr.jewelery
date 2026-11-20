-- 064: комиссия от list_price_krw; цены изделий CEIL до 1 000 ₩ (новые расчёты).
-- Применить целиком в Supabase SQL Editor (после 063).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Хелперы
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.round_krw_up_1000(p_amount numeric)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN COALESCE(p_amount, 0) <= 0 THEN 0
    ELSE (ceil(round(p_amount, 4) / 1000.0) * 1000)::integer
  END;
$$;

CREATE OR REPLACE FUNCTION public.seller_commission_krw(
  p_price_krw bigint,
  p_list_price_krw bigint,
  p_commission_percent numeric
)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (
    CASE WHEN COALESCE(p_price_krw, 0) < 0 THEN -1 ELSE 1 END
  ) * round(
    COALESCE(
      NULLIF(abs(p_list_price_krw), 0),
      abs(p_price_krw)
    )::numeric * COALESCE(p_commission_percent, 0) / 100.0
  )::integer;
$$;

CREATE OR REPLACE FUNCTION public.seller_turnover_krw(
  p_price_krw bigint,
  p_list_price_krw bigint
)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN COALESCE(p_price_krw, 0) < 0 THEN p_price_krw
    ELSE COALESCE(NULLIF(p_list_price_krw, 0), p_price_krw)::bigint
  END;
$$;

COMMENT ON FUNCTION public.round_krw_up_1000(numeric) IS
  'Цена изделия: округление вверх до 1 000 ₩.';
COMMENT ON FUNCTION public.seller_commission_krw(bigint, bigint, numeric) IS
  'Комиссия продавца от list_price (fallback price_krw), знак от price_krw.';
COMMENT ON FUNCTION public.seller_turnover_krw(bigint, bigint) IS
  'База оборота в отчётах: list для продаж, price_krw для возвратов.';

GRANT EXECUTE ON FUNCTION public.round_krw_up_1000(numeric)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.seller_commission_krw(bigint, bigint, numeric)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.seller_turnover_krw(bigint, bigint)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) Триггер: нормализация price / sale_price / old_price в products
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_products_round_prices_krw()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.sale_price IS NOT NULL AND NEW.sale_price > 0 THEN
    NEW.sale_price := public.round_krw_up_1000(NEW.sale_price);
  END IF;
  IF NEW.price IS NOT NULL AND NEW.price > 0 THEN
    NEW.price := public.round_krw_up_1000(NEW.price);
  END IF;
  IF NEW.old_price IS NOT NULL AND NEW.old_price > 0 THEN
    NEW.old_price := public.round_krw_up_1000(NEW.old_price);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_round_prices_krw ON public.products;
CREATE TRIGGER trg_products_round_prices_krw
  BEFORE INSERT OR UPDATE OF sale_price, price, old_price
  ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_products_round_prices_krw();

-- ---------------------------------------------------------------------------
-- 3) log_future_sale_to_history — list-комиссия + округление цен в чеке
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
    GREATEST(COALESCE(NEW.old_price, NEW.sale_price, 0), 0)::numeric
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
-- 4) archive_admin_pos_sale — CEIL цен + комиссия от list
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.archive_admin_pos_sale(
  p_lines jsonb,
  p_seller_name text DEFAULT NULL,
  p_payment_method text DEFAULT NULL,
  p_seller_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line jsonb;
  v_pid text;
  v_discount integer;
  v_row public.products%ROWTYPE;
  v_list bigint;
  v_final bigint;
  v_store text;
  v_payment text;
  v_seller text;
  v_metal text;
  v_sold bigint := 0;
  v_order_id text;
  v_history_id uuid;
  v_code_input text;
  v_seller_code text;
  v_resolved_name text;
  v_gold_pct numeric;
  v_silver_pct numeric;
  v_display_seller_name text;
  v_commission_pct numeric;
  v_commission_krw integer;
BEGIN
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array'
     OR jsonb_array_length(p_lines) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'empty_cart');
  END IF;

  v_seller := NULLIF(btrim(COALESCE(p_seller_name, '')), '');
  v_payment := NULLIF(btrim(COALESCE(p_payment_method, '')), '');
  IF v_payment IS NOT NULL
     AND v_payment NOT IN ('cash', 'card', 'transfer') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_payment_method');
  END IF;
  IF v_seller IS NULL OR v_payment IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'seller_and_payment_required');
  END IF;

  v_code_input := NULLIF(upper(btrim(COALESCE(p_seller_code, ''))), '');
  IF v_code_input IS NOT NULL THEN
    SELECT
      s.promo_code,
      s.name,
      s.gold_commission_percent,
      s.silver_commission_percent
    INTO v_seller_code, v_resolved_name, v_gold_pct, v_silver_pct
    FROM public.sellers AS s
    WHERE s.promo_code = v_code_input
      AND s.is_active;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'seller_not_found');
    END IF;
  ELSE
    SELECT
      r.promo_code,
      r.name,
      r.gold_commission_percent,
      r.silver_commission_percent
    INTO v_seller_code, v_resolved_name, v_gold_pct, v_silver_pct
    FROM public.resolve_seller_by_name(v_seller) AS r
    LIMIT 1;

    IF v_seller_code IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'seller_not_resolved');
    END IF;
  END IF;

  v_display_seller_name := CASE
    WHEN v_seller_code = 'ADMIN' THEN v_seller
    ELSE COALESCE(v_resolved_name, v_seller)
  END;

  v_order_id := 'pos_' || replace(gen_random_uuid()::text, '-', '');

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_pid := NULLIF(btrim(COALESCE(v_line ->> 'product_id', '')), '');
    IF v_pid IS NULL THEN
      CONTINUE;
    END IF;

    v_discount := GREATEST(
      COALESCE((v_line ->> 'discount_percent')::integer, 0),
      0
    );
    v_discount := LEAST(v_discount, 100);

    SELECT * INTO v_row
    FROM public.products AS p
    WHERE p.id = v_pid
    FOR UPDATE;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', format('product_not_found:%s', v_pid));
    END IF;

    IF v_row.status NOT IN ('active', 'reserved', 'hidden') THEN
      RETURN jsonb_build_object('ok', false, 'error', format('product_unavailable:%s', v_pid));
    END IF;

    v_list := public.round_krw_up_1000(
      GREATEST(COALESCE(v_row.sale_price, 0), 0)::numeric
    )::bigint;
    v_final := public.round_krw_up_1000(
      v_list::numeric * (100 - v_discount) / 100.0
    )::bigint;
    v_store := public._norm_store_icn_ans(v_row.store_location);
    v_metal := public.classify_jewelry_metal_category(
      NULLIF(btrim(v_row.metal), ''),
      NULLIF(btrim(v_row.metal_type), '')
    );

    v_commission_pct := public.seller_commission_rate_for_metal(
      v_gold_pct,
      v_silver_pct,
      v_metal
    );
    v_commission_krw := public.seller_commission_krw(
      v_final,
      v_list,
      v_commission_pct
    );

    UPDATE public.products AS p
    SET
      status = 'sold',
      stock_quantity = 0,
      updated_at = now()
    WHERE p.id = v_pid;

    SELECT sh.id
    INTO v_history_id
    FROM public.sales_history AS sh
    WHERE sh.product_id = v_pid
    ORDER BY sh.sold_at_utc DESC NULLS LAST, sh.legacy_id DESC
    LIMIT 1;

    IF v_history_id IS NULL THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', format('sales_history_missing_after_trigger:%s', v_pid)
      );
    END IF;

    UPDATE public.sales_history AS sh
    SET
      price_krw = v_final,
      list_price_krw = v_list,
      discount_percent = v_discount,
      payment_method = v_payment,
      seller_code = v_seller_code,
      seller_name = v_display_seller_name,
      store_location = v_store,
      metal_category = v_metal,
      commission_percent = COALESCE(v_commission_pct, 0),
      commission_krw = COALESCE(v_commission_krw, 0),
      migration_meta = COALESCE(sh.migration_meta, '{}'::jsonb) || jsonb_build_object(
        'pos_order_id', v_order_id,
        'pos_seller_name', v_seller,
        'pos_seller_code', v_seller_code,
        'pos_payment_method', v_payment,
        'logged_by', 'archive_admin_pos_sale'
      )
    WHERE sh.id = v_history_id;
  END LOOP;

  v_sold := jsonb_array_length(p_lines);

  RETURN jsonb_build_object(
    'ok', true,
    'order_id', v_order_id,
    'lines', v_sold,
    'seller_code', v_seller_code
  );
END;
$$;

REVOKE ALL ON FUNCTION public.archive_admin_pos_sale(jsonb, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.archive_admin_pos_sale(jsonb, text, text, text)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5) attach_seller_to_sales — комиссия от list_price
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.attach_seller_to_sales(
  p_skus text[],
  p_seller_code text,
  p_seller_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
  v_name text;
  v_updated bigint := 0;
  v_gold numeric(5, 2);
  v_silver numeric(5, 2);
  v_cutoff timestamptz;
BEGIN
  v_code := upper(btrim(coalesce(p_seller_code, '')));
  v_name := btrim(coalesce(p_seller_name, ''));
  v_cutoff := timezone('utc', now()) - interval '15 minutes';

  IF v_code = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'empty_seller_code');
  END IF;

  IF p_skus IS NULL OR array_length(p_skus, 1) IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'empty_skus');
  END IF;

  SELECT
    s.gold_commission_percent,
    s.silver_commission_percent,
    s.name
  INTO v_gold, v_silver, v_name
  FROM public.sellers AS s
  WHERE s.promo_code = v_code AND s.is_active;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'seller_not_found');
  END IF;

  IF v_name = '' OR v_name IS NULL THEN
    v_name := (SELECT s2.name FROM public.sellers s2 WHERE s2.promo_code = v_code);
  END IF;

  WITH norm_skus AS (
    SELECT DISTINCT upper(btrim(x)) AS sku
    FROM unnest(p_skus) AS x
    WHERE btrim(coalesce(x, '')) <> ''
  ),
  touched AS (
    UPDATE public.sales_history AS sh
    SET
      seller_code = v_code,
      seller_name = v_name,
      metal_category = COALESCE(
        sh.metal_category,
        public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
        'other'
      ),
      commission_percent = public.seller_commission_rate_for_metal(
        v_gold,
        v_silver,
        COALESCE(
          sh.metal_category,
          public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
          'other'
        )
      ),
      commission_krw = public.seller_commission_krw(
        sh.price_krw,
        sh.list_price_krw,
        public.seller_commission_rate_for_metal(
          v_gold,
          v_silver,
          COALESCE(
            sh.metal_category,
            public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
            'other'
          )
        )
      )
    FROM norm_skus AS n
    WHERE upper(btrim(coalesce(sh.sku, ''))) = n.sku
      AND sh.price_krw > 0
      AND sh.sold_at_utc >= v_cutoff
    RETURNING sh.id
  )
  SELECT count(*)::bigint INTO v_updated FROM touched;

  RETURN jsonb_build_object('ok', true, 'updated', v_updated, 'seller_code', v_code);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6) process_product_return_manual — сторно комиссии от list
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.process_product_return_manual(
  p_sku text,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sku            text;
  v_product_id     text;
  v_product_status text;
  v_stock          integer;
  v_sale           record;
  v_return_legacy text;
  v_reversal_id   uuid;
  v_sold_kst      date;
  v_sold_utc      timestamptz;
  v_commission_krw integer;
BEGIN
  v_sku := NULLIF(btrim(p_sku), '');
  IF v_sku IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'empty_sku');
  END IF;

  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  SELECT p.id, p.status, COALESCE(p.stock_quantity, 0)
  INTO v_product_id, v_product_status, v_stock
  FROM public.products AS p
  WHERE p.sku = v_sku
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'product_not_found');
  END IF;

  IF v_product_status IS DISTINCT FROM 'sold' AND v_stock > 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'product_not_sold');
  END IF;

  SELECT sh.*
  INTO v_sale
  FROM public.sales_history AS sh
  WHERE sh.sku = v_sku
    AND sh.price_krw > 0
    AND NOT EXISTS (
      SELECT 1
      FROM public.sales_history AS r
      WHERE (r.migration_meta ->> 'reverses_legacy_id') = sh.legacy_id
        AND COALESCE(r.migration_meta ->> 'type', '') = 'return'
    )
  ORDER BY sh.sold_at_utc DESC NULLS LAST, sh.legacy_id DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sale_not_found');
  END IF;

  v_return_legacy := 'return_' || v_sale.legacy_id;

  IF EXISTS (
    SELECT 1 FROM public.sales_history WHERE legacy_id = v_return_legacy
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_returned');
  END IF;

  v_sold_utc := timezone('utc', now());
  v_sold_kst := (timezone('Asia/Seoul', now()))::date;

  v_commission_krw := (-1) * abs(
    COALESCE(
      v_sale.commission_krw,
      public.seller_commission_krw(
        v_sale.price_krw,
        v_sale.list_price_krw,
        v_sale.commission_percent
      )
    )
  );

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
    v_return_legacy,
    v_sale.sku,
    v_sale.product_id,
    (-1) * v_sale.price_krw,
    v_sold_utc,
    v_sold_kst,
    v_sale.image_url,
    COALESCE(v_sale.photo_status, 'success'),
    v_sale.import_batch_id,
    'pwa_store',
    jsonb_build_object('type', 'return', 'original_payload', v_sale.raw_legacy_payload),
    jsonb_build_object(
      'type', 'return',
      'reverses_legacy_id', v_sale.legacy_id,
      'processed_by', 'process_product_return_manual',
      'returned_at_utc', v_sold_utc,
      'original_sold_date_kst', v_sale.sold_date_kst::text
    ),
    v_sale.seller_code,
    v_sale.seller_name,
    v_sale.metal_category,
    COALESCE(v_sale.commission_percent, 0),
    v_commission_krw
  )
  RETURNING id INTO v_reversal_id;

  UPDATE public.products
  SET
    status = 'active',
    stock_quantity = 1,
    updated_at = now()
  WHERE id = v_product_id;

  RETURN jsonb_build_object(
    'ok', true,
    'sku', v_sku,
    'product_id', v_product_id,
    'reversal_id', v_reversal_id::text,
    'reversal_legacy_id', v_return_legacy,
    'price_krw', (-1) * v_sale.price_krw,
    'sold_date_kst', v_sold_kst::text,
    'reverses_legacy_id', v_sale.legacy_id,
    'commission_krw', v_commission_krw
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 7) upsert_seller_by_admin — пересчёт ADMIN от list_price (как 063)
-- ---------------------------------------------------------------------------
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
      commission_krw = public.seller_commission_krw(
        sh.price_krw,
        sh.list_price_krw,
        public.seller_commission_rate_for_metal(
          v_gold,
          v_silver,
          COALESCE(NULLIF(btrim(sh.metal_category), ''), 'other')
        )
      )
    WHERE upper(btrim(COALESCE(sh.seller_code, ''))) = 'ADMIN'
      AND sh.price_krw <> 0;
  END IF;

  RETURN true;
END;
$$;

-- ---------------------------------------------------------------------------
-- 8) get_seller_payroll_summary — оборот = seller_turnover_krw
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_seller_payroll_summary(
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH period AS (
    SELECT sh.*
    FROM public.sales_history AS sh
    WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
  ),
  agg AS (
    SELECT
      upper(btrim(sh.seller_code)) AS code,
      count(*) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'gold') AS gold_cnt,
      coalesce(sum(public.seller_turnover_krw(sh.price_krw, sh.list_price_krw))
        FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'gold'), 0) AS gold_krw,
      coalesce(sum(sh.commission_krw) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'gold'), 0) AS gold_comm,
      count(*) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'silver') AS silver_cnt,
      coalesce(sum(public.seller_turnover_krw(sh.price_krw, sh.list_price_krw))
        FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'silver'), 0) AS silver_krw,
      coalesce(sum(sh.commission_krw) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'silver'), 0) AS silver_comm,
      count(*) FILTER (WHERE sh.price_krw < 0) AS ret_cnt,
      coalesce(sum(sh.commission_krw) FILTER (WHERE sh.price_krw < 0), 0) AS ret_comm,
      coalesce(sum(sh.commission_krw), 0) AS total_comm
    FROM period AS sh
    WHERE NULLIF(btrim(sh.seller_code), '') IS NOT NULL
    GROUP BY upper(btrim(sh.seller_code))
  ),
  seller_rows AS (
    SELECT
      s.promo_code::text,
      s.name::text AS seller_name,
      s.is_active,
      s.gold_commission_percent,
      s.silver_commission_percent,
      coalesce(a.gold_cnt, 0) AS gold_sales_count,
      coalesce(a.gold_krw, 0)::bigint AS gold_sales_krw,
      coalesce(a.gold_comm, 0)::bigint AS gold_commission_krw,
      coalesce(a.silver_cnt, 0) AS silver_sales_count,
      coalesce(a.silver_krw, 0)::bigint AS silver_sales_krw,
      coalesce(a.silver_comm, 0)::bigint AS silver_commission_krw,
      coalesce(a.ret_cnt, 0) AS returns_count,
      coalesce(a.ret_comm, 0)::bigint AS returns_commission_krw,
      coalesce(a.total_comm, 0)::bigint AS total_commission_krw
    FROM public.sellers AS s
    LEFT JOIN agg AS a ON a.code = s.promo_code
  ),
  unassigned AS (
    SELECT
      '__UNASSIGNED__'::text AS promo_code,
      'Без продавца'::text AS seller_name,
      true AS is_active,
      0::numeric AS gold_commission_percent,
      0::numeric AS silver_commission_percent,
      coalesce(sum(
        CASE WHEN sh.price_krw > 0 AND sh.metal_category = 'gold' THEN 1 ELSE 0 END
      ), 0)::bigint AS gold_sales_count,
      coalesce(sum(public.seller_turnover_krw(sh.price_krw, sh.list_price_krw))
        FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'gold'), 0)::bigint AS gold_sales_krw,
      coalesce(sum(sh.commission_krw) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'gold'), 0)::bigint AS gold_commission_krw,
      coalesce(sum(
        CASE WHEN sh.price_krw > 0 AND sh.metal_category = 'silver' THEN 1 ELSE 0 END
      ), 0)::bigint AS silver_sales_count,
      coalesce(sum(public.seller_turnover_krw(sh.price_krw, sh.list_price_krw))
        FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'silver'), 0)::bigint AS silver_sales_krw,
      coalesce(sum(sh.commission_krw) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'silver'), 0)::bigint AS silver_commission_krw,
      coalesce(sum(
        CASE WHEN sh.price_krw < 0 THEN 1 ELSE 0 END
      ), 0)::bigint AS returns_count,
      coalesce(sum(sh.commission_krw) FILTER (WHERE sh.price_krw < 0), 0)::bigint AS returns_commission_krw,
      coalesce(sum(sh.commission_krw), 0)::bigint AS total_commission_krw
    FROM period AS sh
    WHERE NULLIF(btrim(sh.seller_code), '') IS NULL
    HAVING count(*) > 0
  )
  SELECT * FROM seller_rows
  UNION ALL
  SELECT * FROM unassigned
  ORDER BY 1;
$$;

-- ---------------------------------------------------------------------------
-- 9) Детализация продаж — price_krw = база оборота (list)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_seller_sales_details(text, date, date);

CREATE OR REPLACE FUNCTION public.get_seller_sales_details(
  p_seller_code text,
  p_date_from date,
  p_date_to date
)
RETURNS TABLE (
  sale_id text,
  sold_at timestamptz,
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    sh.id::text AS sale_id,
    sh.sold_at_utc AS sold_at,
    sh.sku,
    COALESCE(
      NULLIF(btrim(p.name ->> 'ru'), ''),
      NULLIF(btrim(p.name ->> 'ko'), ''),
      NULLIF(btrim(p.name ->> 'en'), ''),
      NULLIF(btrim(p_sku.name ->> 'ru'), ''),
      NULLIF(btrim(p_sku.name ->> 'ko'), ''),
      NULLIF(btrim(p_sku.name ->> 'en'), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'Type'), ''),
      NULLIF(btrim(sh.sku), '')
    ) AS product_name,
    COALESCE(
      sh.metal_category,
      public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
      'other'
    ) AS metal_category,
    COALESCE(
      NULLIF(btrim(p.metal_type), ''),
      NULLIF(btrim(p.metal), ''),
      NULLIF(btrim(p_sku.metal_type), ''),
      NULLIF(btrim(p_sku.metal), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'metal_type'), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'metal'), '')
    ) AS metal_label,
    COALESCE(
      p.weight_grams,
      p_sku.weight_grams,
      public.sales_history_payload_weight_grams(sh.raw_legacy_payload)
    ) AS weight_grams,
    public.seller_turnover_krw(sh.price_krw, sh.list_price_krw)::integer AS price_krw,
    sh.commission_percent,
    sh.commission_krw,
    (sh.price_krw < 0) AS is_return,
    COALESCE(
      public.product_primary_image_url(p),
      public.product_primary_image_url(p_sku),
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
  LEFT JOIN public.products AS p ON p.id = sh.product_id
  LEFT JOIN LATERAL (
    SELECT ps.*
    FROM public.products AS ps
    WHERE NULLIF(btrim(sh.sku), '') IS NOT NULL
      AND upper(btrim(ps.sku)) = upper(btrim(sh.sku))
    ORDER BY
      (public.product_primary_image_url(ps) IS NOT NULL) DESC,
      ps.updated_at DESC NULLS LAST
    LIMIT 1
  ) AS p_sku ON true
  WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
    AND (
      (
        upper(btrim(p_seller_code)) = '__UNASSIGNED__'
        AND NULLIF(btrim(sh.seller_code), '') IS NULL
      )
      OR upper(btrim(sh.seller_code)) = upper(btrim(p_seller_code))
    )
  ORDER BY sh.sold_at_utc DESC NULLS LAST, sh.legacy_id DESC;
$$;

DROP FUNCTION IF EXISTS public.get_my_seller_sales_details(text, date, date);

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
      NULLIF(btrim(p_sku.name ->> 'ru'), ''),
      NULLIF(btrim(p_sku.name ->> 'ko'), ''),
      NULLIF(btrim(p_sku.name ->> 'en'), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'Type'), ''),
      NULLIF(btrim(sh.sku), '')
    ) AS product_name,
    COALESCE(
      sh.metal_category,
      public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
      'other'
    ) AS metal_category,
    COALESCE(
      NULLIF(btrim(p.metal_type), ''),
      NULLIF(btrim(p.metal), ''),
      NULLIF(btrim(p_sku.metal_type), ''),
      NULLIF(btrim(p_sku.metal), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'metal_type'), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'metal'), '')
    ) AS metal_label,
    COALESCE(
      p.weight_grams,
      p_sku.weight_grams,
      public.sales_history_payload_weight_grams(sh.raw_legacy_payload)
    ) AS weight_grams,
    public.seller_turnover_krw(sh.price_krw, sh.list_price_krw)::integer AS price_krw,
    sh.commission_percent,
    sh.commission_krw,
    (sh.price_krw < 0) AS is_return,
    COALESCE(
      public.product_primary_image_url(p),
      public.product_primary_image_url(p_sku),
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
  LEFT JOIN public.products AS p ON p.id = sh.product_id
  LEFT JOIN LATERAL (
    SELECT ps.*
    FROM public.products AS ps
    WHERE NULLIF(btrim(sh.sku), '') IS NOT NULL
      AND upper(btrim(ps.sku)) = upper(btrim(sh.sku))
    ORDER BY
      (public.product_primary_image_url(ps) IS NOT NULL) DESC,
      ps.updated_at DESC NULLS LAST
    LIMIT 1
  ) AS p_sku ON true
  WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
    AND upper(btrim(sh.seller_code)) = v_code
  ORDER BY sh.sold_at_utc DESC NULLS LAST, sh.legacy_id DESC;
END;
$$;

-- ---------------------------------------------------------------------------
-- 10) get_advanced_faceted_products — effective_price с CEIL 1 000 ₩
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_advanced_faceted_products(
  metal_tags text[],
  category_tags text[],
  advanced_tags text[],
  min_price numeric,
  max_price numeric,
  gold_gram_price numeric,
  silver_gram_price numeric,
  exact_weight numeric DEFAULT NULL,
  sku_query text DEFAULT NULL,
  p_store_location text DEFAULT NULL
)
RETURNS SETOF public.products
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_metal    text[] := COALESCE(metal_tags, '{}'::text[]);
  v_category text[] := COALESCE(category_tags, '{}'::text[]);
  v_adv      text[] := COALESCE(advanced_tags, '{}'::text[]);
  v_store    text := NULLIF(upper(btrim(COALESCE(p_store_location, ''))), '');
BEGIN
  RETURN QUERY
  SELECT p.*
  FROM public.products AS p
  CROSS JOIN LATERAL (
    SELECT CASE
      WHEN p.sale_price IS NOT NULL AND p.sale_price > 0 THEN
        public.round_krw_up_1000(p.sale_price::numeric)
      WHEN p.weight_grams IS NULL THEN NULL::numeric
      WHEN COALESCE(p.metal, p.metal_type, '') ILIKE '%золото%'
        OR COALESCE(p.metal, p.metal_type, '') ~ '585'
        OR COALESCE(p.metal, p.metal_type, '') ~ '750' THEN
        public.round_krw_up_1000(p.weight_grams * gold_gram_price)
      WHEN COALESCE(p.metal, p.metal_type, '') ILIKE '%серебр%'
        OR COALESCE(p.metal, p.metal_type, '') ~ '925' THEN
        public.round_krw_up_1000(p.weight_grams * silver_gram_price)
      ELSE NULL::numeric
    END AS effective_price
  ) AS pr
  WHERE p.stock_quantity > 0
    AND COALESCE(p.status, 'active') = 'active'
    AND (
      v_store IS NULL
      OR upper(btrim(COALESCE(p.store_location, 'ICN'))) = v_store
    )
    AND (
      min_price IS NULL AND max_price IS NULL
      OR (
        (min_price IS NULL OR (pr.effective_price IS NOT NULL AND pr.effective_price >= min_price))
        AND (max_price IS NULL OR (pr.effective_price IS NOT NULL AND pr.effective_price <= max_price))
      )
    )
    AND (
      cardinality(v_metal) = 0
      OR EXISTS (
        SELECT 1
        FROM unnest(v_metal) AS t(tag)
        WHERE btrim(tag) <> ''
          AND public.showroom_metal_facet_match(p, tag)
      )
    )
    AND (
      cardinality(v_category) = 0
      OR EXISTS (
        SELECT 1
        FROM unnest(v_category) AS t(tag)
        WHERE btrim(tag) <> ''
          AND public.showroom_category_facet_match(p, tag)
      )
    )
    AND (
      cardinality(v_adv) = 0
      OR EXISTS (
        SELECT 1
        FROM unnest(v_adv) AS t(tag)
        WHERE btrim(tag) <> ''
          AND (
            CASE
              WHEN lower(btrim(tag)) = 'без вставок' THEN (
                COALESCE(NULLIF(btrim(p.gem_inserts::text), ''), NULLIF(btrim(p."insert"), ''), '') = ''
                OR COALESCE(NULLIF(btrim(p.gem_inserts::text), ''), NULLIF(btrim(p."insert"), ''), '') IN ('—', '-')
                OR COALESCE(p."insert", '') ILIKE '%без вставок%'
                OR COALESCE(p."insert", '') ILIKE '%без камней%'
                OR COALESCE(p.gem_inserts::text, '') ILIKE '%без вставок%'
                OR COALESCE(p.gem_inserts::text, '') ILIKE '%без камней%'
              )
              ELSE (
                COALESCE(p."insert", '') ILIKE '%' || tag || '%'
                OR COALESCE(p.gem_inserts::text, '') ILIKE '%' || tag || '%'
                OR COALESCE(p.notes, '') ILIKE '%' || tag || '%'
                OR COALESCE(p.name::text, '') ILIKE '%' || tag || '%'
                OR COALESCE(p.category, '') ILIKE '%' || tag || '%'
              )
            END
          )
      )
    )
    AND (
      exact_weight IS NULL
      OR (
        p.weight_grams IS NOT NULL
        AND ROUND(p.weight_grams, 2) = ROUND(exact_weight, 2)
      )
    )
    AND (
      NULLIF(BTRIM(sku_query), '') IS NULL
      OR p.sku ILIKE ('%' || BTRIM(sku_query) || '%')
    )
  ORDER BY p.sku;
END;
$$;

-- ---------------------------------------------------------------------------
-- 11) Бэкфилл commission_krw от list_price_krw (ставка > 0)
-- ---------------------------------------------------------------------------
UPDATE public.sales_history AS sh
SET commission_krw = public.seller_commission_krw(
  sh.price_krw,
  sh.list_price_krw,
  sh.commission_percent
)
WHERE COALESCE(sh.commission_percent, 0) <> 0;

COMMIT;