-- DrJaw: один Articul (sku модели) → несколько Items.Id (физические экземпляры)
BEGIN;
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_sku_key;
COMMIT;
