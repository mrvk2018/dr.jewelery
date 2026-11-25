-- 074: возврат на витрину — manual_return_lock, POS-RPC, защита от перезаписи sync.
BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Флаг ручного возврата (sync не должен откатывать active/stock)
-- ---------------------------------------------------------------------------
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS manual_return_lock boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.products.manual_return_lock IS
  'true после ручного/POS-возврата: cron sync сохраняет active/stock до следующей продажи.';

-- product_status (витрина / telegram); если колонки ещё нет — создаём.
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS product_status text;

UPDATE public.products AS p
SET product_status = p.status
WHERE p.product_status IS NULL;

-- ---------------------------------------------------------------------------
-- 2) Сброс lock при продаже / резерве
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_products_clear_manual_return_lock()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IN ('sold', 'reserved') THEN
    NEW.manual_return_lock := false;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_clear_manual_return_lock ON public.products;
CREATE TRIGGER trg_products_clear_manual_return_lock
  BEFORE INSERT OR UPDATE ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_products_clear_manual_return_lock();

-- ---------------------------------------------------------------------------
-- 3) POS-возврат по product_id (История продаж)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.process_pos_product_return(
  p_product_id text,
  p_reason text DEFAULT NULL,
  p_admin_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pid            text;
  v_product        record;
  v_sale           record;
  v_return_legacy  text;
  v_reversal_id    uuid;
  v_sold_kst       date;
  v_sold_utc       timestamptz;
  v_commission_krw integer;
  v_list_neg       bigint;
  v_net_neg        bigint;
BEGIN
  v_pid := NULLIF(btrim(p_product_id), '');
  IF v_pid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'empty_product_id');
  END IF;

  SELECT *
  INTO v_product
  FROM public.products AS p
  WHERE p.id::text = v_pid
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'product_not_found');
  END IF;

  SELECT sh.*
  INTO v_sale
  FROM public.sales_history AS sh
  WHERE sh.product_id = v_product.id::text
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
    RETURN jsonb_build_object('ok', false, 'error', 'no_active_sale_found');
  END IF;

  v_return_legacy := 'return_' || v_sale.legacy_id;

  IF EXISTS (
    SELECT 1 FROM public.sales_history WHERE legacy_id = v_return_legacy
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_returned');
  END IF;

  v_sold_utc := now();
  v_sold_kst := (now() AT TIME ZONE 'Asia/Seoul')::date;

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

  v_list_neg := (-1) * abs(
    COALESCE(v_sale.list_price_krw, v_sale.price_krw)::bigint
  );
  v_net_neg := (-1) * abs(
    COALESCE(v_sale.net_cash_delta_krw, v_sale.price_krw)::bigint
  );

  INSERT INTO public.sales_history (
    legacy_id,
    sku,
    product_id,
    price_krw,
    list_price_krw,
    discount_percent,
    payment_method,
    store_location,
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
    commission_krw,
    sale_batch_id,
    scrap_trade_in_krw,
    net_cash_delta_krw
  )
  VALUES (
    v_return_legacy,
    v_sale.sku,
    v_sale.product_id,
    (-1) * abs(v_sale.price_krw::bigint),
    v_list_neg,
    COALESCE(v_sale.discount_percent, 0),
    v_sale.payment_method,
    v_sale.store_location,
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
      'processed_by', 'process_pos_product_return',
      'return_reason', NULLIF(btrim(p_reason), ''),
      'returned_by', NULLIF(btrim(p_admin_name), ''),
      'returned_at_utc', v_sold_utc,
      'original_sold_date_kst', v_sale.sold_date_kst::text
    ),
    v_sale.seller_code,
    v_sale.seller_name,
    v_sale.metal_category,
    COALESCE(v_sale.commission_percent, 0),
    v_commission_krw,
    v_sale.sale_batch_id,
    0,
    v_net_neg
  )
  RETURNING id INTO v_reversal_id;

  UPDATE public.products
  SET
    status = 'active',
    product_status = 'active',
    stock_quantity = 1,
    manual_return_lock = true,
    updated_at = now()
  WHERE id = v_product.id;

  RETURN jsonb_build_object(
    'ok', true,
    'product_id', v_product.id::text,
    'sku', v_product.sku,
    'reversal_id', v_reversal_id::text,
    'reversal_legacy_id', v_return_legacy,
    'price_krw', (-1) * abs(v_sale.price_krw::bigint),
    'sold_date_kst', v_sold_kst::text,
    'reverses_legacy_id', v_sale.legacy_id,
    'commission_krw', v_commission_krw
  );
END;
$$;

REVOKE ALL ON FUNCTION public.process_pos_product_return(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_pos_product_return(text, text, text)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) process_product_return_manual — SKU-дубли, product_status, lock
-- PostgREST: DEFAULT на p_admin_email даёт две RPC-сигнатуры (text) и (text,text)
-- → неоднозначность, если клиент шлёт оба параметра. Снимаем DEFAULT и дропаем старые overload.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.process_product_return_manual(text, text, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.process_product_return_manual(text);
DROP FUNCTION IF EXISTS public.process_product_return_manual(text, text);

CREATE OR REPLACE FUNCTION public.process_product_return_manual(
  p_sku text,
  p_admin_email text
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
  ORDER BY (p.status = 'sold') DESC, p.updated_at DESC
  LIMIT 1
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
    product_status = 'active',
    stock_quantity = 1,
    manual_return_lock = true,
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

REVOKE ALL ON FUNCTION public.process_product_return_manual(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_product_return_manual(text, text)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;