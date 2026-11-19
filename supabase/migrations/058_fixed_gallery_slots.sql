-- Фиксированные 4 слота галереи (raw_legacy_payload.gallery_slots).

BEGIN;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS raw_legacy_payload jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.products.raw_legacy_payload IS
  'Служебный JSON: gallery_slots — массив из 4 URL (или null) по индексам 0..3.';

-- ---------------------------------------------------------------------------
-- Канонический ключ URL (без query) для дедупликации
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._gallery_url_canonical(p_url text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(
    btrim(
      split_part(COALESCE(p_url, ''), '?', 1)
    ),
    ''
  );
$$;

-- ---------------------------------------------------------------------------
-- Нормализация jsonb-массива слотов → ровно 4 элемента (null | text)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._product_gallery_slots_normalize(p_slots jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_out jsonb := '[]'::jsonb;
  v_i int;
  v_elem text;
BEGIN
  FOR v_i IN 0..3 LOOP
    v_elem := NULL;
    IF p_slots IS NOT NULL
      AND jsonb_typeof(p_slots) = 'array'
      AND jsonb_array_length(p_slots) > v_i THEN
      IF jsonb_typeof(p_slots -> v_i) = 'null' THEN
        v_elem := NULL;
      ELSE
        v_elem := NULLIF(btrim(p_slots ->> v_i), '');
      END IF;
    END IF;
    v_out := v_out || jsonb_build_array(
      CASE WHEN v_elem IS NULL THEN jsonb 'null' ELSE to_jsonb(v_elem) END
    );
  END LOOP;
  RETURN v_out;
END;
$$;

-- Упорядоченный список URL для витрины: все непустые слоты 0→3
CREATE OR REPLACE FUNCTION public._product_vitrine_urls_from_slots(p_slots jsonb)
RETURNS text[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_norm jsonb;
  v_i int;
  v_elem text;
  v_urls text[] := ARRAY[]::text[];
BEGIN
  v_norm := public._product_gallery_slots_normalize(p_slots);
  FOR v_i IN 0..3 LOOP
  BEGIN
    IF jsonb_typeof(v_norm -> v_i) = 'null' THEN
      CONTINUE;
    END IF;
    v_elem := NULLIF(btrim(v_norm ->> v_i), '');
    IF v_elem IS NULL THEN
      CONTINUE;
    END IF;
    v_urls := array_append(v_urls, v_elem);
  END;
  END LOOP;
  RETURN v_urls;
END;
$$;

CREATE OR REPLACE FUNCTION public._product_first_image_from_slots(p_slots jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_norm jsonb;
  v_i int;
  v_elem text;
BEGIN
  v_norm := public._product_gallery_slots_normalize(p_slots);
  FOR v_i IN 0..3 LOOP
    IF jsonb_typeof(v_norm -> v_i) = 'null' THEN
      CONTINUE;
    END IF;
    v_elem := NULLIF(btrim(v_norm ->> v_i), '');
    IF v_elem IS NOT NULL THEN
      RETURN v_elem;
    END IF;
  END LOOP;
  RETURN NULL;
END;
$$;

-- Заполнить слоты 0..3 из упорядоченного списка URL (дедуп по canonical path)
CREATE OR REPLACE FUNCTION public._product_gallery_slots_init_from_urls(p_urls text[])
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_slots jsonb := '[]'::jsonb;
  v_seen text[] := ARRAY[]::text[];
  v_url text;
  v_canon text;
  v_filled int := 0;
  v_i int;
BEGIN
  FOR v_i IN 1..COALESCE(array_length(p_urls, 1), 0) LOOP
    EXIT WHEN v_filled >= 4;
    v_url := NULLIF(btrim(p_urls[v_i]), '');
    IF v_url IS NULL THEN
      CONTINUE;
    END IF;
    v_canon := public._gallery_url_canonical(v_url);
    IF v_canon IS NOT NULL AND v_canon = ANY (v_seen) THEN
      CONTINUE;
    END IF;
    IF v_canon IS NOT NULL THEN
      v_seen := array_append(v_seen, v_canon);
    END IF;
    v_slots := v_slots || jsonb_build_array(to_jsonb(v_url));
    v_filled := v_filled + 1;
  END LOOP;
  WHILE v_filled < 4 LOOP
    v_slots := v_slots || jsonb_build_array('null'::jsonb);
    v_filled := v_filled + 1;
  END LOOP;
  RETURN public._product_gallery_slots_normalize(v_slots);
END;
$$;

CREATE OR REPLACE FUNCTION public._product_gallery_slots_from_row(p_row public.products)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_payload jsonb;
  v_slots jsonb;
  v_merged text[];
BEGIN
  v_payload := COALESCE(p_row.raw_legacy_payload, '{}'::jsonb);
  IF v_payload ? 'gallery_slots'
    AND jsonb_typeof(v_payload -> 'gallery_slots') = 'array' THEN
    RETURN public._product_gallery_slots_normalize(v_payload -> 'gallery_slots');
  END IF;

  v_merged := public._product_gallery_urls_merged(
    p_row.image_url,
    p_row.images,
    p_row.additional_images
  );
  RETURN public._product_gallery_slots_init_from_urls(v_merged);
END;
$$;

-- ---------------------------------------------------------------------------
-- Триггер: при gallery_slots — витрина из слотов; иначе legacy merge
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_products_sync_gallery_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_payload jsonb;
  v_slots jsonb;
  v_urls text[];
  v_norm public.products;
BEGIN
  v_payload := COALESCE(NEW.raw_legacy_payload, '{}'::jsonb);
  IF v_payload ? 'gallery_slots'
    AND jsonb_typeof(v_payload -> 'gallery_slots') = 'array' THEN
    v_slots := public._product_gallery_slots_normalize(v_payload -> 'gallery_slots');
    NEW.raw_legacy_payload :=
      jsonb_set(v_payload, '{gallery_slots}', v_slots, true);
    v_urls := public._product_vitrine_urls_from_slots(v_slots);
    NEW.images := v_urls;
    NEW.additional_images := v_urls;
    NEW.image_url := public._product_first_image_from_slots(v_slots);
    RETURN NEW;
  END IF;

  v_norm := public._product_apply_gallery_fields(NEW);
  NEW.images := v_norm.images;
  NEW.additional_images := v_norm.additional_images;
  NEW.image_url := v_norm.image_url;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS products_sync_gallery_fields ON public.products;

CREATE TRIGGER products_sync_gallery_fields
  BEFORE INSERT OR UPDATE OF image_url, images, additional_images, raw_legacy_payload
  ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_products_sync_gallery_fields();

-- ---------------------------------------------------------------------------
-- RPC: контекст галереи по product id (для дублей SKU)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_product_gallery_context_by_id(
  p_product_id text,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id text := btrim(COALESCE(p_product_id, ''));
  v_row public.products%ROWTYPE;
  v_slots jsonb;
  v_urls text[];
BEGIN
  IF v_id = '' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_id');
  END IF;
  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'forbidden');
  END IF;

  SELECT p.* INTO v_row FROM public.products AS p WHERE p.id = v_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  v_slots := public._product_gallery_slots_from_row(v_row);
  v_urls := public._product_vitrine_urls_from_slots(v_slots);

  RETURN jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'sku', v_row.sku,
    'gallery_slots', v_slots,
    'additional_images', COALESCE(to_jsonb(v_urls), '[]'::jsonb),
    'images', COALESCE(to_jsonb(v_urls), '[]'::jsonb),
    'image_url', public._product_first_image_from_slots(v_slots)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_product_gallery_context_by_sku(
  p_sku text,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sku text := btrim(COALESCE(p_sku, ''));
  v_row public.products%ROWTYPE;
  v_slots jsonb;
  v_urls text[];
BEGIN
  IF v_sku = '' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_sku');
  END IF;
  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'forbidden');
  END IF;

  SELECT p.*
  INTO v_row
  FROM public.products AS p
  WHERE p.sku = v_sku
  ORDER BY p.updated_at DESC NULLS LAST
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  v_slots := public._product_gallery_slots_from_row(v_row);
  v_urls := public._product_vitrine_urls_from_slots(v_slots);

  RETURN jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'sku', v_row.sku,
    'gallery_slots', v_slots,
    'additional_images', COALESCE(to_jsonb(v_urls), '[]'::jsonb),
    'images', COALESCE(to_jsonb(v_urls), '[]'::jsonb),
    'image_url', public._product_first_image_from_slots(v_slots)
  );
END;
$$;

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
  v_slots jsonb;
  v_payload jsonb;
  v_urls text[];
BEGIN
  IF v_id = '' THEN
    RETURN false;
  END IF;
  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN false;
  END IF;

  v_slots := public._product_gallery_slots_normalize(p_gallery_slots);
  v_urls := public._product_vitrine_urls_from_slots(v_slots);

  SELECT COALESCE(p.raw_legacy_payload, '{}'::jsonb)
  INTO v_payload
  FROM public.products AS p
  WHERE p.id = v_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  v_payload := jsonb_set(v_payload, '{gallery_slots}', v_slots, true);

  UPDATE public.products AS p
  SET
    raw_legacy_payload = v_payload,
    additional_images = v_urls,
    images = v_urls,
    image_url = public._product_first_image_from_slots(v_slots),
    updated_at = now()
  WHERE p.id = v_id;

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_product_additional_images(
  p_product_id text,
  p_additional_images jsonb,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id text := btrim(COALESCE(p_product_id, ''));
  v_images jsonb;
  v_urls text[];
  v_slots jsonb;
  v_payload jsonb;
BEGIN
  IF v_id = '' THEN
    RETURN false;
  END IF;
  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN false;
  END IF;

  v_images := COALESCE(p_additional_images, '[]'::jsonb);
  IF jsonb_typeof(v_images) IS DISTINCT FROM 'array' THEN
    v_images := '[]'::jsonb;
  END IF;

  v_urls := public._product_gallery_urls_from_payload(
    jsonb_build_object('additional_images', v_images)
  );
  v_slots := public._product_gallery_slots_init_from_urls(v_urls);

  SELECT COALESCE(p.raw_legacy_payload, '{}'::jsonb)
  INTO v_payload
  FROM public.products AS p
  WHERE p.id = v_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  v_payload := jsonb_set(v_payload, '{gallery_slots}', v_slots, true);

  UPDATE public.products AS p
  SET
    raw_legacy_payload = v_payload,
    additional_images = v_urls,
    images = v_urls,
    image_url = public._product_first_image_from_slots(v_slots),
    updated_at = now()
  WHERE p.id = v_id;

  RETURN FOUND;
END;
$$;

-- Бэкфилл gallery_slots для существующих карточек
UPDATE public.products AS p
SET
  raw_legacy_payload = jsonb_set(
    COALESCE(p.raw_legacy_payload, '{}'::jsonb),
    '{gallery_slots}',
    public._product_gallery_slots_init_from_urls(
      public._product_gallery_urls_merged(
        p.image_url,
        p.images,
        p.additional_images
      )
    ),
    true
  )
WHERE NOT (
  COALESCE(p.raw_legacy_payload, '{}'::jsonb) ? 'gallery_slots'
  AND jsonb_typeof(p.raw_legacy_payload -> 'gallery_slots') = 'array'
  AND jsonb_array_length(p.raw_legacy_payload -> 'gallery_slots') = 4
);

UPDATE public.products AS p
SET updated_at = p.updated_at
WHERE COALESCE(p.raw_legacy_payload, '{}'::jsonb) ? 'gallery_slots';

REVOKE ALL ON FUNCTION public.admin_get_product_gallery_context_by_id(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_set_product_gallery_slots(text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_get_product_gallery_context_by_id(text, text)
  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_product_gallery_slots(text, jsonb, text)
  TO anon, authenticated;

REVOKE ALL ON FUNCTION public.admin_set_product_additional_images(text, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_product_additional_images(text, jsonb, text)
  TO anon, authenticated;

REVOKE ALL ON FUNCTION public.admin_get_product_gallery_context_by_sku(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_product_gallery_context_by_sku(text, text)
  TO anon, authenticated;

COMMIT;