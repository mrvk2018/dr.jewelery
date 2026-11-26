-- 076: бронь по предоплате и залоговые платежи.
--
-- Касса смены в проекте не имеет отдельной таблицы. Деньги дня читает
-- get_sales_history_summary: sum(sales_history.price_krw > 0) − лом Trade-In.
-- Залог / доплата / возврат залога пишутся только в reservation_payments и
-- входят в shift_cash_krw / net_cash_krw. Строка sales_history создаётся
-- лишь при 100% выкупе (полная сумма сделки, стандартный возврат) и
-- помечается migration_meta.cash_via = 'reservation_payments', чтобы
-- касса не прибавила её второй раз к уже учтённым платежам.
--
-- products.id — text (DrJaw), не uuid. seller_id проекта — sellers.promo_code
-- (колонка seller_code). Статус reserved уже входит в products_status_check (043).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Статус reserved и сброс manual_return_lock
-- ---------------------------------------------------------------------------
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_status_check;
ALTER TABLE public.products
  ADD CONSTRAINT products_status_check
  CHECK (status IN ('active', 'reserved', 'sold', 'hidden', 'in_transfer'));

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

-- Витрина (anon/authenticated): только active. reserved покупателю не виден.
DROP POLICY IF EXISTS products_public_select ON public.products;
CREATE POLICY products_public_select
  ON public.products
  FOR SELECT
  TO anon, authenticated
  USING (status = 'active');

