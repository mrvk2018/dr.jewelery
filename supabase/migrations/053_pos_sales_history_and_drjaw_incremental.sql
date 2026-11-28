-- 053: POS — seller_name, payment_method, metal_category на все pwa_id_* (включая суффикс).
--      Повторная продажа: legacy_id = pwa_id_{id}_{epoch_ms} при конфликте.
--      Бэкфилл metal_category по products для существующих POS-строк.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) log_future_sale_to_history — суффикс при повторной продаже
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
  v_list_krw := GREATEST(COALESCE(NEW.old_price, NEW.sale_price, 0), 0)::bigint;
  v_discount := GREATEST(COALESCE(NEW.discount_percent, 0), 0);
  v_price_krw := GREATEST(COALESCE(NEW.sale_price, 0), 0)::bigint;
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

    v_commission_krw := round(
      (v_price_krw::numeric * COALESCE(v_commission_pct, 0) / 100.0)
    )::integer;
  END IF;

  v_image_url := NULLIF(btrim(COALESCE(NEW.image_url, '')), '');

  INSERT INTO public.sales_history (
    legacy_id, sku, product_id, price_krw, list_price_krw, discount_percent,
    store_location, payment_method,
    sold_at_utc, sold_date_kst, image_url, photo_status, import_batch_id,
    source_system, raw_legacy_payload, migration_meta,
    seller_code, seller_name, metal_category, commission_percent, commission_krw
  )
  VALUES (
    v_legacy_id, NEW.sku, NEW.id, v_price_krw, v_list_krw, v_discount,
    v_store, NULL,
    v_sold_at_utc, v_sold_kst, v_image_url, 'success',
    '00000000-0000-0000-0000-000000000000'::uuid,
    'pwa_store', v_payload,
    jsonb_build_object(
      'source_system', 'pwa_store',
      'logged_by', 'trg_log_pwa_sale',
      'product_id', NEW.id,
      'store_location', v_store,
      'sold_at_utc', v_sold_at_utc,
      'sold_date_kst', v_sold_kst::text
    ),
    v_seller_code, v_seller_name, v_metal_category,
    COALESCE(v_commission_pct, 0), COALESCE(v_commission_krw, 0)
  )
  ON CONFLICT (legacy_id) DO NOTHING;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.log_future_sale_to_history() IS
  'status→sold: sales_history; при занятом pwa_id_{id} — pwa_id_{id}_{epoch_ms}.';

-- ---------------------------------------------------------------------------
-- 2) archive_admin_pos_sale — seller, payment, metal на последнюю строку продукта
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.archive_admin_pos_sale(jsonb, text, text);

CREATE OR REPLACE FUNCTION public.archive_admin_pos_sale(
  p_lines jsonb,
  p_seller_name text DEFAULT NULL,
  p_payment_method text DEFAULT NULL
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

    v_list := GREATEST(COALESCE(v_row.sale_price, 0), 0)::bigint;
    v_final := round(v_list::numeric * (100 - v_discount) / 100.0)::bigint;
    v_store := public._norm_store_icn_ans(v_row.store_location);
    v_metal := public.classify_jewelry_metal_category(
      NULLIF(btrim(v_row.metal), ''),
      NULLIF(btrim(v_row.metal_type), '')
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
      seller_name = v_seller,
      store_location = v_store,
      metal_category = v_metal,
      migration_meta = COALESCE(sh.migration_meta, '{}'::jsonb) || jsonb_build_object(
        'pos_order_id', v_order_id,
        'pos_seller_name', v_seller,
        'pos_payment_method', v_payment,
        'logged_by', 'archive_admin_pos_sale'
      )
    WHERE sh.id = v_history_id;
  END LOOP;

  v_sold := jsonb_array_length(p_lines);

  RETURN jsonb_build_object(
    'ok', true,
    'order_id', v_order_id,
    'lines', v_sold
  );
END;
$$;

REVOKE ALL ON FUNCTION public.archive_admin_pos_sale(jsonb, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.archive_admin_pos_sale(jsonb, text, text)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) Бэкфилл metal_category для существующих POS-продаж
-- ---------------------------------------------------------------------------
UPDATE public.sales_history AS sh
SET metal_category = public.classify_jewelry_metal_category(
  NULLIF(btrim(p.metal), ''),
  NULLIF(btrim(p.metal_type), '')
)
FROM public.products AS p
WHERE p.id = sh.product_id
  AND sh.legacy_id LIKE 'pwa_id_%'
  AND sh.price_krw > 0
  AND COALESCE(sh.migration_meta ->> 'type', '') IS DISTINCT FROM 'return'
  AND sh.legacy_id NOT LIKE 'return_%';

COMMIT;