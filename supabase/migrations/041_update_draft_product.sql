-- Полное редактирование черновика (products.stock_quantity = 0) админом.

BEGIN;

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

  IF EXISTS (
    SELECT 1
    FROM public.products AS p
    WHERE p.sku = v_sku
      AND p.id IS DISTINCT FROM v_id
  ) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'SKU уже занят другой карточкой'
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
  'Админ: полное обновление черновика (без дубля, stock=0).';

REVOKE ALL ON FUNCTION public.update_draft_product(jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.update_draft_product(jsonb, text)
  TO anon, authenticated, service_role;

COMMIT;