-- ---------------------------------------------------------------------------
-- 2) Таблицы брони, позиций, платежей
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.reservations (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_number    text,
  branch            text NOT NULL,
  seller_name       text,
  seller_code       text,
  customer_name     text NOT NULL,
  customer_phone    text NOT NULL,
  expires_at        timestamptz NOT NULL,
  comment           text,
  total_amount_krw  numeric(14, 0) NOT NULL,
  paid_deposit_krw  numeric(14, 0) NOT NULL DEFAULT 0,
  status            text NOT NULL DEFAULT 'active',
  sale_id           uuid,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.reservations DROP CONSTRAINT IF EXISTS reservations_branch_check;
ALTER TABLE public.reservations
  ADD CONSTRAINT reservations_branch_check
  CHECK (branch IN ('ICN', 'ANS'));

ALTER TABLE public.reservations DROP CONSTRAINT IF EXISTS reservations_status_check;
ALTER TABLE public.reservations
  ADD CONSTRAINT reservations_status_check
  CHECK (status IN ('active', 'completed', 'cancelled'));

ALTER TABLE public.reservations DROP CONSTRAINT IF EXISTS reservations_amounts_check;
ALTER TABLE public.reservations
  ADD CONSTRAINT reservations_amounts_check
  CHECK (
    total_amount_krw > 0
    AND paid_deposit_krw >= 0
    AND paid_deposit_krw <= total_amount_krw
  );

ALTER TABLE public.reservations DROP CONSTRAINT IF EXISTS reservations_sale_id_fkey;
ALTER TABLE public.reservations
  ADD CONSTRAINT reservations_sale_id_fkey
  FOREIGN KEY (sale_id) REFERENCES public.sales_history (id) ON DELETE SET NULL;

COMMENT ON TABLE public.reservations IS
  'Бронь изделий под предоплату. Просрочка: status = active AND expires_at < now().';
COMMENT ON COLUMN public.reservations.seller_code IS
  'Идентификатор продавца проекта: sellers.promo_code.';
COMMENT ON COLUMN public.reservations.receipt_number IS
  'Задел под номер квитанции брони. Пока nullable.';
COMMENT ON COLUMN public.reservations.sale_id IS
  'Первая строка sales_history после 100% выкупа (остальные — тот же sale_batch_id rsv_<id>).';

CREATE TABLE IF NOT EXISTS public.reservation_items (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id    uuid NOT NULL REFERENCES public.reservations (id) ON DELETE CASCADE,
  product_id        text NOT NULL REFERENCES public.products (id) ON DELETE RESTRICT,
  sku               text NOT NULL,
  title             text,
  category          text,
  weight_g          numeric(12, 4),
  purity            text,
  size              text,
  list_price_krw    numeric(14, 0) NOT NULL DEFAULT 0,
  agreed_price_krw  numeric(14, 0) NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reservation_items_agreed_positive CHECK (agreed_price_krw > 0)
);

CREATE TABLE IF NOT EXISTS public.reservation_payments (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id   uuid NOT NULL REFERENCES public.reservations (id) ON DELETE CASCADE,
  receipt_number   text,
  payment_type     text NOT NULL,
  amount_krw       numeric(14, 0) NOT NULL,
  payment_method   text NOT NULL,
  branch           text NOT NULL,
  seller_name      text,
  seller_code      text,
  created_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.reservation_payments DROP CONSTRAINT IF EXISTS reservation_payments_type_check;
ALTER TABLE public.reservation_payments
  ADD CONSTRAINT reservation_payments_type_check
  CHECK (payment_type IN ('deposit', 'topup', 'buyout', 'refund'));

ALTER TABLE public.reservation_payments DROP CONSTRAINT IF EXISTS reservation_payments_method_check;
ALTER TABLE public.reservation_payments
  ADD CONSTRAINT reservation_payments_method_check
  CHECK (payment_method IN ('cash', 'card', 'transfer'));

ALTER TABLE public.reservation_payments DROP CONSTRAINT IF EXISTS reservation_payments_branch_check;
ALTER TABLE public.reservation_payments
  ADD CONSTRAINT reservation_payments_branch_check
  CHECK (branch IN ('ICN', 'ANS'));

ALTER TABLE public.reservation_payments DROP CONSTRAINT IF EXISTS reservation_payments_amount_sign_check;
ALTER TABLE public.reservation_payments
  ADD CONSTRAINT reservation_payments_amount_sign_check
  CHECK (
    (payment_type = 'refund' AND amount_krw < 0)
    OR (payment_type IN ('deposit', 'topup', 'buyout') AND amount_krw > 0)
  );

COMMENT ON TABLE public.reservation_payments IS
  'Журнал кассы по брони. Плюс — приход залога/доплаты, минус — refund. В sales_history не дублируется.';
COMMENT ON COLUMN public.reservation_payments.receipt_number IS
  'Задел под номер квитанции конкретного платежа.';

CREATE UNIQUE INDEX IF NOT EXISTS reservation_items_reservation_product_uidx
  ON public.reservation_items (reservation_id, product_id);

CREATE INDEX IF NOT EXISTS idx_reservations_status_expires
  ON public.reservations (status, expires_at);

CREATE INDEX IF NOT EXISTS idx_reservations_branch
  ON public.reservations (branch);

CREATE INDEX IF NOT EXISTS idx_reservations_customer_phone
  ON public.reservations (customer_phone);

CREATE INDEX IF NOT EXISTS idx_reservation_items_product
  ON public.reservation_items (product_id);

CREATE INDEX IF NOT EXISTS idx_reservation_payments_reservation
  ON public.reservation_payments (reservation_id);

CREATE INDEX IF NOT EXISTS idx_reservation_payments_branch_created
  ON public.reservation_payments (branch, created_at DESC);

CREATE OR REPLACE FUNCTION public.trg_reservations_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reservations_touch_updated_at ON public.reservations;
CREATE TRIGGER trg_reservations_touch_updated_at
  BEFORE UPDATE ON public.reservations
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_reservations_touch_updated_at();

ALTER TABLE public.reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reservation_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reservation_payments ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.reservations FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.reservation_items FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.reservation_payments FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.reservations TO service_role;
GRANT ALL ON TABLE public.reservation_items TO service_role;
GRANT ALL ON TABLE public.reservation_payments TO service_role;

-- ---------------------------------------------------------------------------
-- 3) Хелперы
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._reservation_krw(p_amount numeric)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_amount IS NULL THEN NULL
    ELSE round(p_amount)::bigint
  END;
$$;

CREATE OR REPLACE FUNCTION public._reservation_resolve_seller(
  p_seller_name text,
  p_seller_code text DEFAULT NULL
)
RETURNS TABLE (
  seller_code text,
  seller_name text,
  gold_commission_percent numeric,
  silver_commission_percent numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seller text := NULLIF(btrim(COALESCE(p_seller_name, '')), '');
  v_code   text := NULLIF(upper(btrim(COALESCE(p_seller_code, ''))), '');
  v_row    public.sellers%ROWTYPE;
BEGIN
  IF v_code IS NOT NULL THEN
    SELECT * INTO v_row
    FROM public.sellers AS s
    WHERE s.promo_code = v_code
      AND s.is_active;
    IF NOT FOUND THEN
      RETURN;
    END IF;
    seller_code := v_row.promo_code::text;
    seller_name := CASE
      WHEN v_row.promo_code = 'ADMIN' AND v_seller IS NOT NULL THEN v_seller
      ELSE v_row.name::text
    END;
    gold_commission_percent := v_row.gold_commission_percent;
    silver_commission_percent := v_row.silver_commission_percent;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_seller IS NULL THEN
    RETURN;
  END IF;

  SELECT r.promo_code, r.name, r.gold_commission_percent, r.silver_commission_percent
  INTO seller_code, seller_name, gold_commission_percent, silver_commission_percent
  FROM public.resolve_seller_by_name(v_seller) AS r
  LIMIT 1;

  IF seller_code IS NULL THEN
    RETURN;
  END IF;
  IF seller_code = 'ADMIN' THEN
    seller_name := v_seller;
  END IF;
  RETURN NEXT;
END;
$$;

-- 100% выкуп: products reserved → sold, sales_history на согласованные цены.
-- Касса этой суммой не пополняется (cash_via = reservation_payments).
CREATE OR REPLACE FUNCTION public._reservation_complete(
  p_reservation_id uuid,
  p_payment_method text,
  p_branch text,
  p_seller_code text,
  p_seller_name text,
  p_gold numeric,
  p_silver numeric
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res        public.reservations%ROWTYPE;
  v_item       public.reservation_items%ROWTYPE;
  v_prod       public.products%ROWTYPE;
  v_hist       uuid;
  v_first      uuid;
  v_batch      text;
  v_list       bigint;
  v_agreed     bigint;
  v_discount   integer;
  v_metal      text;
  v_rate       numeric;
  v_commission integer;
  v_n          integer;
  v_payments   jsonb;
BEGIN
  PERFORM set_config('drj.reservation_status_change', 'on', true);

  SELECT * INTO v_res
  FROM public.reservations
  WHERE id = p_reservation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'reservation_not_found';
  END IF;
  IF v_res.status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'reservation_not_active';
  END IF;
  IF v_res.paid_deposit_krw < v_res.total_amount_krw THEN
    RAISE EXCEPTION 'reservation_not_fully_paid';
  END IF;

  v_batch := 'rsv_' || v_res.id::text;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'payment_type', rp.payment_type,
    'payment_method', rp.payment_method,
    'amount_krw', rp.amount_krw,
    'branch', rp.branch
  ) ORDER BY rp.created_at), '[]'::jsonb)
  INTO v_payments
  FROM public.reservation_payments AS rp
  WHERE rp.reservation_id = v_res.id;

  FOR v_item IN
    SELECT * FROM public.reservation_items
    WHERE reservation_id = v_res.id
    ORDER BY id
  LOOP
    SELECT * INTO v_prod
    FROM public.products
    WHERE id = v_item.product_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'product_not_reserved: %', v_item.product_id;
    END IF;
    IF v_prod.status IS DISTINCT FROM 'reserved' THEN
      RAISE EXCEPTION 'product_not_reserved: %', v_item.product_id;
    END IF;

    UPDATE public.products
    SET
      status = 'sold',
      product_status = 'sold',
      stock_quantity = 0,
      manual_return_lock = false,
      updated_at = now()
    WHERE id = v_item.product_id
      AND status = 'reserved';

    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'product_not_reserved: %', v_item.product_id;
    END IF;

    v_list := GREATEST(COALESCE(v_item.list_price_krw, 0), 0)::bigint;
    v_agreed := v_item.agreed_price_krw::bigint;
    v_discount := 0;
    IF v_list > v_agreed AND v_list > 0 THEN
      v_discount := LEAST(
        100,
        GREATEST(0, round((v_list - v_agreed) * 100.0 / v_list)::integer)
      );
    END IF;

    v_metal := public.classify_jewelry_metal_category(
      NULLIF(btrim(v_prod.metal), ''),
      NULLIF(btrim(v_prod.metal_type), '')
    );
    v_rate := public.seller_commission_rate_for_metal(p_gold, p_silver, v_metal);
    v_commission := public.seller_commission_krw(v_agreed, v_list, v_rate);

    SELECT sh.id INTO v_hist
    FROM public.sales_history AS sh
    WHERE sh.product_id = v_item.product_id
      AND sh.price_krw > 0
      AND sh.sold_at_utc = timezone('utc', now())
      AND COALESCE(sh.migration_meta ->> 'cash_via', '') = ''
    ORDER BY sh.legacy_id DESC
    LIMIT 1;

    IF v_hist IS NULL THEN
      RAISE EXCEPTION 'sales_history_missing_after_trigger: %', v_item.product_id;
    END IF;

    UPDATE public.sales_history AS sh
    SET
      price_krw = v_agreed,
      list_price_krw = v_list,
      discount_percent = v_discount,
      payment_method = p_payment_method,
      seller_code = p_seller_code,
      seller_name = p_seller_name,
      store_location = p_branch,
      metal_category = v_metal,
      commission_percent = COALESCE(v_rate, 0),
      commission_krw = COALESCE(v_commission, 0),
      sale_batch_id = v_batch,
      scrap_trade_in_krw = 0,
      net_cash_delta_krw = v_agreed,
      migration_meta = COALESCE(sh.migration_meta, '{}'::jsonb) || jsonb_build_object(
        'cash_via', 'reservation_payments',
        'reservation_id', v_res.id::text,
        'reservation_buyout', true,
        'pos_payment_method', p_payment_method,
        'pos_seller_name', p_seller_name,
        'pos_seller_code', p_seller_code,
        'deal_total_krw', v_res.total_amount_krw,
        'line_agreed_krw', v_agreed,
        'reservation_payments', v_payments
      )
    WHERE sh.id = v_hist;

    IF v_first IS NULL THEN
      v_first := v_hist;
    END IF;
  END LOOP;

  IF v_first IS NULL THEN
    RAISE EXCEPTION 'reservation_has_no_items';
  END IF;

  UPDATE public.reservations
  SET
    status = 'completed',
    sale_id = v_first,
    updated_at = now()
  WHERE id = v_res.id
    AND status = 'active';

  RETURN v_first;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4) Sync (service_role) не снимает reserved / sold / in_transfer / lock.
