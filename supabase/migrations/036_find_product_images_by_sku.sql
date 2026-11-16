-- Dr. Jewelry — поиск URL галереи по артикулу (все статусы) для ручного добавления.

BEGIN;

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
  v_has_photo boolean;
BEGIN
  IF v_sku = '' THEN
    RETURN jsonb_build_object('ok', true, 'images', '[]'::jsonb);
  END IF;

  FOR v_row IN
    SELECT
      p.image_url,
      p.additional_images
    FROM public.products AS p
    WHERE lower(btrim(p.sku)) = v_sku
    ORDER BY p.updated_at DESC NULLS LAST, p.created_at DESC NULLS LAST
  LOOP
    v_has_photo := false;

    v_url := NULLIF(btrim(COALESCE(v_row.image_url, '')), '');
    IF v_url IS NOT NULL THEN
      v_has_photo := true;
      IF NOT (v_url = ANY(v_seen)) THEN
        v_seen := array_append(v_seen, v_url);
        v_images := array_append(v_images, v_url);
      END IF;
    END IF;

    v_add := CASE
      WHEN v_row.additional_images IS NULL THEN '[]'::jsonb
      ELSE to_jsonb(v_row.additional_images)
    END;

    IF jsonb_typeof(v_add) = 'array' AND jsonb_array_length(v_add) > 0 THEN
      v_has_photo := true;
      FOR v_i IN 0 .. jsonb_array_length(v_add) - 1 LOOP
        v_elem := NULLIF(btrim(v_add ->> v_i), '');
        IF v_elem IS NOT NULL AND NOT (v_elem = ANY(v_seen)) THEN
          v_seen := array_append(v_seen, v_elem);
          v_images := array_append(v_images, v_elem);
        END IF;
      END LOOP;
    END IF;

    IF NOT v_has_photo THEN
      CONTINUE;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'images', COALESCE(to_jsonb(v_images), '[]'::jsonb)
  );
END;
$$;

COMMENT ON FUNCTION public.find_product_images_by_sku(text) IS
  'Админка: уникальные URL фото по SKU (любой status), порядок по свежести карточек.';

REVOKE ALL ON FUNCTION public.find_product_images_by_sku(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.find_product_images_by_sku(text) TO anon, authenticated, service_role;

COMMIT;