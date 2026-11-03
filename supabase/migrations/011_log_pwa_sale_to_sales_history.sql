-- Dr. Jewelry — автологирование PWA-продаж в sales_history (без изменений Flutter).
-- Срабатывает на UPDATE products (в т.ч. RPC reserve_product_for_checkout).
--
-- Контракт products (001/002/003): sale_price, stock_quantity, status, image_url, sku, id (text).

BEGIN;

-- Колонка для отличия органических продаж от ETL (если ещё не добавлена при создании таблицы).
ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS source_system text;

COMMENT ON COLUMN public.sales_history.source_system IS
  'DrJaw — исторический импорт; pwa_store — продажа через приложение (триггер trg_log_pwa_sale).';

CREATE OR REPLACE FUNCTION public.log_future_sale_to_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_legacy_id   text;
  v_image_url   text;
  v_price_krw   bigint;
  v_payload     jsonb;
  v_sold_at_utc timestamptz;
  v_sold_kst    date;
BEGIN
  IF NOT (
    (NEW.stock_quantity = 0 AND COALESCE(OLD.stock_quantity, 0) > 0)
    OR (NEW.status = 'sold' AND OLD.status IS DISTINCT FROM 'sold')
  ) THEN
    RETURN NEW;
  END IF;

  v_legacy_id := 'pwa_id_' || NEW.id;
  v_sold_at_utc := timezone('utc', now());
  v_sold_kst := (timezone('Asia/Seoul', now()))::date;
  v_payload := row_to_json(NEW)::jsonb;

  v_price_krw := COALESCE(NEW.sale_price, 0)::bigint;

  v_image_url := NULLIF(btrim(COALESCE(NEW.image_url, '')), '');
  IF v_image_url IS NULL
     AND v_payload ? 'additional_images'
     AND jsonb_typeof(v_payload -> 'additional_images') = 'array'
     AND jsonb_array_length(v_payload -> 'additional_images') > 0
  THEN
    v_image_url := NULLIF(btrim(v_payload -> 'additional_images' ->> 0), '');
  END IF;

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
    v_legacy_id,
    NEW.sku,
    v_price_krw,
    v_sold_at_utc,
    v_sold_kst,
    v_image_url,
    'success',
    '00000000-0000-0000-0000-000000000000'::uuid,
    'pwa_store',
    v_payload,
    jsonb_build_object(
      'source_system', 'pwa_store',
      'logged_by', 'trg_log_pwa_sale',
      'sold_at_utc', v_sold_at_utc,
      'sold_date_kst', v_sold_kst::text
    )
  )
  ON CONFLICT (legacy_id) DO NOTHING;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.log_future_sale_to_history() IS
  'AFTER UPDATE на products: stock 0←> или status→sold → INSERT sales_history (идемпотентно по legacy_id).';

DROP TRIGGER IF EXISTS trg_log_pwa_sale ON public.products;

CREATE TRIGGER trg_log_pwa_sale
  AFTER UPDATE ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.log_future_sale_to_history();

COMMIT;