--    POS-продажа изделия из активной брони — product_unavailable.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_products_sync_status_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;

  IF current_user = 'service_role'
     AND COALESCE(current_setting('drj.reservation_status_change', true), '') IS DISTINCT FROM 'on'
     AND (
       OLD.status IN ('reserved', 'sold', 'in_transfer')
       OR COALESCE(OLD.manual_return_lock, false)
     )
  THEN
    NEW.status := OLD.status;
    NEW.stock_quantity := OLD.stock_quantity;
    NEW.product_status := OLD.product_status;
    NEW.store_location := OLD.store_location;
    IF COALESCE(OLD.manual_return_lock, false) THEN
      NEW.manual_return_lock := true;
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'reserved'
     AND NEW.status IS DISTINCT FROM 'reserved'
     AND COALESCE(current_setting('drj.reservation_status_change', true), '') IS DISTINCT FROM 'on'
     AND EXISTS (
       SELECT 1
       FROM public.reservation_items AS ri
       INNER JOIN public.reservations AS r ON r.id = ri.reservation_id
       WHERE ri.product_id = OLD.id
         AND r.status = 'active'
     )
  THEN
    RAISE EXCEPTION 'product_unavailable: % reserved', OLD.id
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_sync_status_guard ON public.products;
CREATE TRIGGER trg_products_sync_status_guard
  BEFORE UPDATE ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_products_sync_status_guard();

