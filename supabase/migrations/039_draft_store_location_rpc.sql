-- Черновики: store_location может быть NULL («Не выбран»); RPC смены точки при приёмке.

BEGIN;

ALTER TABLE public.products
  ALTER COLUMN store_location DROP NOT NULL;

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_store_location_check;
ALTER TABLE public.products
  ADD CONSTRAINT products_store_location_check
  CHECK (
    store_location IS NULL
    OR store_location IN ('ICN', 'ANS')
  );

COMMENT ON COLUMN public.products.store_location IS
  'Точка: ICN, ANS или NULL (черновик без точки). На витрине при stock > 0 — обычно ICN/ANS.';

-- Активная витрина: пустое значение трактуем как Инчхон
UPDATE public.products AS p
SET store_location = 'ICN'
WHERE p.stock_quantity > 0
  AND (
    p.store_location IS NULL
    OR btrim(COALESCE(p.store_location, '')) = ''
    OR upper(btrim(p.store_location)) NOT IN ('ICN', 'ANS')
  );

CREATE OR REPLACE FUNCTION public.set_draft_product_store_location(
  p_id text,
  p_store_location text DEFAULT NULL,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_loc text;
BEGIN
  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Нет прав администратора');
  END IF;

  IF NULLIF(btrim(COALESCE(p_store_location, '')), '') IS NULL THEN
    v_loc := NULL;
  ELSIF upper(btrim(p_store_location)) IN ('ANS', 'ANSAN', 'АНСАН') THEN
    v_loc := 'ANS';
  ELSIF upper(btrim(p_store_location)) IN ('ICN', 'INCHEON', 'ИНЧХОН') THEN
    v_loc := 'ICN';
  ELSE
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Недопустимая точка. Укажите ICN, ANS или пусто (не выбран)'
    );
  END IF;

  UPDATE public.products AS p
  SET
    store_location = v_loc,
    updated_at = now()
  WHERE p.id = btrim(p_id)
    AND p.stock_quantity = 0
    AND p.status IN ('hidden', 'active');

  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok', true,
      'store_location', v_loc
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', false,
    'error', 'Черновик не найден или уже активирован'
  );
END;
$$;

COMMENT ON FUNCTION public.set_draft_product_store_location(text, text, text) IS
  'Админ: смена store_location у черновика (NULL = не выбран).';

REVOKE ALL ON FUNCTION public.set_draft_product_store_location(text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.set_draft_product_store_location(text, text, text)
  TO anon, authenticated, service_role;

COMMIT;