-- Удаление черновика приёмки по products.id (text) с диагностикой; fallback по sku.
-- Контракт Flutter: delete_draft_product + delete_draft_product_by_sku (legacy boolean).

BEGIN;

CREATE OR REPLACE FUNCTION public.delete_draft_product(
  p_id text DEFAULT NULL,
  p_sku text DEFAULT NULL,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id   text;
  v_sku  text;
  v_row  public.products%ROWTYPE;
BEGIN
  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Нет прав администратора');
  END IF;

  v_id := NULLIF(btrim(COALESCE(p_id, '')), '');
  v_sku := NULLIF(btrim(COALESCE(p_sku, '')), '');

  IF v_id IS NULL AND v_sku IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите id или sku');
  END IF;

  IF v_id IS NOT NULL THEN
    DELETE FROM public.products
    WHERE id = v_id
      AND stock_quantity = 0
      AND status IN ('hidden', 'active');
  ELSE
    DELETE FROM public.products
    WHERE btrim(sku) = v_sku
      AND stock_quantity = 0
      AND status IN ('hidden', 'active');
  END IF;

  IF FOUND THEN
    RETURN jsonb_build_object('ok', true);
  END IF;

  IF v_id IS NOT NULL THEN
    SELECT * INTO v_row FROM public.products AS p WHERE p.id = v_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'Позиция уже активирована (stock_quantity > 0) или не найдена'
      );
    END IF;
    IF v_row.stock_quantity > 0 THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error',
        'Позиция уже активирована (stock_quantity > 0) или не найдена'
      );
    END IF;
    IF v_row.status NOT IN ('hidden', 'active') THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error',
        format('Статус «%s» не позволяет удалить черновик', v_row.status)
      );
    END IF;
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Позиция уже активирована (stock_quantity > 0) или не найдена'
    );
  END IF;

  SELECT * INTO v_row
  FROM public.products AS p
  WHERE btrim(p.sku) = v_sku
  ORDER BY p.updated_at DESC NULLS LAST
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Позиция уже активирована (stock_quantity > 0) или не найдена'
    );
  END IF;

  IF v_row.stock_quantity > 0 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Позиция уже активирована (stock_quantity > 0) или не найдена'
    );
  END IF;

  IF v_row.status NOT IN ('hidden', 'active') THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error',
      format('Статус «%s» не позволяет удалить черновик', v_row.status)
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', false,
    'error', 'Позиция уже активирована (stock_quantity > 0) или не найдена'
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', SQLERRM,
      'code', SQLSTATE
    );
END;
$$;

COMMENT ON FUNCTION public.delete_draft_product(text, text, text) IS
  'Удаление одного черновика по products.id (приоритет) или sku; jsonb ok/error.';

CREATE OR REPLACE FUNCTION public.delete_draft_product_by_sku(
  p_sku text,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  v_result := public.delete_draft_product(NULL, p_sku, p_admin_email);
  RETURN COALESCE((v_result ->> 'ok')::boolean, false);
END;
$$;

REVOKE ALL ON FUNCTION public.delete_draft_product(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_draft_product_by_sku(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.delete_draft_product(text, text, text)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.delete_draft_product_by_sku(text, text)
  TO anon, authenticated, service_role;

COMMIT;