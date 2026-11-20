-- 061: Фото в отчёте продаж — главное фото (slot 0 / products/{sku}.webp).
-- Зависит: 034, 056, 058 (gallery_slots).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Storage: только products/{sku}.webp (без _1.._3)
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

CREATE OR REPLACE FUNCTION public._storage_product_webp_object_name(p_sku text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'products/' || public._storage_safe_sku(p_sku) || '.webp';
$$;

CREATE OR REPLACE FUNCTION public._storage_product_images_public_base_url()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT split_part(split_part(url, '/storage/', 1), '?', 1)
  FROM (
    SELECT NULLIF(btrim(p.image_url), '') AS url
    FROM public.products AS p
    WHERE NULLIF(btrim(p.image_url), '') LIKE '%/storage/v1/object/public/product-images/%'
    ORDER BY p.updated_at DESC NULLS LAST
    LIMIT 1
  ) AS sample
  WHERE url IS NOT NULL;
$$;

-- URL — главный кадр Storage (…/products/{sku}.webp), не _1/_2/_3.
CREATE OR REPLACE FUNCTION public._product_storage_url_is_primary_slot(
  p_url text,
  p_sku text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN NULLIF(btrim(p_url), '') IS NULL THEN false
    WHEN NULLIF(btrim(p_sku), '') IS NULL THEN true
    ELSE right(
      public._gallery_url_canonical(p_url),
      length(public._storage_safe_sku(p_sku)) + length('.webp')
    ) = public._storage_safe_sku(p_sku) || '.webp'
  END;
$$;

DROP FUNCTION IF EXISTS public.product_storage_image_url_by_sku(text);

CREATE OR REPLACE FUNCTION public.product_storage_image_url_by_sku(p_sku text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, storage
AS $$
  SELECT CASE
    WHEN NULLIF(btrim(p_sku), '') IS NULL THEN NULL
    WHEN public._storage_product_images_public_base_url() IS NULL THEN NULL
    ELSE (
      SELECT
        public._storage_product_images_public_base_url()
        || '/storage/v1/object/public/product-images/'
        || o.name
      FROM storage.objects AS o
      WHERE o.bucket_id = 'product-images'
        AND o.name = public._storage_product_webp_object_name(p_sku)
      LIMIT 1
    )
  END;
$$;

COMMENT ON FUNCTION public.product_storage_image_url_by_sku(text) IS
  'Главное фото: products/{sku}.webp (slot 0), LIMIT 1 lookup в storage.objects.';

REVOKE ALL ON FUNCTION public.product_storage_image_url_by_sku(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.product_storage_image_url_by_sku(text)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) Галерея: slot 0 только (не _1.._3 при пустом slot 0 в отчётах)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._product_gallery_slot0_url(p_slots jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_slots IS NULL OR jsonb_typeof(p_slots) <> 'array' THEN NULL
    WHEN jsonb_typeof(public._product_gallery_slots_normalize(p_slots) -> 0) = 'null' THEN
      NULL
    ELSE NULLIF(
      btrim((public._product_gallery_slots_normalize(p_slots) ->> 0)),
      ''
    )
  END;
$$;

-- Витрина/триггеры: «первое фото» = строго индекс 0 (не первый непустой из 1..3).
CREATE OR REPLACE FUNCTION public._product_first_image_from_slots(p_slots jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT public._product_gallery_slot0_url(p_slots);
$$;

CREATE OR REPLACE FUNCTION public.product_primary_image_url(p public.products)
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    CASE
      WHEN public._product_storage_url_is_primary_slot(p.image_url, p.sku) THEN
        NULLIF(btrim(p.image_url), '')
      ELSE NULL
    END,
    public._product_gallery_slot0_url(
      public._product_gallery_slots_from_row(p)
    ),
    CASE
      WHEN COALESCE(array_length(p.additional_images, 1), 0) > 0
        AND public._product_storage_url_is_primary_slot(
          p.additional_images[1],
          p.sku
        ) THEN NULLIF(btrim(p.additional_images[1]), '')
      WHEN COALESCE(array_length(p.images, 1), 0) > 0
        AND public._product_storage_url_is_primary_slot(p.images[1], p.sku) THEN
        NULLIF(btrim(p.images[1]), '')
      ELSE NULL
    END,
    public.product_storage_image_url_by_sku(p.sku)
  );
$$;

REVOKE ALL ON FUNCTION public.product_primary_image_url(public.products) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.product_primary_image_url(public.products)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) log_future_sale_to_history — снимок: главное фото
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_future_sale_to_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_legacy_id        text;
  v_image_url        text;
  v_price_krw        bigint;
  v_list_krw         bigint;
  v_discount         integer;
  v_store            text;
  v_payload          jsonb;
  v_sold_at_utc      timestamptz;
  v_sold_kst         date;
  v_metal_category   text;
  v_seller_code      text;
  v_seller_name      text;
  v_commission_pct   numeric(5, 2);
  v_commission_krw   integer;
  v_product_name     text;
  v_suffix           text;
  v_gallery_slots    jsonb;
BEGIN
  IF NOT (NEW.status = 'sold' AND OLD.status IS DISTINCT FROM 'sold') THEN
    RETURN NEW;
  END IF;

  v_legacy_id := 'pwa_id_' || NEW.id;
  IF EXISTS (
    SELECT 1 FROM public.sales_history AS sh WHERE sh.legacy_id = v_legacy_id
  ) THEN
    v_suffix := floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint::text;
    v_legacy_id := 'pwa_id_' || NEW.id || '_' || v_suffix;
  END IF;

  v_sold_at_utc := timezone('utc', now());
  v_sold_kst := (timezone('Asia/Seoul', now()))::date;
  v_payload := row_to_json(NEW)::jsonb;
  v_list_krw := GREATEST(COALESCE(NEW.old_price, NEW.sale_price, 0), 0)::bigint;
  v_discount := GREATEST(COALESCE(NEW.discount_percent, 0), 0);
  v_price_krw := GREATEST(COALESCE(NEW.sale_price, 0), 0)::bigint;
  v_store := public._norm_store_icn_ans(NEW.store_location);

  v_metal_category := public.classify_jewelry_metal_category(
    NULLIF(btrim(NEW.metal), ''),
    NULLIF(btrim(NEW.metal_type), '')
  );

  v_product_name := COALESCE(
    NULLIF(btrim(NEW.name ->> 'ru'), ''),
    NULLIF(btrim(NEW.name ->> 'ko'), ''),
    NULLIF(btrim(NEW.sku), '')
  );

  SELECT r.seller_code, r.seller_name
  INTO v_seller_code, v_seller_name
  FROM public.resolve_seller_for_product_sale(NEW.id, NEW.sku, v_product_name) AS r
  LIMIT 1;

  v_commission_pct := 0;
  v_commission_krw := 0;
  IF v_seller_code IS NOT NULL THEN
    SELECT
      public.seller_commission_rate_for_metal(
        s.app_gold_commission_percent,
        s.app_silver_commission_percent,
        v_metal_category
      ),
      s.name
    INTO v_commission_pct, v_seller_name
    FROM public.sellers AS s
    WHERE s.promo_code = upper(v_seller_code);

    v_commission_krw := round(
      (v_price_krw::numeric * COALESCE(v_commission_pct, 0) / 100.0)
    )::integer;
  END IF;

  v_gallery_slots := public._product_gallery_slots_from_row(NEW);
  v_image_url := COALESCE(
    CASE
      WHEN public._product_storage_url_is_primary_slot(NEW.image_url, NEW.sku) THEN
        NULLIF(btrim(NEW.image_url), '')
      ELSE NULL
    END,
    public._product_gallery_slot0_url(v_gallery_slots),
    public.product_storage_image_url_by_sku(NEW.sku)
  );

  INSERT INTO public.sales_history (
    legacy_id, sku, product_id, price_krw, list_price_krw, discount_percent,
    store_location, payment_method,
    sold_at_utc, sold_date_kst, image_url, photo_status, import_batch_id,
    source_system, raw_legacy_payload, migration_meta,
    seller_code, seller_name, metal_category, commission_percent, commission_krw
  )
  VALUES (
    v_legacy_id,
    NEW.sku,
    NEW.id,
    v_price_krw,
    v_list_krw,
    v_discount,
    v_store,
    NULL,
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
      'store_location', v_store,
      'sold_at_utc', v_sold_at_utc,
      'sold_date_kst', v_sold_kst::text
    ),
    v_seller_code,
    v_seller_name,
    v_metal_category,
    COALESCE(v_commission_pct, 0),
    COALESCE(v_commission_krw, 0)
  )
  ON CONFLICT (legacy_id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4) list_sales_history_report — главное фото
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.list_sales_history_report(date, date, text, integer, integer);

CREATE OR REPLACE FUNCTION public.list_sales_history_report(
  p_date_from date,
  p_date_to date,
  p_store text DEFAULT 'ALL',
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  legacy_id text,
  product_id text,
  sku text,
  product_name text,
  weight_grams numeric,
  list_price_krw bigint,
  price_krw bigint,
  discount_percent integer,
  store_location text,
  seller_name text,
  seller_code text,
  payment_method text,
  sold_at_utc timestamptz,
  sold_date_kst date,
  image_url text,
  metal_category text,
  source_system text,
  manufacturer text,
  can_return boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, storage
AS $$
  WITH base AS (
    SELECT
      sh.*,
      public._sales_history_resolve_store(sh) AS resolved_store,
      COALESCE(p.weight_grams, p_sku.weight_grams) AS p_weight,
      COALESCE(p.status, p_sku.status) AS p_status,
      COALESCE(
        NULLIF(btrim(p.name ->> 'ru'), ''),
        NULLIF(btrim(p.name ->> 'ko'), ''),
        NULLIF(btrim(p.name ->> 'en'), ''),
        NULLIF(btrim(p_sku.name ->> 'ru'), ''),
        NULLIF(btrim(p_sku.name ->> 'ko'), ''),
        NULLIF(btrim(p_sku.name ->> 'en'), ''),
        NULLIF(btrim(sh.raw_legacy_payload ->> 'Type'), ''),
        NULLIF(btrim(sh.sku), '')
      ) AS p_name,
      COALESCE(
        public.product_primary_image_url(p),
        public.product_primary_image_url(p_sku),
        public.product_storage_image_url_by_sku(sh.sku),
        CASE
          WHEN public._product_storage_url_is_primary_slot(sh.image_url, sh.sku) THEN
            NULLIF(btrim(sh.image_url), '')
          ELSE NULL
        END
      ) AS resolved_image_url,
      COALESCE(
        sh.metal_category,
        public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
        public.classify_jewelry_metal_category(
          COALESCE(p.metal, p_sku.metal),
          COALESCE(p.metal_type, p_sku.metal_type)
        ),
        'other'
      ) AS resolved_metal_category
    FROM public.sales_history AS sh
    LEFT JOIN public.products AS p ON p.id = sh.product_id
    LEFT JOIN LATERAL (
      SELECT ps.*
      FROM public.products AS ps
      WHERE NULLIF(btrim(sh.sku), '') IS NOT NULL
        AND upper(btrim(ps.sku)) = upper(btrim(sh.sku))
      ORDER BY
        (public.product_primary_image_url(ps) IS NOT NULL) DESC,
        ps.updated_at DESC NULLS LAST
      LIMIT 1
    ) AS p_sku ON true
    WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
      AND (
        upper(btrim(COALESCE(p_store, 'ALL'))) = 'ALL'
        OR public._sales_history_resolve_store(sh) = upper(btrim(p_store))
      )
  )
  SELECT
    b.id,
    b.legacy_id,
    b.product_id,
    b.sku,
    b.p_name AS product_name,
    COALESCE(
      b.p_weight,
      public.sales_history_payload_weight_grams(b.raw_legacy_payload)
    ) AS weight_grams,
    COALESCE(b.list_price_krw, b.price_krw) AS list_price_krw,
    b.price_krw,
    COALESCE(b.discount_percent, 0) AS discount_percent,
    b.resolved_store AS store_location,
    NULLIF(btrim(b.seller_name), '') AS seller_name,
    b.seller_code,
    b.payment_method,
    b.sold_at_utc,
    b.sold_date_kst,
    b.resolved_image_url AS image_url,
    b.resolved_metal_category AS metal_category,
    b.source_system,
    CASE
      WHEN b.legacy_id NOT LIKE 'pwa_id_%' THEN
        NULLIF(btrim(b.raw_legacy_payload ->> 'Manager'), '')
      ELSE NULL
    END AS manufacturer,
    (
      b.price_krw > 0
      AND b.legacy_id LIKE 'pwa_id_%'
      AND COALESCE(b.source_system, '') IS DISTINCT FROM 'DrJaw'
      AND b.p_status = 'sold'
      AND NOT EXISTS (
        SELECT 1
        FROM public.sales_history AS r
        WHERE (r.migration_meta ->> 'reverses_legacy_id') = b.legacy_id
          AND COALESCE(r.migration_meta ->> 'type', '') = 'return'
      )
    ) AS can_return
  FROM base AS b
  ORDER BY b.sold_at_utc DESC NULLS LAST, b.legacy_id DESC
  LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 200), 1)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

REVOKE ALL ON FUNCTION public.list_sales_history_report(date, date, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_sales_history_report(date, date, text, integer, integer)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5) Бэкфилл sales_history.image_url — главное фото
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

-- products: .jpg → главный .webp в Storage
UPDATE public.products AS p
SET
  image_url = CASE
    WHEN NULLIF(btrim(p.image_url), '') ~* '\.jpe?g(\?|$)'
      AND public.product_storage_image_url_by_sku(p.sku) IS NOT NULL
      THEN public.product_storage_image_url_by_sku(p.sku)
        || COALESCE(
          NULLIF(substring(p.image_url from '\?.*$'), ''),
          ''
        )
    ELSE p.image_url
  END,
  gallery_slots = (
    SELECT jsonb_agg(
      CASE
        WHEN elem IS NULL OR jsonb_typeof(elem) = 'null' THEN 'null'::jsonb
        WHEN elem #>> '{}' ~* '\.jpe?g(\?|$)'
          AND public.product_storage_image_url_by_sku(p.sku) IS NOT NULL
        AND (ord - 1) = 0 THEN
          to_jsonb(public.product_storage_image_url_by_sku(p.sku))
        WHEN elem #>> '{}' ~* '\.jpe?g(\?|$)' THEN
          to_jsonb(
            regexp_replace(elem #>> '{}', '\.jpe?g', '.webp', 'i')
          )
        ELSE elem
      END
      ORDER BY ord
    )
    FROM jsonb_array_elements(
      COALESCE(p.gallery_slots, '[]'::jsonb)
    ) WITH ORDINALITY AS t(elem, ord)
  )
WHERE NULLIF(btrim(p.sku), '') IS NOT NULL
  AND (
    NULLIF(btrim(p.image_url), '') ~* '\.jpe?g(\?|$)'
    OR p.gallery_slots::text ~* '\.jpe?g'
  );

COMMIT;