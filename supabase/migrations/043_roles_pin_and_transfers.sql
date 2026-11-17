-- Dr. Jewelry — 043: PIN/пароль продавцов, in_transfer, product_transfers DDL/RPC, партия черновиков ANS, трансфер лома.
-- Совместимость: Android-терминал (initiate/complete_product_transfer по QR), telegram-logger на product_transfers.

BEGIN;

-- ============================================================================
-- 1. Авторизация продавцов (sellers: login_password, pin_code)
-- ============================================================================

ALTER TABLE public.sellers
  ADD COLUMN IF NOT EXISTS login_password text;

ALTER TABLE public.sellers
  ADD COLUMN IF NOT EXISTS pin_code text;

COMMENT ON COLUMN public.sellers.login_password IS
  'Первичный пароль, задаётся админом (upsert_seller_by_admin). Не отдаётся клиенту.';
COMMENT ON COLUMN public.sellers.pin_code IS
  'Персональный PIN (4 цифры) после первого входа; NULL — PIN ещё не задан.';

DROP FUNCTION IF EXISTS public.upsert_seller_by_admin(text, text, boolean);
DROP FUNCTION IF EXISTS public.upsert_seller_by_admin(text, text, boolean, numeric, numeric);
DROP FUNCTION IF EXISTS public.upsert_seller_by_admin(
  text, text, boolean, numeric, numeric, numeric, numeric, numeric, numeric
);
DROP FUNCTION IF EXISTS public.upsert_seller_by_admin(
  text, text, boolean, numeric, numeric, numeric, numeric, numeric, numeric, text, boolean
);

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
  v_code varchar(50);
  v_name varchar(255);
  v_gold numeric(5, 2);
  v_silver numeric(5, 2);
  v_app_gold numeric(5, 2);
  v_app_silver numeric(5, 2);
  v_app_gold_disc numeric(5, 2);
  v_app_silver_disc numeric(5, 2);
  v_pwd text;
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

  v_pwd := NULLIF(btrim(coalesce(p_login_password, '')), '');

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
    coalesce(p_is_active, true),
    v_gold,
    v_silver,
    v_app_gold,
    v_app_silver,
    v_app_gold_disc,
    v_app_silver_disc,
    v_pwd,
    CASE WHEN coalesce(p_reset_pin, false) THEN NULL ELSE NULL END
  )
  ON CONFLICT (promo_code) DO UPDATE SET
    name = EXCLUDED.name,
    is_active = EXCLUDED.is_active,
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
      WHEN coalesce(p_reset_pin, false) THEN NULL
      ELSE public.sellers.pin_code
    END;

  RETURN true;
END;
$$;

DROP FUNCTION IF EXISTS public.get_active_sellers_for_login();
DROP FUNCTION IF EXISTS public.seller_login_or_setup_pin(text, text, text);

