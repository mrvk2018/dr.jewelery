-- Синхронизация gallery_slots на все экземпляры с тем же SKU (артикулом).
-- Зависит от 058 (колонка gallery_slots, нормализация, триггер витрины).

-- ---------------------------------------------------------------------------
-- admin_set_product_gallery_slots: одна комбинация 4 слотов → все строки SKU
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_product_gallery_slots(
  p_product_id text,
  p_gallery_slots jsonb,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id text := btrim(COALESCE(p_product_id, ''));
  v_sku text;
  v_slots jsonb;
  v_updated int := 0;
BEGIN
  IF v_id = '' THEN
    RETURN false;
  END IF;
  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN false;
  END IF;

  SELECT lower(btrim(COALESCE(p.sku, '')))
  INTO v_sku
  FROM public.products AS p
  WHERE p.id::text = v_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  v_slots := public._product_gallery_slots_normalize(p_gallery_slots);

  IF v_sku <> '' THEN
    UPDATE public.products AS p
    SET
      gallery_slots = v_slots,
      updated_at = now()
    WHERE lower(btrim(COALESCE(p.sku, ''))) = v_sku;

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RETURN v_updated > 0;
  END IF;

  UPDATE public.products AS p
  SET
    gallery_slots = v_slots,
    updated_at = now()
  WHERE p.id::text = v_id;

  RETURN FOUND;
END;
$$;

COMMENT ON FUNCTION public.admin_set_product_gallery_slots(text, jsonb, text) IS
  'Админка: нормализует 4 слота и пишет gallery_slots всем products с тем же SKU (lower trim); пустой SKU — только p_product_id.';

-- ---------------------------------------------------------------------------
-- Поиск фото по SKU: gallery_slots свежей карточки этого SKU
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.find_product_images_by_sku(p_sku text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sku text := lower(btrim(COALESCE(p_sku, '')));
  v_images text[] := ARRAY[]::text[];
  v_seen text[] := ARRAY[]::text[];
  v_row record;
  v_url text;
  v_elem text;
  v_add jsonb;
  v_i int;
  v_primary_row public.products%ROWTYPE;
  v_slots jsonb;
BEGIN
  IF v_sku = '' THEN
    RETURN jsonb_build_object(
      'ok', true,
      'images', '[]'::jsonb,
      'gallery_slots', public._product_gallery_slots_normalize('[]'::jsonb)
    );
  END IF;

  SELECT p.*
  INTO v_primary_row
  FROM public.products AS p
  WHERE lower(btrim(p.sku)) = v_sku
  ORDER BY p.updated_at DESC NULLS LAST, p.id DESC
  LIMIT 1;

  IF FOUND THEN
    v_slots := public._product_gallery_slots_from_row(v_primary_row);
  ELSE
    v_slots := public._product_gallery_slots_normalize('[]'::jsonb);
  END IF;

  FOR v_row IN
    SELECT
      p.image_url,
      p.additional_images
    FROM public.products AS p
    WHERE lower(btrim(p.sku)) = v_sku
    ORDER BY p.updated_at DESC NULLS LAST, p.id DESC
  LOOP
    v_url := NULLIF(btrim(COALESCE(v_row.image_url, '')), '');
    IF v_url IS NOT NULL THEN
      IF NOT (v_url = ANY (v_seen)) THEN
        v_seen := array_append(v_seen, v_url);
        v_images := array_append(v_images, v_url);
      END IF;
    END IF;

    v_add := CASE
      WHEN v_row.additional_images IS NULL THEN '[]'::jsonb
      ELSE to_jsonb(v_row.additional_images)
    END;

    IF jsonb_typeof(v_add) = 'array' AND jsonb_array_length(v_add) > 0 THEN
      FOR v_i IN 0 .. jsonb_array_length(v_add) - 1 LOOP
        v_elem := NULLIF(btrim(v_add ->> v_i), '');
        IF v_elem IS NOT NULL AND NOT (v_elem = ANY (v_seen)) THEN
          v_seen := array_append(v_seen, v_elem);
          v_images := array_append(v_images, v_elem);
        END IF;
      END LOOP;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'images', COALESCE(to_jsonb(v_images), '[]'::jsonb),
    'gallery_slots', v_slots
  );
END;
$$;

COMMENT ON FUNCTION public.find_product_images_by_sku(text) IS
  'Админка: URL фото по SKU + gallery_slots самой свежей строки (updated_at DESC, id DESC).';

REVOKE ALL ON FUNCTION public.admin_set_product_gallery_slots(text, jsonb, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.find_product_images_by_sku(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_set_product_gallery_slots(text, jsonb, text)
  TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.find_product_images_by_sku(text)
  TO anon, authenticated, service_role;