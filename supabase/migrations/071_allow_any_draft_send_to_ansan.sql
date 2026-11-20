-- 071: Партия в Ансан — любой черновик hidden/active stock=0 (бейдж ICN/ANS/NULL).
BEGIN;

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
  'Черновики stock=0 hidden/active (любой бейдж) → product_transfers ICN→ANS in_transit.';

REVOKE ALL ON FUNCTION public.send_drafts_to_ansan_by_ids(text, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_drafts_to_ansan_by_ids(text, text[])
  TO anon, authenticated, service_role;

COMMIT;