CREATE OR REPLACE FUNCTION public.get_active_sellers_for_login()
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT jsonb_build_object(
    'promo_code', s.promo_code,
    'name', s.name,
    'has_pin', (s.pin_code IS NOT NULL AND btrim(s.pin_code) <> '')
  )
  FROM public.sellers AS s
  WHERE s.is_active = true
  ORDER BY s.name, s.promo_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.seller_login_or_setup_pin(
  p_promo_code text,
  p_password text DEFAULT NULL,
  p_pin text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text := upper(btrim(coalesce(p_promo_code, '')));
  v_pwd text := NULLIF(btrim(coalesce(p_password, '')), '');
  v_pin text := NULLIF(btrim(coalesce(p_pin, '')), '');
  v_row public.sellers%ROWTYPE;
  v_has_pin boolean;
BEGIN
  IF v_code = '' THEN
    RAISE EXCEPTION 'invalid_promo_code'
      USING ERRCODE = '28000',
            MESSAGE = 'Укажите код продавца';
  END IF;

  SELECT * INTO v_row
  FROM public.sellers AS s
  WHERE s.promo_code = v_code;

  IF NOT FOUND OR NOT coalesce(v_row.is_active, false) THEN
    RAISE EXCEPTION 'seller_inactive'
      USING ERRCODE = '28000',
            MESSAGE = 'Продавец не найден или деактивирован';
  END IF;

  v_has_pin := v_row.pin_code IS NOT NULL AND btrim(v_row.pin_code) <> '';

  IF NOT v_has_pin THEN
    IF v_pwd IS NULL OR v_row.login_password IS DISTINCT FROM v_pwd THEN
      RAISE EXCEPTION 'invalid_password'
        USING ERRCODE = '28000',
              MESSAGE = 'Неверный пароль для первичного входа';
    END IF;
    IF v_pin IS NULL OR v_pin !~ '^\d{4}$' THEN
      RAISE EXCEPTION 'invalid_pin'
        USING ERRCODE = '22023',
              MESSAGE = 'PIN должен состоять ровно из 4 цифр';
    END IF;
    UPDATE public.sellers AS s
    SET pin_code = v_pin
    WHERE s.promo_code = v_code;
    RETURN jsonb_build_object(
      'ok', true,
      'promo_code', v_code,
      'name', v_row.name,
      'pin_setup', true
    );
  END IF;

  IF v_pwd IS NOT NULL
     AND v_row.login_password IS NOT DISTINCT FROM v_pwd
     AND v_pin IS NOT NULL
     AND v_pin ~ '^\d{4}$' THEN
    UPDATE public.sellers AS s
    SET pin_code = v_pin
    WHERE s.promo_code = v_code;
    RETURN jsonb_build_object(
      'ok', true,
      'promo_code', v_code,
      'name', v_row.name,
      'pin_reset', true
    );
  END IF;

  IF v_pin IS NULL OR v_row.pin_code IS DISTINCT FROM v_pin THEN
    RAISE EXCEPTION 'invalid_pin'
      USING ERRCODE = '28000',
            MESSAGE = 'Неверный PIN';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'promo_code', v_code,
    'name', v_row.name
  );
END;
$$;

-- ============================================================================
-- 2. products.status in_transfer, product_transfers, продажа/списание, трансферы
-- ============================================================================

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_status_check;
ALTER TABLE public.products
  ADD CONSTRAINT products_status_check
  CHECK (status IN ('active', 'reserved', 'sold', 'hidden', 'in_transfer'));

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS is_customer_order boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.products.is_customer_order IS
  'Заказ под клиента: при приёмке трансфера касса показывает alert.';

CREATE TABLE IF NOT EXISTS public.product_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id text,
  sku text,
  qr_code_payload text,
  from_store text,
  to_store text,
  status text NOT NULL DEFAULT 'in_transit',
  sender_code text,
  receiver_code text,
  weight_grams numeric,
  metal_type text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.product_transfers
  ADD COLUMN IF NOT EXISTS product_id text;

ALTER TABLE public.product_transfers
  ADD COLUMN IF NOT EXISTS sku text;

ALTER TABLE public.product_transfers
  ADD COLUMN IF NOT EXISTS qr_code_payload text;

ALTER TABLE public.product_transfers
  ADD COLUMN IF NOT EXISTS from_store text;

ALTER TABLE public.product_transfers
  ADD COLUMN IF NOT EXISTS to_store text;

ALTER TABLE public.product_transfers
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'in_transit';

ALTER TABLE public.product_transfers
  ADD COLUMN IF NOT EXISTS sender_code text;

ALTER TABLE public.product_transfers
  ADD COLUMN IF NOT EXISTS receiver_code text;

ALTER TABLE public.product_transfers
  ADD COLUMN IF NOT EXISTS weight_grams numeric;

ALTER TABLE public.product_transfers
  ADD COLUMN IF NOT EXISTS metal_type text;

ALTER TABLE public.product_transfers
  ADD COLUMN IF NOT EXISTS notes text;

ALTER TABLE public.product_transfers
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

ALTER TABLE public.product_transfers
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_product_transfers_to_store_status
  ON public.product_transfers (to_store, status);

