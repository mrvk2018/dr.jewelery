-- Dr. Jewelry — загрузка галереи для hidden/active (обход SELECT/UPDATE RLS на products).

BEGIN;

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

  RETURN jsonb_build_object(
    'ok', true,
    'id', v_row.id,
    'additional_images', COALESCE(v_row.additional_images, '[]'::jsonb),
    'image_url', v_row.image_url
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
  v_first text;
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

  IF jsonb_array_length(v_images) > 0 THEN
    v_first := btrim(v_images ->> 0);
  ELSE
    v_first := NULL;
  END IF;

  UPDATE public.products
  SET
    additional_images = v_images,
    image_url = NULLIF(v_first, ''),
    updated_at = now()
  WHERE id = v_id;

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_product_gallery_context_by_sku(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_set_product_additional_images(text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_get_product_gallery_context_by_sku(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_product_additional_images(text, jsonb, text) TO anon, authenticated;

COMMIT;
