-- Dr. Jewelry — частичный возврат: сторно в sales_history + active на витрине.

BEGIN;

CREATE OR REPLACE FUNCTION public.process_product_return_manual(
  p_sku text,
  p_admin_email text DEFAULT 'dr.jewelry.korea@gmail.com'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sku            text;
  v_product_id     text;
  v_product_status text;
  v_stock          integer;
  v_sale           record;
  v_return_legacy text;
  v_reversal_id   uuid;
  v_sold_kst      date;
  v_sold_utc      timestamptz;
BEGIN
  v_sku := NULLIF(btrim(p_sku), '');
  IF v_sku IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'empty_sku');
  END IF;

  IF p_admin_email IS DISTINCT FROM 'dr.jewelry.korea@gmail.com' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  SELECT p.id, p.status, COALESCE(p.stock_quantity, 0)
  INTO v_product_id, v_product_status, v_stock
  FROM public.products AS p
  WHERE p.sku = v_sku
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'product_not_found');
  END IF;

  IF v_product_status IS DISTINCT FROM 'sold' AND v_stock > 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'product_not_sold');
  END IF;

  SELECT sh.*
  INTO v_sale
  FROM public.sales_history AS sh
  WHERE sh.sku = v_sku
    AND sh.price_krw > 0
    AND NOT EXISTS (
      SELECT 1
      FROM public.sales_history AS r
      WHERE (r.migration_meta ->> 'reverses_legacy_id') = sh.legacy_id
        AND COALESCE(r.migration_meta ->> 'type', '') = 'return'
    )
  ORDER BY sh.sold_at_utc DESC NULLS LAST, sh.legacy_id DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sale_not_found');
  END IF;

  v_return_legacy := 'return_' || v_sale.legacy_id;

  IF EXISTS (
    SELECT 1 FROM public.sales_history WHERE legacy_id = v_return_legacy
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_returned');
  END IF;

  v_sold_utc := timezone('utc', now());
  v_sold_kst := COALESCE(v_sale.sold_date_kst, (timezone('Asia/Seoul', now()))::date);

  INSERT INTO public.sales_history (
    legacy_id,
    sku,
    price_krw,
    sold_at_utc,
    sold_date_kst,
    image_url,
    photo_status,
    import_batch_id,
    source_system,
    raw_legacy_payload,
    migration_meta
  )
  VALUES (
    v_return_legacy,
    v_sale.sku,
    (-1) * v_sale.price_krw,
    v_sold_utc,
    v_sold_kst,
    v_sale.image_url,
    COALESCE(v_sale.photo_status, 'success'),
    v_sale.import_batch_id,
    'pwa_store',
    jsonb_build_object('type', 'return', 'original_payload', v_sale.raw_legacy_payload),
    jsonb_build_object(
      'type', 'return',
      'reverses_legacy_id', v_sale.legacy_id,
      'processed_by', 'process_product_return_manual',
      'returned_at_utc', v_sold_utc
    )
  )
  RETURNING id INTO v_reversal_id;

  UPDATE public.products
  SET
    status = 'active',
    stock_quantity = 1,
    updated_at = now()
  WHERE id = v_product_id;

  RETURN jsonb_build_object(
    'ok', true,
    'sku', v_sku,
    'product_id', v_product_id,
    'reversal_id', v_reversal_id::text,
    'reversal_legacy_id', v_return_legacy,
    'price_krw', (-1) * v_sale.price_krw,
    'sold_date_kst', v_sold_kst::text,
    'reverses_legacy_id', v_sale.legacy_id
  );
END;
$$;

COMMENT ON FUNCTION public.process_product_return_manual(text, text) IS
  'Возврат на витрину: сторно sales_history (price_krw < 0), products status=active stock=1.';

REVOKE ALL ON FUNCTION public.process_product_return_manual(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_product_return_manual(text, text) TO anon, authenticated;

COMMIT;