-- ---------------------------------------------------------------------------
-- 5) create_reservation
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_reservation(
  p_lines jsonb,
  p_total_amount_krw numeric,
  p_deposit_krw numeric,
  p_payment_method text,
  p_branch text,
  p_seller_name text,
  p_customer_name text,
  p_customer_phone text,
  p_expires_at timestamptz,
  p_comment text DEFAULT NULL,
  p_seller_code text DEFAULT NULL,
  p_receipt_number text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_elem     jsonb;
  v_pid      text;
  v_agreed   bigint;
  v_ids      text[] := '{}';
  v_map      jsonb := '{}'::jsonb;
  v_sum      bigint := 0;
  v_total    bigint;
  v_deposit  bigint;
  v_payment  text;
  v_branch   text;
  v_customer text;
  v_phone    text;
  v_seller   record;
  v_id       uuid;
  v_sale     uuid;
  v_n        integer;
  v_bad      text;
BEGIN
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'empty_lines');
  END IF;
  IF jsonb_array_length(p_lines) > 50 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'too_many_lines');
  END IF;

  FOR v_elem IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_pid := NULLIF(btrim(COALESCE(v_elem ->> 'product_id', '')), '');
    v_agreed := public._reservation_krw(COALESCE(
      NULLIF(v_elem ->> 'agreed_price_krw', '')::numeric,
      NULLIF(v_elem ->> 'price_krw', '')::numeric
    ));
    IF v_pid IS NULL OR v_agreed IS NULL OR v_agreed <= 0 THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_line');
    END IF;
    IF v_map ? v_pid THEN
      RETURN jsonb_build_object('ok', false, 'error', 'duplicate_product');
    END IF;
    v_map := v_map || jsonb_build_object(v_pid, v_agreed);
    v_ids := v_ids || v_pid;
    v_sum := v_sum + v_agreed;
  END LOOP;

  v_total := public._reservation_krw(p_total_amount_krw);
  v_deposit := public._reservation_krw(p_deposit_krw);
  IF v_total IS NULL OR v_total <= 0 OR v_sum <> v_total THEN
    RETURN jsonb_build_object('ok', false, 'error', 'lines_total_mismatch');
  END IF;
  IF v_deposit IS NULL OR v_deposit <= 0 OR v_deposit > v_total THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_deposit');
  END IF;

  v_payment := lower(btrim(COALESCE(p_payment_method, '')));
  IF v_payment NOT IN ('cash', 'card', 'transfer') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_payment_method');
  END IF;

  v_branch := public._norm_store_icn_ans(p_branch);
  IF v_branch IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_branch');
  END IF;

  v_customer := NULLIF(btrim(COALESCE(p_customer_name, '')), '');
  v_phone := NULLIF(btrim(COALESCE(p_customer_phone, '')), '');
  IF v_customer IS NULL OR v_phone IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'customer_required');
  END IF;
  IF p_expires_at IS NULL OR p_expires_at <= now() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_expires_at');
  END IF;

  SELECT * INTO v_seller
  FROM public._reservation_resolve_seller(p_seller_name, p_seller_code) AS s
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'seller_not_resolved');
  END IF;

  PERFORM p.id
  FROM public.products AS p
  WHERE p.id = ANY (v_ids)
  ORDER BY p.id
  FOR UPDATE;

  IF (SELECT count(*) FROM public.products AS p WHERE p.id = ANY (v_ids)) <> cardinality(v_ids) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'product_not_found');
  END IF;

  SELECT p.id INTO v_bad
  FROM public.products AS p
  WHERE p.id = ANY (v_ids)
    AND (p.status IS DISTINCT FROM 'active' OR COALESCE(p.stock_quantity, 0) <= 0)
  LIMIT 1;
  IF v_bad IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'product_unavailable', 'product_id', v_bad);
  END IF;

  SELECT ri.product_id INTO v_bad
  FROM public.reservation_items AS ri
  INNER JOIN public.reservations AS r ON r.id = ri.reservation_id
  WHERE ri.product_id = ANY (v_ids)
    AND r.status = 'active'
  LIMIT 1;
  IF v_bad IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'product_unavailable', 'product_id', v_bad);
  END IF;

  INSERT INTO public.reservations (
    receipt_number, branch, seller_name, seller_code,
    customer_name, customer_phone, expires_at, comment,
    total_amount_krw, paid_deposit_krw, status
  ) VALUES (
    NULLIF(btrim(COALESCE(p_receipt_number, '')), ''),
    v_branch,
    v_seller.seller_name,
    v_seller.seller_code,
    v_customer,
    v_phone,
    p_expires_at,
    NULLIF(btrim(COALESCE(p_comment, '')), ''),
    v_total,
    v_deposit,
    'active'
  )
  RETURNING id INTO v_id;

  INSERT INTO public.reservation_items (
    reservation_id, product_id, sku, title, category,
    weight_g, purity, size, list_price_krw, agreed_price_krw
  )
  SELECT
    v_id,
    p.id,
    p.sku,
    COALESCE(
      NULLIF(btrim(p.name ->> 'ru'), ''),
      NULLIF(btrim(p.name ->> 'ko'), ''),
      p.sku
    ),
    NULLIF(btrim(p.category), ''),
    p.weight_grams,
    NULLIF(btrim(p.metal_type), ''),
    COALESCE(
      CASE
        WHEN p.size_value IS NOT NULL THEN trim(to_char(p.size_value, 'FM999990.999'))
      END,
      NULLIF(btrim(p.available_sizes ->> 0), '')
    ),
    public.round_krw_up_1000(
      public.product_showroom_list_price_krw(p.sale_price, p.price)::numeric
    ),
    (v_map ->> p.id)::bigint
  FROM public.products AS p
  WHERE p.id = ANY (v_ids);

  INSERT INTO public.reservation_payments (
    reservation_id, receipt_number, payment_type, amount_krw,
    payment_method, branch, seller_name, seller_code
  ) VALUES (
    v_id,
    NULLIF(btrim(COALESCE(p_receipt_number, '')), ''),
    'deposit',
    v_deposit,
    v_payment,
    v_branch,
    v_seller.seller_name,
    v_seller.seller_code
  );

  UPDATE public.products
  SET
    status = 'reserved',
    product_status = 'reserved',
    stock_quantity = 0,
    manual_return_lock = false,
    updated_at = now()
  WHERE id = ANY (v_ids)
    AND status = 'active';

  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> cardinality(v_ids) THEN
    RAISE EXCEPTION 'product_unavailable';
  END IF;

  IF v_deposit >= v_total THEN
    v_sale := public._reservation_complete(
      v_id, v_payment, v_branch,
      v_seller.seller_code, v_seller.seller_name,
      v_seller.gold_commission_percent, v_seller.silver_commission_percent
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'reservation_id', v_id,
    'status', CASE WHEN v_sale IS NULL THEN 'active' ELSE 'completed' END,
    'paid_deposit_krw', v_deposit,
    'balance_krw', v_total - v_deposit,
    'completed', v_sale IS NOT NULL,
    'sale_id', v_sale
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 6) pay_reservation_balance
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pay_reservation_balance(
  p_reservation_id uuid,
  p_payment_amount_krw numeric,
  p_payment_method text,
  p_branch text,
  p_seller_name text,
  p_seller_code text DEFAULT NULL,
  p_receipt_number text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res      public.reservations%ROWTYPE;
  v_amount   bigint;
  v_due      bigint;
  v_payment  text;
  v_branch   text;
  v_type     text;
  v_seller   record;
  v_paid     bigint;
  v_sale     uuid;
BEGIN
  IF p_reservation_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reservation_not_found');
  END IF;

  SELECT * INTO v_res
  FROM public.reservations
  WHERE id = p_reservation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reservation_not_found');
  END IF;
  IF v_res.status IS DISTINCT FROM 'active' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reservation_not_active');
  END IF;

  v_amount := public._reservation_krw(p_payment_amount_krw);
  v_due := (v_res.total_amount_krw - v_res.paid_deposit_krw)::bigint;
  IF v_amount IS NULL OR v_amount <= 0 OR v_amount > v_due THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_amount', 'due_krw', v_due);
  END IF;

  v_payment := lower(btrim(COALESCE(p_payment_method, '')));
  IF v_payment NOT IN ('cash', 'card', 'transfer') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_payment_method');
  END IF;

  v_branch := public._norm_store_icn_ans(p_branch);
  IF v_branch IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_branch');
  END IF;

  SELECT * INTO v_seller
  FROM public._reservation_resolve_seller(p_seller_name, p_seller_code) AS s
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'seller_not_resolved');
  END IF;

  v_type := CASE WHEN v_amount = v_due THEN 'buyout' ELSE 'topup' END;
  v_paid := (v_res.paid_deposit_krw + v_amount)::bigint;

  INSERT INTO public.reservation_payments (
    reservation_id, receipt_number, payment_type, amount_krw,
    payment_method, branch, seller_name, seller_code
  ) VALUES (
    v_res.id,
    NULLIF(btrim(COALESCE(p_receipt_number, '')), ''),
    v_type,
    v_amount,
    v_payment,
    v_branch,
    v_seller.seller_name,
    v_seller.seller_code
  );

  UPDATE public.reservations
  SET paid_deposit_krw = v_paid, updated_at = now()
  WHERE id = v_res.id;

  IF v_paid >= v_res.total_amount_krw THEN
    v_sale := public._reservation_complete(
      v_res.id, v_payment, v_branch,
      v_seller.seller_code, v_seller.seller_name,
      v_seller.gold_commission_percent, v_seller.silver_commission_percent
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'reservation_id', v_res.id,
    'payment_type', v_type,
    'paid_deposit_krw', v_paid,
    'balance_krw', v_res.total_amount_krw - v_paid,
    'status', CASE WHEN v_sale IS NULL THEN 'active' ELSE 'completed' END,
    'completed', v_sale IS NOT NULL,
    'sale_id', v_sale
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 7) cancel_reservation
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_reservation(
  p_reservation_id uuid,
  p_refund_deposit boolean DEFAULT false,
  p_refund_method text DEFAULT NULL,
  p_branch text DEFAULT NULL,
  p_seller_name text DEFAULT NULL,
  p_seller_code text DEFAULT NULL,
  p_receipt_number text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res     public.reservations%ROWTYPE;
  v_branch  text;
  v_method  text;
  v_seller_name text;
  v_seller_code text;
  v_seller  record;
  v_refund  bigint;
  v_n       integer;
  v_items   integer;
BEGIN
  IF p_reservation_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reservation_not_found');
  END IF;

  SELECT * INTO v_res
  FROM public.reservations
  WHERE id = p_reservation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reservation_not_found');
  END IF;
  IF v_res.status IS DISTINCT FROM 'active' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reservation_not_active');
  END IF;

  v_refund := v_res.paid_deposit_krw::bigint;
  v_method := lower(btrim(COALESCE(p_refund_method, '')));
  IF COALESCE(p_refund_deposit, false) AND v_refund > 0 THEN
    IF v_method NOT IN ('cash', 'card', 'transfer') THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_payment_method');
    END IF;
  END IF;

  IF p_branch IS NULL OR btrim(p_branch) = '' THEN
    v_branch := v_res.branch;
  ELSE
    v_branch := public._norm_store_icn_ans(p_branch);
    IF v_branch IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_branch');
    END IF;
  END IF;

  IF NULLIF(btrim(COALESCE(p_seller_name, '')), '') IS NULL
     AND NULLIF(btrim(COALESCE(p_seller_code, '')), '') IS NULL
  THEN
    v_seller_name := v_res.seller_name;
    v_seller_code := v_res.seller_code;
  ELSE
    SELECT * INTO v_seller
    FROM public._reservation_resolve_seller(p_seller_name, p_seller_code) AS s
    LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'seller_not_resolved');
    END IF;
    v_seller_name := v_seller.seller_name;
    v_seller_code := v_seller.seller_code;
  END IF;

  PERFORM set_config('drj.reservation_status_change', 'on', true);

  SELECT count(*) INTO v_items
  FROM public.reservation_items
  WHERE reservation_id = v_res.id;

  UPDATE public.products AS p
  SET
    status = 'active',
    product_status = 'active',
    stock_quantity = 1,
    updated_at = now()
  WHERE p.id IN (
    SELECT ri.product_id
    FROM public.reservation_items AS ri
    WHERE ri.reservation_id = v_res.id
  )
    AND p.status = 'reserved';

  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> v_items THEN
    RAISE EXCEPTION 'product_not_reserved';
  END IF;

  UPDATE public.reservations
  SET status = 'cancelled', updated_at = now()
  WHERE id = v_res.id;

  IF COALESCE(p_refund_deposit, false) AND v_refund > 0 THEN
    INSERT INTO public.reservation_payments (
      reservation_id, receipt_number, payment_type, amount_krw,
      payment_method, branch, seller_name, seller_code
    ) VALUES (
      v_res.id,
      NULLIF(btrim(COALESCE(p_receipt_number, '')), ''),
      'refund',
      (-1) * v_refund,
      v_method,
      v_branch,
      v_seller_name,
      v_seller_code
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'reservation_id', v_res.id,
    'status', 'cancelled',
    'refunded_krw', CASE
      WHEN COALESCE(p_refund_deposit, false) THEN v_refund
      ELSE 0
    END,
    'deposit_kept_krw', CASE
      WHEN COALESCE(p_refund_deposit, false) THEN 0
      ELSE v_refund
    END
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 8) Список и бейдж
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_reservations(
  p_filter text DEFAULT 'active',
  p_search text DEFAULT NULL,
  p_branch text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_filter text := lower(btrim(COALESCE(p_filter, 'active')));
  v_q      text := NULLIF(btrim(COALESCE(p_search, '')), '');
  v_branch text;
  v_limit  integer := GREATEST(LEAST(COALESCE(p_limit, 50), 200), 1);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_total  bigint;
  v_rows   jsonb;
BEGIN
  IF v_filter NOT IN ('active', 'expired', 'completed', 'cancelled', 'all') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_filter');
  END IF;

  IF p_branch IS NULL OR btrim(p_branch) = '' OR upper(btrim(p_branch)) = 'ALL' THEN
    v_branch := NULL;
  ELSE
    v_branch := public._norm_store_icn_ans(p_branch);
    IF v_branch IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_branch');
    END IF;
  END IF;

  IF v_q IS NOT NULL THEN
    v_q := replace(replace(replace(v_q, '\', ''), '%', ''), '_', '');
    IF v_q = '' THEN
      v_q := NULL;
    END IF;
  END IF;

  WITH base AS (
    SELECT
      r.*,
      CASE
        WHEN r.status = 'active' AND r.expires_at < now() THEN 'expired'
        WHEN r.status = 'active' THEN 'active'
        ELSE r.status
      END AS display_status
    FROM public.reservations AS r
    WHERE (v_branch IS NULL OR r.branch = v_branch)
      AND (
        v_q IS NULL
        OR r.customer_name ILIKE '%' || v_q || '%'
        OR r.customer_phone ILIKE '%' || v_q || '%'
        OR EXISTS (
          SELECT 1
          FROM public.reservation_items AS ri
          WHERE ri.reservation_id = r.id
            AND ri.sku ILIKE '%' || v_q || '%'
        )
      )
  ),
  filtered AS (
    SELECT * FROM base
    WHERE v_filter = 'all'
      OR (v_filter = 'expired' AND display_status = 'expired')
      OR (v_filter = 'active' AND display_status = 'active')
      OR (v_filter IN ('completed', 'cancelled') AND status = v_filter)
  )
  SELECT count(*) INTO v_total FROM filtered;

  WITH base AS (
    SELECT
      r.*,
      CASE
        WHEN r.status = 'active' AND r.expires_at < now() THEN 'expired'
        WHEN r.status = 'active' THEN 'active'
        ELSE r.status
      END AS display_status
    FROM public.reservations AS r
    WHERE (v_branch IS NULL OR r.branch = v_branch)
      AND (
        v_q IS NULL
        OR r.customer_name ILIKE '%' || v_q || '%'
        OR r.customer_phone ILIKE '%' || v_q || '%'
        OR EXISTS (
          SELECT 1
          FROM public.reservation_items AS ri
          WHERE ri.reservation_id = r.id
            AND ri.sku ILIKE '%' || v_q || '%'
        )
      )
  ),
  filtered AS (
    SELECT * FROM base
    WHERE v_filter = 'all'
      OR (v_filter = 'expired' AND display_status = 'expired')
      OR (v_filter = 'active' AND display_status = 'active')
      OR (v_filter IN ('completed', 'cancelled') AND status = v_filter)
  )
  SELECT COALESCE(jsonb_agg((to_jsonb(page) - 'ord') ORDER BY page.ord), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      f.id,
      f.receipt_number,
      f.branch,
      f.seller_name,
      f.seller_code,
      f.customer_name,
      f.customer_phone,
      f.expires_at,
      f.comment,
      f.total_amount_krw,
      f.paid_deposit_krw,
      (f.total_amount_krw - f.paid_deposit_krw) AS balance_krw,
      f.status,
      f.display_status,
      (f.display_status = 'expired') AS is_expired,
      f.sale_id,
      f.created_at,
      f.updated_at,
      (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', ri.id,
          'product_id', ri.product_id,
          'sku', ri.sku,
          'title', ri.title,
          'category', ri.category,
          'weight_g', ri.weight_g,
          'purity', ri.purity,
          'size', ri.size,
          'list_price_krw', ri.list_price_krw,
          'agreed_price_krw', ri.agreed_price_krw
        ) ORDER BY ri.sku), '[]'::jsonb)
        FROM public.reservation_items AS ri
        WHERE ri.reservation_id = f.id
      ) AS items,
      (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', rp.id,
          'receipt_number', rp.receipt_number,
          'payment_type', rp.payment_type,
          'amount_krw', rp.amount_krw,
          'payment_method', rp.payment_method,
          'branch', rp.branch,
          'seller_name', rp.seller_name,
          'seller_code', rp.seller_code,
          'created_at', rp.created_at
        ) ORDER BY rp.created_at), '[]'::jsonb)
        FROM public.reservation_payments AS rp
        WHERE rp.reservation_id = f.id
      ) AS payments,
      row_number() OVER (
        ORDER BY
          CASE WHEN f.display_status IN ('active', 'expired') THEN f.expires_at END ASC NULLS LAST,
          f.created_at DESC
      ) AS ord
    FROM filtered AS f
    ORDER BY
      CASE WHEN f.display_status IN ('active', 'expired') THEN f.expires_at END ASC NULLS LAST,
      f.created_at DESC
    LIMIT v_limit
    OFFSET v_offset
  ) AS page;

  RETURN jsonb_build_object(
    'ok', true,
    'total', COALESCE(v_total, 0),
    'rows', COALESCE(v_rows, '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_active_reservations_count(
  p_branch text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch text;
  v_count  bigint;
BEGIN
  IF p_branch IS NULL OR btrim(p_branch) = '' OR upper(btrim(p_branch)) = 'ALL' THEN
    v_branch := NULL;
  ELSE
    v_branch := public._norm_store_icn_ans(p_branch);
    IF v_branch IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_branch');
    END IF;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.reservations AS r
  WHERE r.status = 'active'
    AND (v_branch IS NULL OR r.branch = v_branch);

  RETURN jsonb_build_object('ok', true, 'count', COALESCE(v_count, 0));
END;
$$;

-- ---------------------------------------------------------------------------
-- 9) Касса: залог в смене, выкуп в истории без второго прихода
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_sales_history_summary(
  p_date_from date,
  p_date_to date,
  p_store text DEFAULT 'ALL'
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH filtered AS (
    SELECT sh.*, public._sales_history_resolve_store(sh) AS resolved_store,
      COALESCE(p.weight_grams, NULLIF((sh.raw_legacy_payload ->> 'weight_grams')::numeric, 0), 0) AS w_g,
      COALESCE(sh.metal_category,
        public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
        public.classify_jewelry_metal_category(p.metal, p.metal_type), 'other') AS m_cat
    FROM public.sales_history AS sh
    LEFT JOIN public.products AS p ON p.id = sh.product_id
      OR (sh.product_id IS NULL AND p.sku = sh.sku)
    WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
      AND (upper(btrim(COALESCE(p_store, 'ALL'))) = 'ALL'
        OR public._sales_history_resolve_store(sh) = upper(btrim(p_store)))
  ),
  batch_scrap AS (
    SELECT sale_batch_id, max(scrap_trade_in_krw) AS scrap_krw
    FROM filtered
    WHERE sale_batch_id IS NOT NULL AND scrap_trade_in_krw > 0
    GROUP BY sale_batch_id
  ),
  agg AS (
    SELECT
      COALESCE(sum(f.price_krw) FILTER (WHERE f.price_krw > 0), 0) AS gross,
      COALESCE(count(*) FILTER (WHERE f.price_krw > 0), 0) AS total_count,
      COALESCE(sum(f.price_krw) FILTER (
        WHERE f.price_krw > 0
          AND COALESCE(f.migration_meta ->> 'cash_via', '') = 'reservation_payments'
      ), 0) AS booked_gross,
      COALESCE(sum(f.price_krw) FILTER (
        WHERE f.price_krw < 0
          AND EXISTS (
            SELECT 1
            FROM public.sales_history AS orig
            WHERE orig.legacy_id = (f.migration_meta ->> 'reverses_legacy_id')
              AND COALESCE(orig.migration_meta ->> 'cash_via', '') = 'reservation_payments'
          )
      ), 0) AS booked_returns,
      COALESCE(sum(f.w_g) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'gold'), 0) AS gold_w,
      COALESCE(sum(f.price_krw) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'gold'), 0) AS gold_sum,
      COALESCE(count(*) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'gold'), 0) AS gold_count,
      COALESCE(sum(f.w_g) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'silver'), 0) AS silver_w,
      COALESCE(sum(f.price_krw) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'silver'), 0) AS silver_sum,
      COALESCE(count(*) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'silver'), 0) AS silver_count,
      COALESCE(count(*) FILTER (WHERE f.price_krw > 0 AND f.m_cat = 'other'), 0) AS other_count
    FROM filtered AS f
  ),
  reservation_cash AS (
    SELECT COALESCE(sum(rp.amount_krw), 0) AS net_krw
    FROM public.reservation_payments AS rp
    WHERE (rp.created_at AT TIME ZONE 'Asia/Seoul')::date BETWEEN p_date_from AND p_date_to
      AND (
        upper(btrim(COALESCE(p_store, 'ALL'))) = 'ALL'
        OR public._norm_store_icn_ans(rp.branch) = upper(btrim(p_store))
      )
  ),
  scrap AS (
    SELECT
      COALESCE(sum(scrap_krw), 0) AS scrap_krw,
      COALESCE(count(*), 0) AS batch_count
    FROM batch_scrap
  )
  SELECT jsonb_build_object(
    'total_sum_krw', a.gross,
    'total_count', a.total_count,
    'gross_sales_krw', a.gross,
    'trade_in_scrap_krw', s.scrap_krw,
    'trade_in_batch_count', s.batch_count,
    'net_cash_krw', a.gross - a.booked_gross - s.scrap_krw + r.net_krw + a.booked_returns,
    'shift_cash_krw', a.gross - a.booked_gross - s.scrap_krw + r.net_krw + a.booked_returns,
    'reservation_cash_krw', r.net_krw,
    'gold_weight_grams', a.gold_w,
    'gold_sum_krw', a.gold_sum,
    'gold_count', a.gold_count,
    'silver_weight_grams', a.silver_w,
    'silver_sum_krw', a.silver_sum,
    'silver_count', a.silver_count,
    'other_count', a.other_count
  )
  FROM agg AS a
  CROSS JOIN reservation_cash AS r
  CROSS JOIN scrap AS s;
