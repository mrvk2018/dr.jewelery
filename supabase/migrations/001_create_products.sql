-- Dr. Jewelry — таблица витрины (контракт ProductItem / DatabaseService.getProducts)
-- Запись и изменение остатков: только sync-скрипт с SUPABASE_SERVICE_ROLE_KEY (RLS обходится у service_role).

BEGIN;

CREATE TABLE IF NOT EXISTS public.products (
  id                  text PRIMARY KEY,
  sku                 text NOT NULL UNIQUE,
  stock_quantity      integer NOT NULL DEFAULT 0
                        CHECK (stock_quantity >= 0),
  name                jsonb NOT NULL DEFAULT '{}'::jsonb,
  description         jsonb NOT NULL DEFAULT '{}'::jsonb,
  metal               text NOT NULL,
  sale_price          integer NOT NULL CHECK (sale_price >= 0),
  old_price           integer NOT NULL CHECK (old_price >= 0),
  discount_percent    integer NOT NULL DEFAULT 0
                        CHECK (discount_percent >= 0 AND discount_percent <= 100),
  category            text NOT NULL,
  "insert"            text NOT NULL,
  icon_index          integer NOT NULL DEFAULT 0,
  available_sizes     jsonb NOT NULL DEFAULT '[]'::jsonb,
  CONSTRAINT products_name_is_object
    CHECK (jsonb_typeof(name) = 'object'),
  CONSTRAINT products_description_is_object
    CHECK (jsonb_typeof(description) = 'object'),
  CONSTRAINT products_available_sizes_is_array
    CHECK (jsonb_typeof(available_sizes) = 'array')
);

COMMENT ON TABLE public.products IS
  'Каталог витрины. ProductItem: id, sku, stockQuantity, name/description (ru|kk|ko|en|uz), metal, salePrice/oldPrice (KRW int), discountPercent, category, insert, iconIndex, availableSizes. Фото URL в модели нет — только iconIndex.';
COMMENT ON COLUMN public.products.sku IS
  'Артикул / штрихкод POS; ключ синхронизации остатков (updateProductStock).';
COMMENT ON COLUMN public.products.name IS
  'JSON: {"ru":"...","kk":"...","ko":"...","en":"...","uz":"..."}';
COMMENT ON COLUMN public.products.available_sizes IS
  'JSON-массив чисел, напр. [15, 15.5, 16]';

CREATE INDEX IF NOT EXISTS products_sku_idx ON public.products (sku);
CREATE INDEX IF NOT EXISTS products_category_idx ON public.products (category);
CREATE INDEX IF NOT EXISTS products_stock_quantity_idx ON public.products (stock_quantity);

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.products FORCE ROW LEVEL SECURITY;

-- Публичное чтение витрины (гость и авторизованный клиент).
CREATE POLICY products_public_select
  ON public.products
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- INSERT / UPDATE / DELETE для anon и authenticated не создаём → запрещено при включённом RLS.
-- Складской sync использует service_role (ключ только на сервере, .env) — RLS не применяется.

REVOKE ALL ON TABLE public.products FROM PUBLIC;
REVOKE ALL ON TABLE public.products FROM anon;
REVOKE ALL ON TABLE public.products FROM authenticated;

GRANT SELECT ON TABLE public.products TO anon;
GRANT SELECT ON TABLE public.products TO authenticated;

COMMIT;
