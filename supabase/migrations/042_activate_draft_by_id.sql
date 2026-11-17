-- Приёмка черновиков строго по products.id (поштучно); одинаковый sku допустим.

BEGIN;

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
    AND p.status IN ('hidden', 'active');

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
    AND p.status IN ('hidden', 'active');

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

COMMENT ON FUNCTION public.activate_draft_product_by_id(text, text, text, text) IS
  'Админ: активация одного черновика по id; другие экземпляры с тем же sku не затрагиваются.';

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
      AND p.status IN ('hidden', 'active')
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

COMMENT ON FUNCTION public.activate_draft_products_by_ids(jsonb, text) IS
  'Админ: массовая активация черновиков по списку id (store_location должен быть ICN/ANS).';

-- Legacy: по sku активируем не более одной строки (страховка от массовой приёмки по артикулу).
CREATE OR REPLACE FUNCTION public.activate_draft_product_by_sku(
  p_sku text,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sku text := btrim(COALESCE(p_sku, ''));
  v_id text;
BEGIN
  IF v_sku = '' THEN
    RETURN false;
  END IF;
  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN false;
  END IF;

  SELECT p.id INTO v_id
  FROM public.products AS p
  WHERE p.sku = v_sku
    AND p.stock_quantity = 0
    AND p.status IN ('hidden', 'active')
  ORDER BY p.updated_at DESC NULLS LAST, p.id
  LIMIT 1;

  IF v_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN COALESCE(
    (public.activate_draft_product_by_id(v_id, NULL, NULL, p_admin_email) ->> 'ok')::boolean,
    false
  );
END;
$$;

-- Редактирование черновика: одинаковый sku у разных физических экземпляров разрешён.
CREATE OR REPLACE FUNCTION public.update_draft_product(
  p_payload jsonb,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id text;
  v_sku text;
  v_name text;
  v_row public.products%ROWTYPE;
  v_images jsonb;
  v_first text;
  v_store text;
  v_loc text;
BEGIN
  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Нет прав администратора');
  END IF;

  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Некорректный payload');
  END IF;

  v_id := NULLIF(btrim(COALESCE(p_payload->>'id', '')), '');
  IF v_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите id черновика');
  END IF;

  v_sku := NULLIF(btrim(COALESCE(p_payload->>'sku', '')), '');
  IF v_sku IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите SKU');
  END IF;

  SELECT * INTO v_row
  FROM public.products AS p
  WHERE p.id = v_id
    AND p.stock_quantity = 0
    AND p.status IN ('hidden', 'active');

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Черновик не найден или уже активирован'
    );
  END IF;

  v_name := NULLIF(btrim(COALESCE(p_payload->>'name', '')), '');
  IF v_name IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите наименование');
  END IF;

  v_images := COALESCE(p_payload->'additional_images', '[]'::jsonb);
  IF jsonb_typeof(v_images) IS DISTINCT FROM 'array' THEN
    v_images := '[]'::jsonb;
  END IF;

  v_first := NULLIF(btrim(COALESCE(p_payload->>'image_url', '')), '');
  IF v_first IS NULL AND jsonb_array_length(v_images) > 0 THEN
    v_first := NULLIF(btrim(v_images ->> 0), '');
  END IF;

  v_store := NULLIF(btrim(COALESCE(p_payload->>'store_location', '')), '');
  IF v_store IS NULL OR upper(v_store) IN ('', 'UNSELECTED', 'NONE', 'NULL') THEN
    v_loc := NULL;
  ELSIF upper(v_store) IN ('ANS', 'ANSAN', 'АНСАН') THEN
    v_loc := 'ANS';
  ELSIF upper(v_store) IN ('ICN', 'INCHEON', 'ИНЧХОН') THEN
    v_loc := 'ICN';
  ELSE
    RETURN jsonb_build_object('ok', false, 'error', 'Недопустимый магазин');
  END IF;

  UPDATE public.products AS p
  SET
    sku = v_sku,
    name = jsonb_build_object('ru', v_name, 'ko', v_name),
    metal = NULLIF(btrim(COALESCE(p_payload->>'metal_type', p_payload->>'metal', '')), ''),
    metal_type = NULLIF(btrim(COALESCE(p_payload->>'metal_type', p_payload->>'metal', '')), ''),
    category = COALESCE(
      NULLIF(btrim(COALESCE(p_payload->>'category', '')), ''),
      'manual'
    ),
    "insert" = COALESCE(NULLIF(btrim(COALESCE(p_payload->>'insert', '')), ''), ''),
    gem_inserts = COALESCE(NULLIF(btrim(COALESCE(p_payload->>'gem_inserts', '')), ''), ''),
    weight_grams = GREATEST(COALESCE((p_payload->>'weight_grams')::numeric, 0), 0),
    size_value = (p_payload->>'size_value')::numeric,
    notes = COALESCE(NULLIF(btrim(COALESCE(p_payload->>'notes', '')), ''), ''),
    manufacturer = COALESCE(NULLIF(btrim(COALESCE(p_payload->>'manufacturer', '')), ''), ''),
    price = GREATEST(COALESCE((p_payload->>'sale_price')::integer, (p_payload->>'price')::integer, 0), 0),
    sale_price = GREATEST(COALESCE((p_payload->>'sale_price')::integer, (p_payload->>'price')::integer, 0), 0),
    old_price = GREATEST(COALESCE((p_payload->>'sale_price')::integer, (p_payload->>'price')::integer, 0), 0),
    store_location = v_loc,
    additional_images = v_images,
    image_url = v_first,
    status = 'hidden',
    stock_quantity = 0,
    updated_at = now()
  WHERE p.id = v_id;

  RETURN jsonb_build_object('ok', true, 'id', v_id, 'sku', v_sku);
END;
$$;

COMMENT ON FUNCTION public.update_draft_product(jsonb, text) IS
  'Админ: полное обновление черновика по id; дубли sku между экземплярами допустимы.';

REVOKE ALL ON FUNCTION public.activate_draft_product_by_id(text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.activate_draft_products_by_ids(jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.activate_draft_product_by_id(text, text, text, text)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.activate_draft_products_by_ids(jsonb, text)
  TO anon, authenticated, service_role;

COMMIT;