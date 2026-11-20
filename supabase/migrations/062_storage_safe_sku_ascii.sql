-- 062: ASCII-safe SKU для Storage (как sync.js: [^a-zA-Z0-9_.-]+ → '_').
-- Зависит: 061 (product_storage_image_url_by_sku, _product_storage_url_is_primary_slot).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) _storage_safe_sku — явная ASCII-регулярка (PostgreSQL \w ≠ JS \w для кириллицы)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._storage_safe_sku(p_sku text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT regexp_replace(
    btrim(COALESCE(p_sku, '')),
    '[^a-zA-Z0-9_.-]+',
    '_',
    'g'
  );
$$;

COMMENT ON FUNCTION public._storage_safe_sku(text) IS
  'Имя файла в product-images/products/: не-ASCII (в т.ч. кириллица) → _, как sync.js.';

-- product_storage_image_url_by_sku / _product_storage_product_webp_object_name /
-- _product_storage_url_is_primary_slot из 061 используют только _storage_safe_sku (без \w).

-- ---------------------------------------------------------------------------
-- 2) Бэкфилл sales_history.image_url (идемпотентно, главное фото)
-- ---------------------------------------------------------------------------
UPDATE public.sales_history AS sh
SET image_url = resolved.url
FROM (
  SELECT
    sh2.id,
    COALESCE(
      public.product_primary_image_url(p),
      public.product_primary_image_url(p_sku),
      public.product_storage_image_url_by_sku(sh2.sku),
      CASE
        WHEN public._product_storage_url_is_primary_slot(sh2.image_url, sh2.sku) THEN
          NULLIF(btrim(sh2.image_url), '')
        ELSE NULL
      END
    ) AS url
  FROM public.sales_history AS sh2
  LEFT JOIN public.products AS p ON p.id = sh2.product_id
  LEFT JOIN LATERAL (
    SELECT ps.*
    FROM public.products AS ps
    WHERE NULLIF(btrim(sh2.sku), '') IS NOT NULL
      AND upper(btrim(ps.sku)) = upper(btrim(sh2.sku))
    ORDER BY
      (public.product_primary_image_url(ps) IS NOT NULL) DESC,
      ps.updated_at DESC NULLS LAST
    LIMIT 1
  ) AS p_sku ON true
  WHERE NULLIF(btrim(sh2.sku), '') IS NOT NULL
) AS resolved
WHERE sh.id = resolved.id
  AND NULLIF(btrim(resolved.url), '') IS NOT NULL
  AND (
    NULLIF(btrim(sh.image_url), '') IS NULL
    OR NOT public._product_storage_url_is_primary_slot(sh.image_url, sh.sku)
    OR NULLIF(btrim(sh.image_url), '') IS DISTINCT FROM NULLIF(btrim(resolved.url), '')
  );

COMMIT;