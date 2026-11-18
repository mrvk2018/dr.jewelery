-- Dr. Jewelry — 045: legacy from_location/to_location, desync draft activate vs product_transfers, data-fix 20180.

BEGIN;

-- ---------------------------------------------------------------------------
-- Legacy колонки product_transfers (есть на проде, нет в 043 git-DDL)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'product_transfers'
      AND column_name = 'from_location'
  ) THEN
    ALTER TABLE public.product_transfers
      ALTER COLUMN from_location DROP NOT NULL;

    UPDATE public.product_transfers AS t
    SET from_location = t.from_store
    WHERE t.from_location IS NULL
      AND t.from_store IS NOT NULL;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'product_transfers'
      AND column_name = 'to_location'
  ) THEN
    ALTER TABLE public.product_transfers
      ALTER COLUMN to_location DROP NOT NULL;

    UPDATE public.product_transfers AS t
    SET to_location = t.to_store
    WHERE t.to_location IS NULL
      AND t.to_store IS NOT NULL;
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'product_transfers'
      AND column_name = 'from_location'
  ) THEN
    EXECUTE $sync$
      CREATE OR REPLACE FUNCTION public.product_transfers_sync_store_location_columns()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $fn$
      BEGIN
        IF NEW.from_store IS NOT NULL AND (
          NEW.from_location IS NULL OR NEW.from_location IS DISTINCT FROM NEW.from_store
        ) THEN
          NEW.from_location := NEW.from_store;
        ELSIF NEW.from_location IS NOT NULL AND NEW.from_store IS NULL THEN
          NEW.from_store := public._norm_store_icn_ans(NEW.from_location);
        END IF;

        IF NEW.to_store IS NOT NULL AND (
          NEW.to_location IS NULL OR NEW.to_location IS DISTINCT FROM NEW.to_store
        ) THEN
          NEW.to_location := NEW.to_store;
        ELSIF NEW.to_location IS NOT NULL AND NEW.to_store IS NULL THEN
          NEW.to_store := public._norm_store_icn_ans(NEW.to_location);
        END IF;

        RETURN NEW;
      END;
      $fn$;
    $sync$;

    DROP TRIGGER IF EXISTS trg_product_transfers_sync_store_location
      ON public.product_transfers;

    CREATE TRIGGER trg_product_transfers_sync_store_location
      BEFORE INSERT OR UPDATE OF from_store, to_store, from_location, to_location
      ON public.product_transfers
      FOR EACH ROW
      EXECUTE FUNCTION public.product_transfers_sync_store_location_columns();
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- Авто-закрытие открытых трансферов при приёмке черновика
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._close_open_transfers_for_draft_activation(
  p_product_id text,
  p_activate_store text
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_loc text := public._norm_store_icn_ans(p_activate_store);
  v_t public.product_transfers%ROWTYPE;
  v_suffix text;
  v_note text;
BEGIN
  IF p_product_id IS NULL OR btrim(p_product_id) = '' OR v_loc IS NULL THEN
    RETURN NULL;
  END IF;

  FOR v_t IN
    SELECT t.*
    FROM public.product_transfers AS t
    WHERE t.product_id = p_product_id
      AND public._transfer_status_is_open(t.status)
    ORDER BY t.created_at DESC NULLS LAST
    FOR UPDATE
  LOOP
    v_suffix := format(
      E'\n[auto 045] Черновик активирован в %s (маршрут %s→%s).',
      v_loc,
      coalesce(v_t.from_store, '?'),
      coalesce(v_t.to_store, '?')
    );

    IF public._norm_store_icn_ans(v_t.to_store) = v_loc THEN
      v_note := NULLIF(btrim(coalesce(v_t.notes, '') || v_suffix), '');
      UPDATE public.product_transfers
      SET
        status = 'completed',
        notes = v_note,
        updated_at = now()
      WHERE id = v_t.id;

      RETURN jsonb_build_object(
        'transfer_resolution', 'completed',
        'transfer_id', v_t.id,
        'transfer_from', v_t.from_store,
        'transfer_to', v_t.to_store
      );
    END IF;

    v_note := NULLIF(btrim(coalesce(v_t.notes, '') || v_suffix || ' Трансфер отменён.'), '');
    UPDATE public.product_transfers
    SET
      status = 'cancelled',
      notes = v_note,
      updated_at = now()
    WHERE id = v_t.id;

    RETURN jsonb_build_object(
      'transfer_resolution', 'cancelled',
      'transfer_id', v_t.id,
      'transfer_from', v_t.from_store,
      'transfer_to', v_t.to_store
    );
  END LOOP;

  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- create_product_transfer_by_id: INSERT + legacy location columns when present
-- ---------------------------------------------------------------------------
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
  v_has_from_loc boolean;
  v_has_to_loc boolean;
  v_notes text := NULLIF(btrim(coalesce(p_notes, '')), '');
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
      v_from,
      v_to,
      v_from,
      v_to,
      'in_transit',
      v_sender,
      v_row.weight_grams,
      coalesce(v_row.metal_type, v_row.metal),
      v_notes
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
      v_from,
      v_to,
      'in_transit',
      v_sender,
      v_row.weight_grams,
      coalesce(v_row.metal_type, v_row.metal),
      v_notes
    )
    RETURNING id INTO v_transfer_id;
  END IF;

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