CREATE INDEX IF NOT EXISTS idx_product_transfers_product_id
  ON public.product_transfers (product_id);

CREATE INDEX IF NOT EXISTS idx_product_transfers_qr_code_payload
  ON public.product_transfers (qr_code_payload);

CREATE OR REPLACE FUNCTION public.product_transfers_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_product_transfers_updated_at ON public.product_transfers;
CREATE TRIGGER trg_product_transfers_updated_at
  BEFORE UPDATE ON public.product_transfers
  FOR EACH ROW
  EXECUTE FUNCTION public.product_transfers_touch_updated_at();

ALTER TABLE public.product_transfers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS product_transfers_select_anon ON public.product_transfers;
CREATE POLICY product_transfers_select_anon
  ON public.product_transfers
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- Смена RETURNS (42P13): снять старые сигнатуры перед CREATE.
DROP FUNCTION IF EXISTS public._norm_store_icn_ans(text);
DROP FUNCTION IF EXISTS public._transfer_status_is_open(text);
DROP FUNCTION IF EXISTS public.mark_product_sold_manual(text, text);
DROP FUNCTION IF EXISTS public.write_off_product_by_id(text, text);
DROP FUNCTION IF EXISTS public.create_product_transfer_by_id(text, text, text, text);
DROP FUNCTION IF EXISTS public.complete_product_transfer_by_id(uuid, text);
DROP FUNCTION IF EXISTS public.cancel_product_transfer_by_id(uuid, text);
DROP FUNCTION IF EXISTS public.list_product_transfers(text, text);
DROP FUNCTION IF EXISTS public.initiate_product_transfer(text, text, text);
DROP FUNCTION IF EXISTS public.complete_product_transfer(text, text);
DROP FUNCTION IF EXISTS public.send_drafts_batch_to_ansan(text);
DROP FUNCTION IF EXISTS public.search_draft_products(text);
DROP FUNCTION IF EXISTS public.activate_draft_product_by_id(text, text, text, text);
DROP FUNCTION IF EXISTS public.activate_draft_products_by_ids(jsonb, text);
DROP FUNCTION IF EXISTS public.initiate_scrap_transfer(uuid, text, text);
DROP FUNCTION IF EXISTS public.complete_scrap_transfer(uuid, text);
DROP FUNCTION IF EXISTS public.cancel_scrap_transfer(uuid);

