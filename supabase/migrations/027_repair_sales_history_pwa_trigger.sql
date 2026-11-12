-- Прод-ремонт: sales_history + trg_log_pwa_sale + product_id + backfill sold products.
-- Идемпотентно для ручного запуска в SQL Editor.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Таблица sales_history (если создана только ETL — дозаполнить колонки)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sales_history (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legacy_id           text NOT NULL,
  sku                 text,
  price_krw           bigint,
  sold_at_utc         timestamptz,
  sold_date_kst       date,
  image_url           text,
  photo_status        text,
  import_batch_id     uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
  raw_legacy_payload  jsonb,
  migration_meta      jsonb DEFAULT '{}'::jsonb,
  source_system       text
);

ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS source_system text;

ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS product_id text;

ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS raw_legacy_payload jsonb;

ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS migration_meta jsonb DEFAULT '{}'::jsonb;

ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS import_batch_id uuid
    DEFAULT '00000000-0000-0000-0000-000000000000'::uuid;

ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS photo_status text;

ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS image_url text;

ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS sold_date_kst date;

ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS sold_at_utc timestamptz;

ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS price_krw bigint;

ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS sku text;

ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS legacy_id text;

CREATE UNIQUE INDEX IF NOT EXISTS sales_history_legacy_id_key
  ON public.sales_history (legacy_id);

CREATE INDEX IF NOT EXISTS sales_history_sold_date_kst_idx
  ON public.sales_history (sold_date_kst);

CREATE INDEX IF NOT EXISTS sales_history_product_id_idx
  ON public.sales_history (product_id)
  WHERE product_id IS NOT NULL;

COMMENT ON COLUMN public.sales_history.product_id IS
  'products.id (DrJaw/1С text). Для POS-возвратов и отчётов.';
COMMENT ON COLUMN public.sales_history.source_system IS
  'DrJaw — ETL; pwa_store — trg_log_pwa_sale / админ-POS.';

-- ---------------------------------------------------------------------------
-- 2) Триггер: products UPDATE → INSERT sales_history
--    (011 + product_id + migration_meta.product_id)
-- ---------------------------------------------------------------------------
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
    product_id,
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
    NEW.id,
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
      'product_id', NEW.id,
      'sold_at_utc', v_sold_at_utc,
      'sold_date_kst', v_sold_kst::text
    )
  )
  ON CONFLICT (legacy_id) DO NOTHING;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.log_future_sale_to_history() IS
  'AFTER UPDATE products: sold/stock 0 → sales_history (price_krw, sold_date_kst KST).';

ALTER FUNCTION public.log_future_sale_to_history() OWNER TO postgres;

DROP TRIGGER IF EXISTS trg_log_pwa_sale ON public.products;

CREATE TRIGGER trg_log_pwa_sale
  AFTER UPDATE ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.log_future_sale_to_history();

-- ---------------------------------------------------------------------------
-- 3) Права чтения для PWA (админ «История продаж» под anon JWT / PIN)
-- ---------------------------------------------------------------------------
GRANT SELECT ON TABLE public.sales_history TO anon, authenticated;

ALTER TABLE public.sales_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sales_history_select_anon ON public.sales_history;

CREATE POLICY sales_history_select_anon
  ON public.sales_history
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- ---------------------------------------------------------------------------
-- 4) Бэкфилл: products.status = sold без строки pwa_id_{id}
-- ---------------------------------------------------------------------------
INSERT INTO public.sales_history (
  legacy_id,
  sku,
  product_id,
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
SELECT
  'pwa_id_' || p.id,
  p.sku,
  p.id,
  COALESCE(p.sale_price, 0)::bigint,
  COALESCE(p.updated_at, timezone('utc', now())),
  (timezone('Asia/Seoul', COALESCE(p.updated_at, now())))::date,
  NULLIF(btrim(COALESCE(p.image_url, '')), ''),
  'success',
  '00000000-0000-0000-0000-000000000000'::uuid,
  'pwa_store',
  row_to_json(p)::jsonb,
  jsonb_build_object(
    'source_system', 'pwa_store',
    'logged_by', 'backfill_sold_products',
    'product_id', p.id,
    'sold_at_utc', COALESCE(p.updated_at, timezone('utc', now())),
    'sold_date_kst',
      (timezone('Asia/Seoul', COALESCE(p.updated_at, now())))::date::text,
    'backfill', true
  )
FROM public.products AS p
WHERE p.status = 'sold'
  AND NOT EXISTS (
    SELECT 1
    FROM public.sales_history AS sh
    WHERE sh.legacy_id = 'pwa_id_' || p.id
  );

COMMIT;
