-- Dr. Jewelry — 046: product_transfers status CHECK, list_product_transfers + product photo.

BEGIN;

-- ---------------------------------------------------------------------------
-- Статусы product_transfers (legacy + приложение)
-- ---------------------------------------------------------------------------
ALTER TABLE public.product_transfers
  DROP CONSTRAINT IF EXISTS product_transfers_status_check;

ALTER TABLE public.product_transfers
  ADD CONSTRAINT product_transfers_status_check
  CHECK (
    status IS NULL
    OR lower(btrim(status)) IN (
      'in_transit',
      'pending',
      'sent',
      'completed',
      'received',
      'cancelled',
      'canceled'
    )
    OR btrim(status) IN ('в пути', 'В пути')
  );

-- ---------------------------------------------------------------------------
-- Первое фото и наименование товара для UI трансферов
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._product_first_image_url(p_row public.products)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_url text;
  v_json jsonb;
BEGIN
  IF p_row.id IS NULL THEN
    RETURN NULL;
  END IF;

  v_url := NULLIF(btrim(coalesce(p_row.image_url, '')), '');
  IF v_url IS NOT NULL THEN
    RETURN v_url;
  END IF;

  IF p_row.additional_images IS NULL THEN
    RETURN NULL;
  END IF;

  IF jsonb_typeof(to_jsonb(p_row.additional_images)) = 'array' THEN
    v_json := to_jsonb(p_row.additional_images);
    IF jsonb_array_length(v_json) > 0 THEN
      RETURN NULLIF(btrim(v_json ->> 0), '');
    END IF;
  END IF;

  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._product_display_name_ru(p_row public.products)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  IF p_row.id IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN NULLIF(
    btrim(
      coalesce(
        p_row.name ->> 'ru',
        p_row.name ->> 'ko',
        p_row.name ->> 'en',
        ''
      )
    ),
    ''
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.list_product_transfers(
  p_status text DEFAULT NULL,
  p_store text DEFAULT NULL
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text := NULLIF(lower(btrim(coalesce(p_status, ''))), '');
  v_store text := public._norm_store_icn_ans(p_store);
BEGIN
  RETURN QUERY
  SELECT
    to_jsonb(t.*) || jsonb_build_object(
      'image_url', public._product_first_image_url(p),
      'product_name', public._product_display_name_ru(p)
    )
  FROM public.product_transfers AS t
  LEFT JOIN public.products AS p
    ON p.id::text = t.product_id::text
  WHERE (
      v_status IS NULL
      OR (
        v_status = 'in_transit'
        AND public._transfer_status_is_open(t.status)
      )
      OR (
        v_status IS DISTINCT FROM 'in_transit'
        AND (lower(t.status) = v_status OR t.status = p_status)
      )
    )
    AND (
      v_store IS NULL
      OR t.to_store = v_store
      OR t.from_store = v_store
    )
  ORDER BY t.created_at DESC NULLS LAST, t.id DESC;
END;
$$;

COMMIT;