CREATE OR REPLACE FUNCTION public._norm_store_icn_ans(p_store text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v text := upper(btrim(coalesce(p_store, '')));
BEGIN
  IF v IN ('ANS', 'ANSAN', 'АНСАН') THEN
    RETURN 'ANS';
  ELSIF v IN ('ICN', 'INCHEON', 'ИНЧХОН') THEN
    RETURN 'ICN';
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._transfer_status_is_open(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(btrim(coalesce(p_status, ''))) IN (
    'in_transit', 'pending', 'sent', 'в пути'
  )
  OR btrim(coalesce(p_status, '')) = 'В пути';
$$;

CREATE OR REPLACE FUNCTION public.mark_product_sold_manual(
  p_product_id text,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
BEGIN
  IF p_product_id IS NULL OR btrim(p_product_id) = '' THEN
    RETURN false;
  END IF;

  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN false;
  END IF;

  SELECT p.status
  INTO v_status
  FROM public.products AS p
  WHERE p.id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_status = 'in_transfer' THEN
    RETURN false;
  END IF;

  IF v_status NOT IN ('active', 'reserved', 'hidden') THEN
    RETURN false;
  END IF;

  UPDATE public.products
  SET
    status = 'sold',
    stock_quantity = 0,
    updated_at = now()
  WHERE id = p_product_id;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.write_off_product_by_id(
  p_product_id text,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
BEGIN
  IF p_product_id IS NULL OR btrim(p_product_id) = '' THEN
    RETURN false;
  END IF;

  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN false;
  END IF;

  SELECT p.status
  INTO v_status
  FROM public.products AS p
  WHERE p.id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_status = 'in_transfer' THEN
    RETURN false;
  END IF;

  UPDATE public.products
  SET
    stock_quantity = 0,
    updated_at = now()
  WHERE id = p_product_id;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_product_transfer_by_id(
  p_product_id text,
  p_to_store text,
  p_sender_code text,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pid text := NULLIF(btrim(coalesce(p_product_id, '')), '');
  v_to text := public._norm_store_icn_ans(p_to_store);
  v_sender text := upper(btrim(coalesce(p_sender_code, '')));
  v_row public.products%ROWTYPE;
  v_transfer_id uuid;
  v_from text;
  v_open boolean;
BEGIN
  IF v_pid IS NULL OR v_to IS NULL OR v_sender = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите product_id, магазин (ICN/ANS) и код отправителя');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.sellers AS s
    WHERE s.promo_code = v_sender AND s.is_active = true
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Код отправителя не активен');
  END IF;

  SELECT * INTO v_row
  FROM public.products AS p
  WHERE p.id = v_pid
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Товар не найден');
  END IF;

  IF v_row.status <> 'active' OR coalesce(v_row.stock_quantity, 0) <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Товар недоступен для отправки (нужен active и stock > 0)');
  END IF;

  v_from := public._norm_store_icn_ans(v_row.store_location);
  IF v_from IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'У товара не задан магазин (from_store)');
  END IF;

  IF v_from = v_to THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Маршрут: отправка в тот же магазин');
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.product_transfers AS t
    WHERE t.product_id = v_pid
      AND public._transfer_status_is_open(t.status)
  ) INTO v_open;

  IF v_open THEN
    RETURN jsonb_build_object('ok', false, 'error', 'У товара уже есть незавершённый трансфер');
  END IF;

  UPDATE public.products
  SET
    status = 'in_transfer',
    updated_at = now()
  WHERE id = v_pid;

  INSERT INTO public.product_transfers (
    product_id,
    sku,
    qr_code_payload,
    from_store,
    to_store,
    status,
    sender_code,
    weight_grams,
    metal_type,
    notes
  )
  VALUES (
    v_row.id,
    v_row.sku,
    v_row.qr_code_payload,
    v_from,
    v_to,
    'in_transit',
    v_sender,
    v_row.weight_grams,
    coalesce(v_row.metal_type, v_row.metal),
    NULLIF(btrim(coalesce(p_notes, '')), '')
  )
  RETURNING id INTO v_transfer_id;

  RETURN jsonb_build_object(
    'ok', true,
    'transfer_id', v_transfer_id,
    'product_id', v_row.id,
    'sku', v_row.sku,
    'from_store', v_from,
    'to_store', v_to
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_product_transfer_by_id(
  p_transfer_id uuid,
  p_receiver_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_receiver text := upper(btrim(coalesce(p_receiver_code, '')));
  v_t public.product_transfers%ROWTYPE;
  v_alert text;
  v_customer boolean;
BEGIN
  IF p_transfer_id IS NULL OR v_receiver = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите transfer_id и код приёмщика');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.sellers AS s
    WHERE s.promo_code = v_receiver AND s.is_active = true
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Код приёмщика не активен');
  END IF;

  SELECT * INTO v_t
  FROM public.product_transfers AS t
  WHERE t.id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Трансфер не найден');
  END IF;

  IF NOT public._transfer_status_is_open(v_t.status) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Трансфер уже завершён или отменён');
  END IF;

  UPDATE public.product_transfers
  SET
    status = 'completed',
    receiver_code = v_receiver,
    updated_at = now()
  WHERE id = p_transfer_id;

  UPDATE public.products AS p
  SET
    status = 'active',
    store_location = v_t.to_store,
    updated_at = now()
  WHERE p.id = v_t.product_id
    AND p.status = 'in_transfer';

  SELECT coalesce(p.is_customer_order, false)
  INTO v_customer
  FROM public.products AS p
  WHERE p.id = v_t.product_id;

  IF v_customer THEN
    v_alert := 'Заказ покупателя — отложить на спец-полку для выдачи';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'transfer_id', p_transfer_id,
    'sku', v_t.sku,
    'to_store', v_t.to_store,
    'alert', v_alert
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_product_transfer_by_id(
  p_transfer_id uuid,
  p_actor_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor text := upper(btrim(coalesce(p_actor_code, '')));
  v_t public.product_transfers%ROWTYPE;
BEGIN
  IF p_transfer_id IS NULL OR v_actor = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите transfer_id и код сотрудника');
  END IF;

  SELECT * INTO v_t
  FROM public.product_transfers AS t
  WHERE t.id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Трансфер не найден');
  END IF;

  IF NOT public._transfer_status_is_open(v_t.status) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Трансфер уже завершён или отменён');
  END IF;

  UPDATE public.product_transfers
  SET
    status = 'cancelled',
    updated_at = now()
  WHERE id = p_transfer_id;

  UPDATE public.products AS p
  SET
    status = 'active',
    store_location = coalesce(v_t.from_store, p.store_location),
    updated_at = now()
  WHERE p.id = v_t.product_id
    AND p.status = 'in_transfer';

  RETURN jsonb_build_object('ok', true, 'transfer_id', p_transfer_id, 'sku', v_t.sku);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_product_transfers(
  p_status text DEFAULT NULL,
  p_store text DEFAULT NULL
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text := NULLIF(lower(btrim(coalesce(p_status, ''))), '');
  v_store text := public._norm_store_icn_ans(p_store);
BEGIN
  RETURN QUERY
  SELECT to_jsonb(t.*)
  FROM public.product_transfers AS t
  WHERE (v_status IS NULL OR lower(t.status) = v_status OR t.status = p_status)
    AND (
      v_store IS NULL
      OR t.to_store = v_store
      OR t.from_store = v_store
    )
  ORDER BY t.created_at DESC NULLS LAST, t.id DESC;
END;
$$;

-- Android-терминал: обратная совместимость по QR (имена параметров как в Flutter SellerPosRpc).
DROP FUNCTION IF EXISTS public.initiate_product_transfer(text, text, text);
CREATE OR REPLACE FUNCTION public.initiate_product_transfer(
  target_qr text,
  s_code text,
  to_loc text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_qr text := NULLIF(btrim(coalesce(target_qr, '')), '');
  v_sender text := upper(btrim(coalesce(s_code, '')));
  v_to text := public._norm_store_icn_ans(to_loc);
  v_product_id text;
BEGIN
  IF v_qr IS NULL OR v_sender = '' OR v_to IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Некорректные параметры трансфера');
  END IF;

  SELECT p.id INTO v_product_id
  FROM public.products AS p
  WHERE p.qr_code_payload = v_qr
  LIMIT 1;

  IF v_product_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Товар не найден по QR');
  END IF;

  RETURN public.create_product_transfer_by_id(v_product_id, v_to, v_sender, NULL);
END;
$$;

DROP FUNCTION IF EXISTS public.complete_product_transfer(text, text);
CREATE OR REPLACE FUNCTION public.complete_product_transfer(
  target_qr text,
  r_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_qr text := NULLIF(btrim(coalesce(target_qr, '')), '');
  v_receiver text := upper(btrim(coalesce(r_code, '')));
  v_transfer_id uuid;
BEGIN
  IF v_qr IS NULL OR v_receiver = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Некорректные параметры приёмки');
  END IF;

  SELECT t.id INTO v_transfer_id
  FROM public.product_transfers AS t
  WHERE public._transfer_status_is_open(t.status)
    AND (
      t.qr_code_payload = v_qr
      OR t.sku = v_qr
      OR t.product_id IN (
        SELECT p.id FROM public.products AS p WHERE p.qr_code_payload = v_qr
      )
    )
  ORDER BY t.created_at DESC
  LIMIT 1;

  IF v_transfer_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Входящий трансфер не найден');
  END IF;

  RETURN public.complete_product_transfer_by_id(v_transfer_id, v_receiver);
END;
$$;

-- ============================================================================
-- 3. Партия черновиков в Ансан, поиск/активация in_transfer
-- ============================================================================

CREATE OR REPLACE FUNCTION public.send_drafts_batch_to_ansan(p_actor_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor text := upper(btrim(coalesce(p_actor_code, '')));
  v_count integer;
BEGIN
  IF v_actor = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите код сотрудника');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.sellers AS s WHERE s.promo_code = v_actor AND s.is_active = true
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Код сотрудника не активен');
  END IF;

  WITH updated AS (
    UPDATE public.products AS p
    SET
      status = 'in_transfer',
      updated_at = now()
    WHERE p.stock_quantity = 0
      AND p.status IN ('hidden', 'active')
      AND p.store_location = 'ANS'
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_count FROM updated;

  RETURN jsonb_build_object('ok', true, 'sent_count', coalesce(v_count, 0));
END;
$$;

CREATE OR REPLACE FUNCTION public.search_draft_products(search_query text DEFAULT '')
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  q text := btrim(COALESCE(search_query, ''));
  w numeric;
  w_raw text;
BEGIN
  w_raw := NULLIF(regexp_replace(q, '[^0-9.,]', '', 'g'), '');
  IF w_raw IS NOT NULL THEN
    BEGIN
      w := replace(w_raw, ',', '.')::numeric;
    EXCEPTION
      WHEN others THEN
        w := NULL;
    END;
  END IF;

  RETURN QUERY
  SELECT to_jsonb(p.*)
  FROM public.products AS p
  WHERE p.stock_quantity = 0
    AND p.status IN ('hidden', 'active', 'in_transfer')
    AND (
      q = ''
      OR p.sku ILIKE '%' || q || '%'
      OR COALESCE(p.metal_type, p.metal, '') ILIKE '%' || q || '%'
      OR COALESCE(p.gem_inserts, p."insert", '') ILIKE '%' || q || '%'
      OR COALESCE(p.notes, '') ILIKE '%' || q || '%'
      OR (w IS NOT NULL AND p.weight_grams IS NOT NULL AND p.weight_grams = w)
    )
  ORDER BY p.updated_at DESC NULLS LAST, p.sku
  LIMIT 500;
END;
$$;

CREATE OR REPLACE FUNCTION public.activate_draft_product_by_id(
  p_id text,
  p_notes text DEFAULT NULL,
  p_store_location text DEFAULT NULL,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id text := NULLIF(btrim(COALESCE(p_id, '')), '');
  v_row public.products%ROWTYPE;
  v_loc text;
  v_store_in text;
  v_notes text;
BEGIN
  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Нет прав администратора');
  END IF;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите id черновика');
  END IF;

  SELECT * INTO v_row
  FROM public.products AS p
  WHERE p.id = v_id
    AND p.stock_quantity = 0
    AND p.status IN ('hidden', 'active', 'in_transfer');

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Черновик не найден или уже активирован'
    );
  END IF;

  v_store_in := NULLIF(btrim(COALESCE(p_store_location, '')), '');
  IF v_store_in IS NULL OR upper(v_store_in) IN ('', 'UNSELECTED', 'NONE', 'NULL') THEN
    v_loc := v_row.store_location;
  ELSIF upper(v_store_in) IN ('ANS', 'ANSAN', 'АНСАН') THEN
    v_loc := 'ANS';
  ELSIF upper(v_store_in) IN ('ICN', 'INCHEON', 'ИНЧХОН') THEN
    v_loc := 'ICN';
  ELSE
    RETURN jsonb_build_object('ok', false, 'error', 'Недопустимый магазин. Укажите ICN или ANS');
  END IF;

  IF v_loc IS NULL OR v_loc NOT IN ('ICN', 'ANS') THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Перед приёмкой укажите магазин (Инчхон или Ансан)'
    );
  END IF;

  v_notes := NULLIF(btrim(COALESCE(p_notes, '')), '');

  UPDATE public.products AS p
  SET
    status = 'active',
    stock_quantity = 1,
    store_location = v_loc,
    notes = COALESCE(v_notes, p.notes),
    updated_at = now()
  WHERE p.id = v_id
    AND p.stock_quantity = 0
    AND p.status IN ('hidden', 'active', 'in_transfer');

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Не удалось активировать черновик');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'id', v_id,
    'sku', v_row.sku,
    'store_location', v_loc
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.activate_draft_products_by_ids(
  p_ids jsonb,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id text;
  v_activated integer := 0;
  v_skipped integer := 0;
BEGIN
  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Нет прав администратора');
  END IF;

  IF p_ids IS NULL OR jsonb_typeof(p_ids) <> 'array' OR jsonb_array_length(p_ids) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите массив id черновиков');
  END IF;

  FOR v_id IN
    SELECT NULLIF(btrim(elem), '')
    FROM jsonb_array_elements_text(p_ids) AS elem
  LOOP
    CONTINUE WHEN v_id IS NULL;

    UPDATE public.products AS p
    SET
      status = 'active',
      stock_quantity = 1,
      updated_at = now()
    WHERE p.id = v_id
      AND p.stock_quantity = 0
      AND p.status IN ('hidden', 'active', 'in_transfer')
      AND p.store_location IN ('ICN', 'ANS');

    IF FOUND THEN
      v_activated := v_activated + 1;
    ELSE
      v_skipped := v_skipped + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'activated', v_activated,
    'skipped', v_skipped
  );
END;
$$;

-- ============================================================================
-- 4. Трансфер лома (scrap_metal_intakes)
-- ============================================================================

ALTER TABLE public.scrap_metal_intakes DROP CONSTRAINT IF EXISTS scrap_metal_intakes_status_check;
ALTER TABLE public.scrap_metal_intakes
  ADD CONSTRAINT scrap_metal_intakes_status_check
  CHECK (status IN ('in_stock', 'in_transfer', 'written_off'));

ALTER TABLE public.scrap_metal_intakes
  ADD COLUMN IF NOT EXISTS transfer_to_store text;

ALTER TABLE public.scrap_metal_intakes
  ADD COLUMN IF NOT EXISTS transferred_by_code text;

ALTER TABLE public.scrap_metal_intakes
  ADD COLUMN IF NOT EXISTS transferred_by_name text;

ALTER TABLE public.scrap_metal_intakes
  ADD COLUMN IF NOT EXISTS transferred_at timestamptz;

ALTER TABLE public.scrap_metal_intakes
  ADD COLUMN IF NOT EXISTS received_by_code text;

ALTER TABLE public.scrap_metal_intakes
  ADD COLUMN IF NOT EXISTS received_by_name text;

ALTER TABLE public.scrap_metal_intakes
  ADD COLUMN IF NOT EXISTS received_at timestamptz;

CREATE OR REPLACE FUNCTION public.initiate_scrap_transfer(
  p_intake_id uuid,
  p_to_store text,
  p_sender_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_to text := public._norm_store_icn_ans(p_to_store);
  v_sender text := upper(btrim(coalesce(p_sender_code, '')));
  v_name text;
  v_row public.scrap_metal_intakes%ROWTYPE;
BEGIN
  IF p_intake_id IS NULL OR v_to IS NULL OR v_sender = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Некорректные параметры');
  END IF;

  SELECT s.name INTO v_name
  FROM public.sellers AS s
  WHERE s.promo_code = v_sender AND s.is_active = true;

  IF v_name IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Код отправителя не активен');
  END IF;

  SELECT * INTO v_row
  FROM public.scrap_metal_intakes AS i
  WHERE i.id = p_intake_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Акт приёмки не найден');
  END IF;

  IF v_row.status <> 'in_stock' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Лом должен быть в статусе in_stock');
  END IF;

  IF public._norm_store_icn_ans(v_row.store_location) = v_to THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Нельзя отправить в тот же магазин');
  END IF;

  UPDATE public.scrap_metal_intakes
  SET
    status = 'in_transfer',
    transfer_to_store = v_to,
    transferred_by_code = v_sender,
    transferred_by_name = v_name,
    transferred_at = now(),
    updated_at = now()
  WHERE id = p_intake_id;

  RETURN jsonb_build_object('ok', true, 'id', p_intake_id, 'transfer_to_store', v_to);
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_scrap_transfer(
  p_intake_id uuid,
  p_receiver_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_receiver text := upper(btrim(coalesce(p_receiver_code, '')));
  v_name text;
  v_row public.scrap_metal_intakes%ROWTYPE;
  v_dest text;
BEGIN
  IF p_intake_id IS NULL OR v_receiver = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Некорректные параметры');
  END IF;

  SELECT s.name INTO v_name
  FROM public.sellers AS s
  WHERE s.promo_code = v_receiver AND s.is_active = true;

  IF v_name IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Код приёмщика не активен');
  END IF;

  SELECT * INTO v_row
  FROM public.scrap_metal_intakes AS i
  WHERE i.id = p_intake_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Акт приёмки не найден');
  END IF;

  IF v_row.status <> 'in_transfer' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Лом не в пути');
  END IF;

  v_dest := public._norm_store_icn_ans(v_row.transfer_to_store);
  IF v_dest IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Не задан магазин назначения');
  END IF;

  UPDATE public.scrap_metal_intakes
  SET
    status = 'in_stock',
    store_location = v_dest,
    transfer_to_store = NULL,
    received_by_code = v_receiver,
    received_by_name = v_name,
    received_at = now(),
    updated_at = now()
  WHERE id = p_intake_id;

  RETURN jsonb_build_object('ok', true, 'id', p_intake_id, 'store_location', v_dest);
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_scrap_transfer(p_intake_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.scrap_metal_intakes%ROWTYPE;
BEGIN
  IF p_intake_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите id акта');
  END IF;

  SELECT * INTO v_row
  FROM public.scrap_metal_intakes AS i
  WHERE i.id = p_intake_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Акт приёмки не найден');
  END IF;

  IF v_row.status <> 'in_transfer' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Отмена возможна только для in_transfer');
  END IF;

  UPDATE public.scrap_metal_intakes
  SET
    status = 'in_stock',
    transfer_to_store = NULL,
    updated_at = now()
  WHERE id = p_intake_id;

  RETURN jsonb_build_object('ok', true, 'id', p_intake_id);
END;
$$;

-- ============================================================================
-- GRANTS
-- ============================================================================

REVOKE ALL ON FUNCTION public.upsert_seller_by_admin(
  text, text, boolean, numeric, numeric, numeric, numeric, numeric, numeric, text, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_seller_by_admin(
  text, text, boolean, numeric, numeric, numeric, numeric, numeric, numeric, text, boolean
) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_active_sellers_for_login() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_sellers_for_login()
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.seller_login_or_setup_pin(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.seller_login_or_setup_pin(text, text, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.mark_product_sold_manual(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_product_sold_manual(text, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.write_off_product_by_id(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.write_off_product_by_id(text, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.create_product_transfer_by_id(text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_product_transfer_by_id(text, text, text, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.complete_product_transfer_by_id(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_product_transfer_by_id(uuid, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.cancel_product_transfer_by_id(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_product_transfer_by_id(uuid, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.list_product_transfers(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_product_transfers(text, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.initiate_product_transfer(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.initiate_product_transfer(text, text, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.complete_product_transfer(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_product_transfer(text, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.send_drafts_batch_to_ansan(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_drafts_batch_to_ansan(text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.search_draft_products(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_draft_products(text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.activate_draft_product_by_id(text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_draft_product_by_id(text, text, text, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.activate_draft_products_by_ids(jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_draft_products_by_ids(jsonb, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.initiate_scrap_transfer(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.initiate_scrap_transfer(uuid, text, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.complete_scrap_transfer(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_scrap_transfer(uuid, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.cancel_scrap_transfer(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_scrap_transfer(uuid)
  TO anon, authenticated, service_role;

COMMIT;