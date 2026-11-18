-- Dr. Jewelry — 047: безвозвратное удаление изделия с витрины (не hidden).
-- Связи: product_transfers.product_id (text, без FK), sales_history.product_id (text, без FK).
-- Запрет: status sold/reserved и любая строка sales_history по product_id.

BEGIN;

CREATE OR REPLACE FUNCTION public.delete_product_permanently(
  p_product_id text,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id text := NULLIF(btrim(coalesce(p_product_id, '')), '');
  v_row public.products%ROWTYPE;
  v_xfer_deleted integer := 0;
  v_sales_rows integer := 0;
BEGIN
  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Нет прав администратора');
  END IF;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите id изделия');
  END IF;

  SELECT * INTO v_row
  FROM public.products AS p
  WHERE p.id::text = v_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Изделие не найдено');
  END IF;

  IF lower(btrim(coalesce(v_row.status, ''))) IN ('sold', 'reserved') THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', format(
        'Нельзя удалить: товар в статусе «%s». Используйте архив продаж.',
        v_row.status
      )
    );
  END IF;

  SELECT count(*)::integer
  INTO v_sales_rows
  FROM public.sales_history AS sh
  WHERE sh.product_id::text = v_id;

  IF v_sales_rows > 0 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error',
      format(
        'Нельзя удалить: есть %s записей в истории продаж (sales_history) по этому id.',
        v_sales_rows
      )
    );
  END IF;

  DELETE FROM public.product_transfers AS t
  WHERE t.product_id::text = v_id;

  GET DIAGNOSTICS v_xfer_deleted = ROW_COUNT;

  DELETE FROM public.products AS p
  WHERE p.id::text = v_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Удаление не выполнено');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'id', v_id,
    'sku', v_row.sku,
    'transfers_removed', coalesce(v_xfer_deleted, 0)
  );
EXCEPTION
  WHEN foreign_key_violation THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error',
      'Нельзя удалить: есть связанные записи в других таблицах (FK). ' || SQLERRM
    );
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', SQLERRM,
      'code', SQLSTATE
    );
END;
$$;

COMMENT ON FUNCTION public.delete_product_permanently(text, text) IS
  'Безвозвратное DELETE products по id; снимает product_transfers; блок при sold/reserved и sales_history.';

REVOKE ALL ON FUNCTION public.delete_product_permanently(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_product_permanently(text, text)
  TO anon, authenticated, service_role;

COMMIT;