$$;

CREATE OR REPLACE FUNCTION public.get_shift_cash_summary(
  p_date_from date,
  p_date_to date,
  p_branch text DEFAULT 'ALL',
  p_seller_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch text;
  v_seller text := NULLIF(btrim(COALESCE(p_seller_name, '')), '');
  v_rows   jsonb;
  v_shift  bigint;
  v_scrap  bigint;
  v_sales  bigint;
  v_res    bigint;
  v_ret    bigint;
BEGIN
  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_range');
  END IF;

  IF p_branch IS NULL OR btrim(p_branch) = '' OR upper(btrim(p_branch)) = 'ALL' THEN
    v_branch := NULL;
  ELSE
    v_branch := public._norm_store_icn_ans(p_branch);
    IF v_branch IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_branch');
    END IF;
  END IF;

  WITH movements AS (
    SELECT
      COALESCE(NULLIF(btrim(sh.payment_method), ''), 'unknown') AS method,
      sh.price_krw::numeric AS amount_krw
    FROM public.sales_history AS sh
    WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
      AND sh.price_krw > 0
      AND COALESCE(sh.migration_meta ->> 'cash_via', '') IS DISTINCT FROM 'reservation_payments'
      AND (v_branch IS NULL OR public._sales_history_resolve_store(sh) = v_branch)
      AND (
        v_seller IS NULL
        OR upper(btrim(COALESCE(sh.seller_name, ''))) = upper(v_seller)
        OR upper(btrim(COALESCE(sh.seller_code, ''))) = upper(v_seller)
      )
    UNION ALL
    SELECT rp.payment_method, rp.amount_krw
    FROM public.reservation_payments AS rp
    WHERE (rp.created_at AT TIME ZONE 'Asia/Seoul')::date BETWEEN p_date_from AND p_date_to
      AND (v_branch IS NULL OR rp.branch = v_branch)
      AND (
        v_seller IS NULL
        OR upper(btrim(COALESCE(rp.seller_name, ''))) = upper(v_seller)
        OR upper(btrim(COALESCE(rp.seller_code, ''))) = upper(v_seller)
      )
    UNION ALL
    SELECT
      COALESCE(NULLIF(btrim(sh.payment_method), ''), 'unknown'),
      sh.price_krw::numeric
    FROM public.sales_history AS sh
    WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
      AND sh.price_krw < 0
      AND EXISTS (
        SELECT 1
        FROM public.sales_history AS orig
        WHERE orig.legacy_id = (sh.migration_meta ->> 'reverses_legacy_id')
          AND COALESCE(orig.migration_meta ->> 'cash_via', '') = 'reservation_payments'
      )
      AND (v_branch IS NULL OR public._sales_history_resolve_store(sh) = v_branch)
      AND (
        v_seller IS NULL
        OR upper(btrim(COALESCE(sh.seller_name, ''))) = upper(v_seller)
        OR upper(btrim(COALESCE(sh.seller_code, ''))) = upper(v_seller)
      )
  ),
  by_method AS (
    SELECT method, COALESCE(sum(amount_krw), 0)::bigint AS amount_krw
    FROM movements
    GROUP BY method
  )
  SELECT COALESCE(jsonb_object_agg(method, amount_krw), '{}'::jsonb)
  INTO v_rows
  FROM by_method;

  SELECT COALESCE(sum(sh.price_krw), 0)::bigint
  INTO v_sales
  FROM public.sales_history AS sh
  WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
    AND sh.price_krw > 0
    AND COALESCE(sh.migration_meta ->> 'cash_via', '') IS DISTINCT FROM 'reservation_payments'
    AND (v_branch IS NULL OR public._sales_history_resolve_store(sh) = v_branch)
    AND (
      v_seller IS NULL
      OR upper(btrim(COALESCE(sh.seller_name, ''))) = upper(v_seller)
      OR upper(btrim(COALESCE(sh.seller_code, ''))) = upper(v_seller)
    );

  SELECT COALESCE(sum(rp.amount_krw), 0)::bigint
  INTO v_res
  FROM public.reservation_payments AS rp
  WHERE (rp.created_at AT TIME ZONE 'Asia/Seoul')::date BETWEEN p_date_from AND p_date_to
    AND (v_branch IS NULL OR rp.branch = v_branch)
    AND (
      v_seller IS NULL
      OR upper(btrim(COALESCE(rp.seller_name, ''))) = upper(v_seller)
      OR upper(btrim(COALESCE(rp.seller_code, ''))) = upper(v_seller)
    );

  SELECT COALESCE(sum(sh.price_krw), 0)::bigint
  INTO v_ret
  FROM public.sales_history AS sh
  WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
    AND sh.price_krw < 0
    AND EXISTS (
      SELECT 1
      FROM public.sales_history AS orig
      WHERE orig.legacy_id = (sh.migration_meta ->> 'reverses_legacy_id')
        AND COALESCE(orig.migration_meta ->> 'cash_via', '') = 'reservation_payments'
    )
    AND (v_branch IS NULL OR public._sales_history_resolve_store(sh) = v_branch)
    AND (
      v_seller IS NULL
      OR upper(btrim(COALESCE(sh.seller_name, ''))) = upper(v_seller)
      OR upper(btrim(COALESCE(sh.seller_code, ''))) = upper(v_seller)
    );

  SELECT COALESCE(sum(batch.scrap_krw), 0)::bigint
  INTO v_scrap
  FROM (
    SELECT max(sh.scrap_trade_in_krw) AS scrap_krw
    FROM public.sales_history AS sh
    WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
      AND sh.sale_batch_id IS NOT NULL
      AND sh.scrap_trade_in_krw > 0
      AND (v_branch IS NULL OR public._sales_history_resolve_store(sh) = v_branch)
      AND (
        v_seller IS NULL
        OR upper(btrim(COALESCE(sh.seller_name, ''))) = upper(v_seller)
        OR upper(btrim(COALESCE(sh.seller_code, ''))) = upper(v_seller)
      )
    GROUP BY sh.sale_batch_id
  ) AS batch;

  v_shift := COALESCE(v_sales, 0) + COALESCE(v_res, 0) + COALESCE(v_ret, 0) - COALESCE(v_scrap, 0);

  RETURN jsonb_build_object(
    'ok', true,
    'branch', COALESCE(v_branch, 'ALL'),
    'seller', v_seller,
    'shift_cash_krw', v_shift,
    'sales_cash_krw', COALESCE(v_sales, 0),
    'reservation_cash_krw', COALESCE(v_res, 0),
    'reservation_sale_return_krw', COALESCE(v_ret, 0),
    'trade_in_scrap_krw', COALESCE(v_scrap, 0),
    'by_method', COALESCE(v_rows, '{}'::jsonb)
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 10) Права
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public._reservation_krw(numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._reservation_resolve_seller(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._reservation_complete(uuid, text, text, text, text, numeric, numeric) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.create_reservation(jsonb, numeric, numeric, text, text, text, text, text, timestamptz, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_reservation(jsonb, numeric, numeric, text, text, text, text, text, timestamptz, text, text, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.pay_reservation_balance(uuid, numeric, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pay_reservation_balance(uuid, numeric, text, text, text, text, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.cancel_reservation(uuid, boolean, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_reservation(uuid, boolean, text, text, text, text, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.list_reservations(text, text, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_reservations(text, text, text, integer, integer)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_active_reservations_count(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_reservations_count(text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_shift_cash_summary(date, date, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_shift_cash_summary(date, date, text, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_sales_history_summary(date, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_sales_history_summary(date, date, text)
  TO anon, authenticated, service_role;

COMMIT;
