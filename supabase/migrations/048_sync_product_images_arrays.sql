-- Синхронизация image_url, images (text[]) и additional_images (text[]) для галереи витрины.

BEGIN;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS images text[] NOT NULL DEFAULT '{}'::text[];

COMMENT ON COLUMN public.products.images IS
  'Публичные URL галереи (до 4). Дублируются в additional_images; image_url = первый кадр.';

-- ---------------------------------------------------------------------------
-- Объединение URL из трёх полей (порядок, дедуп, макс. 4)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._product_gallery_urls_merged(
  p_image_url text,
  p_images text[],
  p_additional text[]
)
RETURNS text[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_urls text[] := ARRAY[]::text[];
  v_url text;
  v_elem text;
BEGIN
  v_url := NULLIF(btrim(COALESCE(p_image_url, '')), '');
  IF v_url IS NOT NULL AND NOT (v_url = ANY (v_urls)) THEN
    v_urls := array_append(v_urls, v_url);
  END IF;

  IF p_images IS NOT NULL THEN
    FOREACH v_elem IN ARRAY p_images LOOP
      v_elem := NULLIF(btrim(COALESCE(v_elem, '')), '');
      IF v_elem IS NULL OR v_elem = ANY (v_urls) THEN
        CONTINUE;
      END IF;
      v_urls := array_append(v_urls, v_elem);
      IF array_length(v_urls, 1) >= 4 THEN
        RETURN v_urls;
      END IF;
    END LOOP;
  END IF;

  IF p_additional IS NOT NULL THEN
    FOREACH v_elem IN ARRAY p_additional LOOP
      v_elem := NULLIF(btrim(COALESCE(v_elem, '')), '');
      IF v_elem IS NULL OR v_elem = ANY (v_urls) THEN
        CONTINUE;
      END IF;
      v_urls := array_append(v_urls, v_elem);
      IF array_length(v_urls, 1) >= 4 THEN
        RETURN v_urls;
      END IF;
    END LOOP;
  END IF;

  RETURN v_urls;
END;
$$;

CREATE OR REPLACE FUNCTION public._product_gallery_urls_from_payload(p_payload jsonb)
RETURNS text[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_images text[];
  v_additional text[];
BEGIN
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RETURN ARRAY[]::text[];
  END IF;

  v_additional := ARRAY[]::text[];
  IF p_payload ? 'additional_images' AND jsonb_typeof(p_payload -> 'additional_images') = 'array' THEN
    SELECT COALESCE(array_agg(NULLIF(btrim(elem), '')), ARRAY[]::text[])
    INTO v_additional
    FROM jsonb_array_elements_text(p_payload -> 'additional_images') AS elem
    WHERE NULLIF(btrim(elem), '') IS NOT NULL;
  END IF;

  v_images := ARRAY[]::text[];
  IF p_payload ? 'images' AND jsonb_typeof(p_payload -> 'images') = 'array' THEN
    SELECT COALESCE(array_agg(NULLIF(btrim(elem), '')), ARRAY[]::text[])
    INTO v_images
    FROM jsonb_array_elements_text(p_payload -> 'images') AS elem
    WHERE NULLIF(btrim(elem), '') IS NOT NULL;
  END IF;

  RETURN public._product_gallery_urls_merged(
    p_payload ->> 'image_url',
    v_images,
    v_additional
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._product_apply_gallery_fields(p_row public.products)
RETURNS public.products
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_urls text[];
  v_out public.products;
BEGIN
  v_out := p_row;
  v_urls := public._product_gallery_urls_merged(
    p_row.image_url,
    p_row.images,
    p_row.additional_images
  );
  v_out.images := v_urls;
  v_out.additional_images := v_urls;
  IF array_length(v_urls, 1) IS NOT NULL AND array_length(v_urls, 1) > 0 THEN
    v_out.image_url := v_urls[1];
  ELSE
    v_out.image_url := NULL;
  END IF;
  RETURN v_out;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_products_sync_gallery_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_norm public.products;
BEGIN
  v_norm := public._product_apply_gallery_fields(NEW);
  NEW.images := v_norm.images;
  NEW.additional_images := v_norm.additional_images;
  NEW.image_url := v_norm.image_url;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS products_sync_gallery_fields ON public.products;

CREATE TRIGGER products_sync_gallery_fields
  BEFORE INSERT OR UPDATE OF image_url, images, additional_images
  ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_products_sync_gallery_fields();

-- ---------------------------------------------------------------------------
-- Бэкфилл существующих строк
-- ---------------------------------------------------------------------------
UPDATE public.products AS p
SET
  images = g.urls,
  additional_images = g.urls,
  image_url = CASE
    WHEN array_length(g.urls, 1) IS NOT NULL AND array_length(g.urls, 1) > 0 THEN g.urls[1]
    ELSE NULL
  END
FROM (
  SELECT
    pr.id,
    public._product_gallery_urls_merged(
      pr.image_url,
      pr.images,
      pr.additional_images
    ) AS urls
  FROM public.products AS pr
) AS g
WHERE p.id = g.id
  AND (
    p.images IS DISTINCT FROM g.urls
    OR p.image_url IS DISTINCT FROM (
      CASE
        WHEN array_length(g.urls, 1) IS NOT NULL AND array_length(g.urls, 1) > 0 THEN g.urls[1]
        ELSE NULL
      END
    )
    OR p.additional_images IS DISTINCT FROM g.urls
  );

-- ---------------------------------------------------------------------------
-- RPC: админ-галерея
-- ---------------------------------------------------------------------------
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

  v_urls := public._product_gallery_urls_merged(
    v_row.image_url,
    v_row.images,
    v_row.additional_images
  );

  RETURN jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'additional_images', COALESCE(to_jsonb(v_urls), '[]'::jsonb),
    'images', COALESCE(to_jsonb(v_urls), '[]'::jsonb),
    'image_url', CASE
      WHEN array_length(v_urls, 1) IS NOT NULL AND array_length(v_urls, 1) > 0 THEN v_urls[1]
      ELSE v_row.image_url
    END
  );
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

  UPDATE public.products
  SET
    additional_images = v_urls,
    images = v_urls,
    image_url = CASE
      WHEN array_length(v_urls, 1) IS NOT NULL AND array_length(v_urls, 1) > 0 THEN v_urls[1]
      ELSE NULL
    END,
    updated_at = now()
  WHERE id = v_id;

  RETURN FOUND;
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC: update_draft_product — учёт images + additional_images
-- ---------------------------------------------------------------------------
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
  v_urls text[];
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

  v_urls := public._product_gallery_urls_from_payload(p_payload);

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
    additional_images = v_urls,
    images = v_urls,
    image_url = CASE
      WHEN array_length(v_urls, 1) IS NOT NULL AND array_length(v_urls, 1) > 0 THEN v_urls[1]
      ELSE NULL
    END,
    status = 'hidden',
    stock_quantity = 0,
    updated_at = now()
  WHERE p.id = v_id;

  RETURN jsonb_build_object('ok', true, 'id', v_id, 'sku', v_sku);
END;
$$;

-- Первое фото: учитываем images[]
CREATE OR REPLACE FUNCTION public._product_first_image_url(p_row public.products)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_urls text[];
BEGIN
  IF p_row.id IS NULL THEN
    RETURN NULL;
  END IF;

  v_urls := public._product_gallery_urls_merged(
    p_row.image_url,
    p_row.images,
    p_row.additional_images
  );

  IF array_length(v_urls, 1) IS NOT NULL AND array_length(v_urls, 1) > 0 THEN
    RETURN v_urls[1];
  END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_product_gallery_context_by_sku(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_set_product_additional_images(text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_get_product_gallery_context_by_sku(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_product_additional_images(text, jsonb, text) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.update_draft_product(jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_draft_product(jsonb, text)
  TO anon, authenticated, service_role;

COMMIT;