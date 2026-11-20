-- 070: Партия черновиков ICN→ANS: product_transfers + complete/cancel для stock=0.
BEGIN;

-- ---------------------------------------------------------------------------
-- send_drafts_to_ansan_by_ids: реальные трансферы in_transit
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_drafts_to_ansan_by_ids(
  p_actor_code text,
  p_ids text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor text := upper(btrim(coalesce(p_actor_code, '')));
  v_pid text;
  v_row public.products%ROWTYPE;
  v_from text;
  v_count integer := 0;
  v_has_from_loc boolean;
  v_has_to_loc boolean;
  v_open boolean;
  v_transfer_id uuid;
BEGIN
  IF v_actor = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите код сотрудника');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.sellers AS s WHERE s.promo_code = v_actor AND s.is_active = true
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Код сотрудника не активен');
  END IF;

  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите массив id черновиков');
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'product_transfers'
      AND column_name = 'from_location'
  ) INTO v_has_from_loc;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'product_transfers'
      AND column_name = 'to_location'
  ) INTO v_has_to_loc;

  FOREACH v_pid IN ARRAY p_ids LOOP
    v_pid := NULLIF(btrim(coalesce(v_pid, '')), '');
    IF v_pid IS NULL THEN
      CONTINUE;
    END IF;

    SELECT * INTO v_row
    FROM public.products AS p
    WHERE p.id = v_pid
    FOR UPDATE;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    IF coalesce(v_row.stock_quantity, 0) <> 0 THEN
      CONTINUE;
    END IF;

    IF v_row.status NOT IN ('hidden', 'active') THEN
      CONTINUE;
    END IF;

    v_from := upper(btrim(coalesce(v_row.store_location, '')));
    IF v_from = '' THEN
      v_from := 'ICN';
    ELSIF v_from NOT IN ('ICN', 'ANS') THEN
      v_from := public._norm_store_icn_ans(v_row.store_location);
    END IF;

    IF v_from IS DISTINCT FROM 'ICN' THEN
      CONTINUE;
    END IF;

    SELECT EXISTS (
      SELECT 1
      FROM public.product_transfers AS t
      WHERE t.product_id = v_pid
        AND public._transfer_status_is_open(t.status)
    ) INTO v_open;

    IF v_open THEN
      CONTINUE;
    END IF;

    UPDATE public.products
    SET
      status = 'in_transfer',
      store_location = 'ICN',
      updated_at = now()
    WHERE id = v_pid;

    IF v_has_from_loc AND v_has_to_loc THEN
      INSERT INTO public.product_transfers (
        product_id,
        sku,
        qr_code_payload,
        from_store,
        to_store,
        from_location,
        to_location,
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
        'ICN',
        'ANS',
        'ICN',
        'ANS',
        'in_transit',
        v_actor,
        v_row.weight_grams,
        coalesce(v_row.metal_type, v_row.metal),
        'draft_batch_icn_to_ans'
      )
      RETURNING id INTO v_transfer_id;
    ELSE
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
        'ICN',
        'ANS',
        'in_transit',
        v_actor,
        v_row.weight_grams,
        coalesce(v_row.metal_type, v_row.metal),
        'draft_batch_icn_to_ans'
      )
      RETURNING id INTO v_transfer_id;
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'sent_count', coalesce(v_count, 0)
  );
END;
$$;

COMMENT ON FUNCTION public.send_drafts_to_ansan_by_ids(text, text[]) IS
  'Черновики ICN (stock=0) → product_transfers in_transit ICN→ANS, products.in_transfer.';

-- ---------------------------------------------------------------------------
-- complete_product_transfer_by_id: приёмка черновика → витрина ANS
-- ---------------------------------------------------------------------------
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
    stock_quantity = greatest(coalesce(p.stock_quantity, 0), 1),
    updated_at = now()
  WHERE p.id = v_t.product_id
    AND p.status IN ('in_transfer', 'active', 'hidden');

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

-- ---------------------------------------------------------------------------
-- cancel_product_transfer_by_id: откат непринятого черновика
-- ---------------------------------------------------------------------------
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
  v_was_draft boolean;
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

  SELECT coalesce(p.stock_quantity, 0) = 0
  INTO v_was_draft
  FROM public.products AS p
  WHERE p.id = v_t.product_id;

  UPDATE public.product_transfers
  SET
    status = 'cancelled',
    updated_at = now()
  WHERE id = p_transfer_id;

  IF v_was_draft THEN
    UPDATE public.products AS p
    SET
      status = 'hidden',
      store_location = coalesce(v_t.from_store, 'ICN'),
      stock_quantity = 0,
      updated_at = now()
    WHERE p.id = v_t.product_id
      AND p.status IN ('in_transfer', 'active', 'hidden');
  ELSE
    UPDATE public.products AS p
    SET
      status = 'active',
      store_location = coalesce(v_t.from_store, p.store_location),
      stock_quantity = greatest(coalesce(p.stock_quantity, 0), 1),
      updated_at = now()
    WHERE p.id = v_t.product_id
      AND p.status IN ('in_transfer', 'active');
  END IF;

  RETURN jsonb_build_object('ok', true, 'transfer_id', p_transfer_id, 'sku', v_t.sku);
END;
$$;

-- ---------------------------------------------------------------------------
-- Backfill: in_transfer без product_transfers (старая кнопка 065)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_has_from_loc boolean;
  v_has_to_loc boolean;
  v_backfill integer := 0;
  r record;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'product_transfers'
      AND column_name = 'from_location'
  ) INTO v_has_from_loc;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'product_transfers'
      AND column_name = 'to_location'
  ) INTO v_has_to_loc;

  FOR r IN
    SELECT p.*
    FROM public.products AS p
    WHERE p.status = 'in_transfer'
      AND coalesce(p.stock_quantity, 0) = 0
      AND NOT EXISTS (
        SELECT 1
        FROM public.product_transfers AS t
        WHERE t.product_id = p.id
          AND public._transfer_status_is_open(t.status)
      )
  LOOP
    UPDATE public.products
    SET store_location = 'ICN', updated_at = now()
    WHERE id = r.id;

    IF v_has_from_loc AND v_has_to_loc THEN
      INSERT INTO public.product_transfers (
        product_id, sku, qr_code_payload,
        from_store, to_store, from_location, to_location,
        status, sender_code, weight_grams, metal_type, notes
      )
      VALUES (
        r.id, r.sku, r.qr_code_payload,
        'ICN', 'ANS', 'ICN', 'ANS',
        'in_transit', 'BACKFILL', r.weight_grams,
        coalesce(r.metal_type, r.metal),
        'backfill_070_stuck_in_transfer'
      );
    ELSE
      INSERT INTO public.product_transfers (
        product_id, sku, qr_code_payload,
        from_store, to_store, status, sender_code,
        weight_grams, metal_type, notes
      )
      VALUES (
        r.id, r.sku, r.qr_code_payload,
        'ICN', 'ANS', 'in_transit', 'BACKFILL',
        r.weight_grams, coalesce(r.metal_type, r.metal),
        'backfill_070_stuck_in_transfer'
      );
    END IF;

    v_backfill := v_backfill + 1;
  END LOOP;

  RAISE NOTICE '070 backfill product_transfers for stuck drafts: %', v_backfill;
END $$;

REVOKE ALL ON FUNCTION public.send_drafts_to_ansan_by_ids(text, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_drafts_to_ansan_by_ids(text, text[])
  TO anon, authenticated, service_role;

COMMIT;