-- ---------------------------------------------------------------------------
-- complete / cancel: обновление products при in_transfer ИЛИ active (не sold/reserved/hidden)
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
    AND p.status IN ('in_transfer', 'active');

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
    stock_quantity = greatest(coalesce(p.stock_quantity, 0), 1),
    updated_at = now()
  WHERE p.id = v_t.product_id
    AND p.status IN ('in_transfer', 'active');

  RETURN jsonb_build_object('ok', true, 'transfer_id', p_transfer_id, 'sku', v_t.sku);
END;
$$;

-- ---------------------------------------------------------------------------
-- activate_draft_* + закрытие висящих product_transfers
-- ---------------------------------------------------------------------------
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
  v_xfer jsonb;
  v_out jsonb;
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

  v_xfer := public._close_open_transfers_for_draft_activation(v_id, v_loc);

  v_out := jsonb_build_object(
    'ok', true,
    'id', v_id,
    'sku', v_row.sku,
    'store_location', v_loc
  );

  IF v_xfer IS NOT NULL THEN
    v_out := v_out || v_xfer;
  END IF;

  RETURN v_out;
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
  v_loc text;
  v_xfer jsonb;
  v_closed integer := 0;
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
      SELECT p.store_location INTO v_loc FROM public.products AS p WHERE p.id = v_id;
      v_xfer := public._close_open_transfers_for_draft_activation(v_id, v_loc);
      IF v_xfer IS NOT NULL THEN
        v_closed := v_closed + 1;
      END IF;
      v_activated := v_activated + 1;
    ELSE
      v_skipped := v_skipped + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'activated', v_activated,
    'skipped', v_skipped,
    'transfers_resolved', v_closed
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Data-fix: MSSQL cutover 20180
-- ---------------------------------------------------------------------------
UPDATE public.products AS p
SET
  status = 'active',
  store_location = 'ANS',
  stock_quantity = 1,
  updated_at = now()
WHERE p.id = '20180'
  AND p.sku = '436-92030780';

UPDATE public.product_transfers AS t
SET
  status = CASE
    WHEN public._transfer_status_is_open(t.status) THEN 'completed'
    ELSE t.status
  END,
  notes = NULLIF(
    btrim(
      coalesce(t.notes, '') || E'\n[data-fix 045] Товар 20180 — активен в ANS.'
    ),
    ''
  ),
  updated_at = now()
WHERE t.product_id = '20180'
  AND public._transfer_status_is_open(t.status);

COMMIT;