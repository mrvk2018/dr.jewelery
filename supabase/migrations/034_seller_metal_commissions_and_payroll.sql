-- Комиссии продавцов (золото/серебро), привязка к sales_history, зарплатные RPC.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) sellers: ставки комиссии
-- ---------------------------------------------------------------------------
ALTER TABLE public.sellers
  ADD COLUMN IF NOT EXISTS gold_commission_percent numeric(5, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS silver_commission_percent numeric(5, 2) NOT NULL DEFAULT 0;

ALTER TABLE public.sellers DROP CONSTRAINT IF EXISTS sellers_gold_commission_range;
ALTER TABLE public.sellers
  ADD CONSTRAINT sellers_gold_commission_range
  CHECK (gold_commission_percent >= 0 AND gold_commission_percent <= 100);

ALTER TABLE public.sellers DROP CONSTRAINT IF EXISTS sellers_silver_commission_range;
ALTER TABLE public.sellers
  ADD CONSTRAINT sellers_silver_commission_range
  CHECK (silver_commission_percent >= 0 AND silver_commission_percent <= 100);

COMMENT ON COLUMN public.sellers.gold_commission_percent IS
  'Процент комиссии продавца с продажи изделий категории gold.';
COMMENT ON COLUMN public.sellers.silver_commission_percent IS
  'Процент комиссии продавца с продажи изделий категории silver.';

DROP FUNCTION IF EXISTS public.upsert_seller_by_admin(text, text, boolean);

CREATE OR REPLACE FUNCTION public.upsert_seller_by_admin(
  p_promo_code text,
  p_name text,
  p_is_active boolean DEFAULT true,
  p_gold_commission_percent numeric DEFAULT 0,
  p_silver_commission_percent numeric DEFAULT 0
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code varchar(50);
  v_name varchar(255);
  v_gold numeric(5, 2);
  v_silver numeric(5, 2);
BEGIN
  v_code := upper(trim(both from coalesce(p_promo_code, '')));
  v_name := trim(both from coalesce(p_name, ''));

  IF v_code = '' OR v_name = '' THEN
    RAISE EXCEPTION 'invalid_input'
      USING ERRCODE = '22023',
            MESSAGE = 'promo_code и name обязательны';
  END IF;

  IF length(v_code) <> 6 OR v_code !~ '^[A-Z0-9]{6}$' THEN
    RAISE EXCEPTION 'invalid_promo_code'
      USING ERRCODE = '22023',
            MESSAGE = 'promo_code: ровно 6 символов A-Z или 0-9';
  END IF;

  v_gold := round(coalesce(p_gold_commission_percent, 0)::numeric, 2);
  v_silver := round(coalesce(p_silver_commission_percent, 0)::numeric, 2);

  IF v_gold < 0 OR v_gold > 100 OR v_silver < 0 OR v_silver > 100 THEN
    RAISE EXCEPTION 'invalid_commission'
      USING ERRCODE = '22023',
            MESSAGE = 'commission percent must be 0..100';
  END IF;

  INSERT INTO public.sellers (
    promo_code,
    name,
    is_active,
    gold_commission_percent,
    silver_commission_percent
  )
  VALUES (v_code, v_name, coalesce(p_is_active, true), v_gold, v_silver)
  ON CONFLICT (promo_code) DO UPDATE SET
    name = EXCLUDED.name,
    is_active = EXCLUDED.is_active,
    gold_commission_percent = EXCLUDED.gold_commission_percent,
    silver_commission_percent = EXCLUDED.silver_commission_percent;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_seller_by_admin(
  text, text, boolean, numeric, numeric
) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) sales_history: продавец и комиссия
-- ---------------------------------------------------------------------------
ALTER TABLE public.sales_history
  ADD COLUMN IF NOT EXISTS seller_code text,
  ADD COLUMN IF NOT EXISTS seller_name text,
  ADD COLUMN IF NOT EXISTS metal_category text,
  ADD COLUMN IF NOT EXISTS commission_percent numeric(5, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS commission_krw integer NOT NULL DEFAULT 0;

ALTER TABLE public.sales_history DROP CONSTRAINT IF EXISTS sales_history_metal_category_check;
ALTER TABLE public.sales_history
  ADD CONSTRAINT sales_history_metal_category_check
  CHECK (
    metal_category IS NULL
    OR metal_category IN ('gold', 'silver', 'other')
  );

CREATE INDEX IF NOT EXISTS sales_history_seller_code_sold_date_idx
  ON public.sales_history (seller_code, sold_date_kst)
  WHERE seller_code IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 3) Классификация металла
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.classify_jewelry_metal_category(
  p_metal text DEFAULT NULL,
  p_metal_type text DEFAULT NULL
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN COALESCE(p_metal, p_metal_type, '') ILIKE '%золото%'
      OR COALESCE(p_metal, p_metal_type, '') ~* '(^|[^0-9])(585|750|583|375)([^0-9]|$)' THEN
      'gold'
    WHEN COALESCE(p_metal, p_metal_type, '') ILIKE '%серебр%'
      OR COALESCE(p_metal, p_metal_type, '') ~* '925' THEN
      'silver'
    ELSE
      'other'
  END;
$$;

CREATE OR REPLACE FUNCTION public.classify_metal_from_sales_payload(p_payload jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT public.classify_jewelry_metal_category(
    NULLIF(btrim(p_payload ->> 'metal'), ''),
    NULLIF(btrim(p_payload ->> 'metal_type'), '')
  );
$$;

CREATE OR REPLACE FUNCTION public.seller_commission_rate_for_metal(
  p_gold numeric,
  p_silver numeric,
  p_category text
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE COALESCE(p_category, 'other')
    WHEN 'gold' THEN coalesce(p_gold, 0)
    WHEN 'silver' THEN coalesce(p_silver, 0)
    ELSE 0
  END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_seller_for_product_sale(
  p_product_id text,
  p_sku text,
  p_product_name text DEFAULT NULL
)
RETURNS TABLE(seller_code text, seller_name text)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH params AS (
    SELECT
      NULLIF(btrim(p_sku), '') AS sku,
      NULLIF(btrim(p_product_name), '') AS pname
  ),
  order_direct AS (
    SELECT
      upper(btrim(o.seller_code))::text AS seller_code,
      COALESCE(NULLIF(btrim(o.seller_name), ''), s.name)::text AS seller_name,
      o.created_at
    FROM public.orders AS o
    LEFT JOIN public.sellers AS s ON upper(btrim(o.seller_code)) = s.promo_code
    CROSS JOIN params AS pr
    WHERE NULLIF(btrim(o.seller_code), '') IS NOT NULL
      AND COALESCE(o.status, '') NOT IN ('cancelled', 'canceled', 'refunded')
      AND pr.sku IS NOT NULL
      AND (
        btrim(COALESCE(o.product_name, '')) ILIKE ('%' || pr.sku || '%')
        OR (
          pr.pname IS NOT NULL
          AND btrim(COALESCE(o.product_name, '')) ILIKE ('%' || pr.pname || '%')
        )
      )
    ORDER BY o.created_at DESC NULLS LAST
    LIMIT 1
  ),
  order_referral AS (
    SELECT
      upper(btrim(p.referred_by_seller))::text AS seller_code,
      s.name::text AS seller_name,
      o.created_at
    FROM public.orders AS o
    INNER JOIN public.profiles AS p ON p.id = o.user_id
    INNER JOIN public.sellers AS s ON s.promo_code = upper(btrim(p.referred_by_seller))
    CROSS JOIN params AS pr
    WHERE NULLIF(btrim(p.referred_by_seller), '') IS NOT NULL
      AND COALESCE(o.status, '') NOT IN ('cancelled', 'canceled', 'refunded')
      AND pr.sku IS NOT NULL
      AND (
        btrim(COALESCE(o.product_name, '')) ILIKE ('%' || pr.sku || '%')
        OR (
          pr.pname IS NOT NULL
          AND btrim(COALESCE(o.product_name, '')) ILIKE ('%' || pr.pname || '%')
        )
      )
      AND NOT EXISTS (SELECT 1 FROM order_direct)
    ORDER BY o.created_at DESC NULLS LAST
    LIMIT 1
  )
  SELECT od.seller_code, od.seller_name FROM order_direct AS od
  UNION ALL
  SELECT r.seller_code, r.seller_name FROM order_referral AS r
  LIMIT 1;
$$;

-- Бэкфилл metal_category
UPDATE public.sales_history AS sh
SET metal_category = COALESCE(
  sh.metal_category,
  public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
  public.classify_jewelry_metal_category(
    (SELECT p.metal FROM public.products p WHERE p.id = sh.product_id OR p.sku = sh.sku LIMIT 1),
    (SELECT p.metal_type FROM public.products p WHERE p.id = sh.product_id OR p.sku = sh.sku LIMIT 1)
  ),
  'other'
)
WHERE sh.metal_category IS NULL;

-- ---------------------------------------------------------------------------
-- 4) Триггер продажи
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
  v_payload          jsonb;
  v_sold_at_utc      timestamptz;
  v_sold_kst         date;
  v_metal_category   text;
  v_seller_code      text;
  v_seller_name      text;
  v_commission_pct   numeric(5, 2);
  v_commission_krw   integer;
  v_product_name     text;
  v_resolved         record;
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

  v_metal_category := public.classify_jewelry_metal_category(
    NULLIF(btrim(NEW.metal), ''),
    NULLIF(btrim(NEW.metal_type), '')
  );

  v_product_name := COALESCE(
    NULLIF(btrim(NEW.name ->> 'ru'), ''),
    NULLIF(btrim(NEW.name ->> 'ko'), ''),
    NULLIF(btrim(NEW.name ->> 'en'), ''),
    NULLIF(btrim(NEW.sku), '')
  );

  v_seller_code := NULL;
  v_seller_name := NULL;
  v_commission_pct := 0;
  v_commission_krw := 0;

  SELECT r.seller_code, r.seller_name
  INTO v_seller_code, v_seller_name
  FROM public.resolve_seller_for_product_sale(NEW.id, NEW.sku, v_product_name) AS r
  LIMIT 1;

  IF v_seller_code IS NOT NULL THEN
    SELECT
      public.seller_commission_rate_for_metal(
        s.gold_commission_percent,
        s.silver_commission_percent,
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
    migration_meta,
    seller_code,
    seller_name,
    metal_category,
    commission_percent,
    commission_krw
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

COMMENT ON FUNCTION public.log_future_sale_to_history() IS
  'AFTER UPDATE products: sold/stock 0 → sales_history с metal_category и комиссией продавца.';

ALTER FUNCTION public.log_future_sale_to_history() OWNER TO postgres;

-- ---------------------------------------------------------------------------
-- 5) attach_seller_to_sales (POS / QR, окно 15 мин)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.attach_seller_to_sales(
  p_skus text[],
  p_seller_code text,
  p_seller_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
  v_name text;
  v_updated bigint := 0;
  v_gold numeric(5, 2);
  v_silver numeric(5, 2);
  v_cutoff timestamptz;
BEGIN
  v_code := upper(btrim(coalesce(p_seller_code, '')));
  v_name := btrim(coalesce(p_seller_name, ''));
  v_cutoff := timezone('utc', now()) - interval '15 minutes';

  IF v_code = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'empty_seller_code');
  END IF;

  IF p_skus IS NULL OR array_length(p_skus, 1) IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'empty_skus');
  END IF;

  SELECT
    s.gold_commission_percent,
    s.silver_commission_percent,
    s.name
  INTO v_gold, v_silver, v_name
  FROM public.sellers AS s
  WHERE s.promo_code = v_code AND s.is_active;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'seller_not_found');
  END IF;

  IF v_name = '' OR v_name IS NULL THEN
    v_name := (SELECT s2.name FROM public.sellers s2 WHERE s2.promo_code = v_code);
  END IF;

  WITH norm_skus AS (
    SELECT DISTINCT upper(btrim(x)) AS sku
    FROM unnest(p_skus) AS x
    WHERE btrim(coalesce(x, '')) <> ''
  ),
  touched AS (
    UPDATE public.sales_history AS sh
    SET
      seller_code = v_code,
      seller_name = v_name,
      metal_category = COALESCE(
        sh.metal_category,
        public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
        'other'
      ),
      commission_percent = public.seller_commission_rate_for_metal(
        v_gold,
        v_silver,
        COALESCE(
          sh.metal_category,
          public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
          'other'
        )
      ),
      commission_krw = round(
        (COALESCE(sh.price_krw, 0)::numeric
          * public.seller_commission_rate_for_metal(
              v_gold,
              v_silver,
              COALESCE(
                sh.metal_category,
                public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
                'other'
              )
            ) / 100.0)
      )::integer
    FROM norm_skus AS n
    WHERE upper(btrim(coalesce(sh.sku, ''))) = n.sku
      AND sh.price_krw > 0
      AND sh.sold_at_utc >= v_cutoff
    RETURNING sh.id
  )
  SELECT count(*)::bigint INTO v_updated FROM touched;

  RETURN jsonb_build_object('ok', true, 'updated', v_updated, 'seller_code', v_code);
END;
$$;

REVOKE ALL ON FUNCTION public.attach_seller_to_sales(text[], text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.attach_seller_to_sales(text[], text, text)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6) Возврат: удержание в месяце возврата (sold_date_kst = сегодня KST)
-- ---------------------------------------------------------------------------
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
  v_commission_krw integer;
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
  v_sold_kst := (timezone('Asia/Seoul', now()))::date;

  v_commission_krw := (-1) * abs(
    COALESCE(
      v_sale.commission_krw,
      round(
        (abs(v_sale.price_krw)::numeric * COALESCE(v_sale.commission_percent, 0) / 100.0)
      )::integer
    )
  );

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
    migration_meta,
    seller_code,
    seller_name,
    metal_category,
    commission_percent,
    commission_krw
  )
  VALUES (
    v_return_legacy,
    v_sale.sku,
    v_sale.product_id,
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
      'returned_at_utc', v_sold_utc,
      'original_sold_date_kst', v_sale.sold_date_kst::text
    ),
    v_sale.seller_code,
    v_sale.seller_name,
    v_sale.metal_category,
    COALESCE(v_sale.commission_percent, 0),
    v_commission_krw
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
    'reverses_legacy_id', v_sale.legacy_id,
    'commission_krw', v_commission_krw
  );
END;
$$;

COMMENT ON FUNCTION public.process_product_return_manual(text, text) IS
  'Возврат: сторно в sales_history с sold_date_kst=дата возврата (KST) и отрицательной commission_krw.';

REVOKE ALL ON FUNCTION public.process_product_return_manual(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_product_return_manual(text, text) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7) get_seller_payroll_summary
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_seller_payroll_summary(
  p_date_from date,
  p_date_to date
)
RETURNS TABLE (
  promo_code text,
  seller_name text,
  is_active boolean,
  gold_commission_percent numeric,
  silver_commission_percent numeric,
  gold_sales_count bigint,
  gold_sales_krw bigint,
  gold_commission_krw bigint,
  silver_sales_count bigint,
  silver_sales_krw bigint,
  silver_commission_krw bigint,
  returns_count bigint,
  returns_commission_krw bigint,
  total_commission_krw bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH period AS (
    SELECT sh.*
    FROM public.sales_history AS sh
    WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
  ),
  agg AS (
    SELECT
      upper(btrim(sh.seller_code)) AS code,
      count(*) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'gold') AS gold_cnt,
      coalesce(sum(sh.price_krw) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'gold'), 0) AS gold_krw,
      coalesce(sum(sh.commission_krw) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'gold'), 0) AS gold_comm,
      count(*) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'silver') AS silver_cnt,
      coalesce(sum(sh.price_krw) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'silver'), 0) AS silver_krw,
      coalesce(sum(sh.commission_krw) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'silver'), 0) AS silver_comm,
      count(*) FILTER (WHERE sh.price_krw < 0) AS ret_cnt,
      coalesce(sum(sh.commission_krw) FILTER (WHERE sh.price_krw < 0), 0) AS ret_comm,
      coalesce(sum(sh.commission_krw), 0) AS total_comm
    FROM period AS sh
    WHERE NULLIF(btrim(sh.seller_code), '') IS NOT NULL
    GROUP BY upper(btrim(sh.seller_code))
  ),
  seller_rows AS (
    SELECT
      s.promo_code::text,
      s.name::text AS seller_name,
      s.is_active,
      s.gold_commission_percent,
      s.silver_commission_percent,
      coalesce(a.gold_cnt, 0) AS gold_sales_count,
      coalesce(a.gold_krw, 0)::bigint AS gold_sales_krw,
      coalesce(a.gold_comm, 0)::bigint AS gold_commission_krw,
      coalesce(a.silver_cnt, 0) AS silver_sales_count,
      coalesce(a.silver_krw, 0)::bigint AS silver_sales_krw,
      coalesce(a.silver_comm, 0)::bigint AS silver_commission_krw,
      coalesce(a.ret_cnt, 0) AS returns_count,
      coalesce(a.ret_comm, 0)::bigint AS returns_commission_krw,
      coalesce(a.total_comm, 0)::bigint AS total_commission_krw
    FROM public.sellers AS s
    LEFT JOIN agg AS a ON a.code = s.promo_code
  ),
  unassigned AS (
    SELECT
      '__UNASSIGNED__'::text AS promo_code,
      'Без продавца'::text AS seller_name,
      true AS is_active,
      0::numeric AS gold_commission_percent,
      0::numeric AS silver_commission_percent,
      coalesce(sum(
        CASE WHEN sh.price_krw > 0 AND sh.metal_category = 'gold' THEN 1 ELSE 0 END
      ), 0)::bigint AS gold_sales_count,
      coalesce(sum(sh.price_krw) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'gold'), 0)::bigint AS gold_sales_krw,
      coalesce(sum(sh.commission_krw) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'gold'), 0)::bigint AS gold_commission_krw,
      coalesce(sum(
        CASE WHEN sh.price_krw > 0 AND sh.metal_category = 'silver' THEN 1 ELSE 0 END
      ), 0)::bigint AS silver_sales_count,
      coalesce(sum(sh.price_krw) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'silver'), 0)::bigint AS silver_sales_krw,
      coalesce(sum(sh.commission_krw) FILTER (WHERE sh.price_krw > 0 AND sh.metal_category = 'silver'), 0)::bigint AS silver_commission_krw,
      coalesce(sum(
        CASE WHEN sh.price_krw < 0 THEN 1 ELSE 0 END
      ), 0)::bigint AS returns_count,
      coalesce(sum(sh.commission_krw) FILTER (WHERE sh.price_krw < 0), 0)::bigint AS returns_commission_krw,
      coalesce(sum(sh.commission_krw), 0)::bigint AS total_commission_krw
    FROM period AS sh
    WHERE NULLIF(btrim(sh.seller_code), '') IS NULL
    HAVING count(*) > 0
  )
  SELECT * FROM seller_rows
  UNION ALL
  SELECT * FROM unassigned
  ORDER BY 1;
$$;

REVOKE ALL ON FUNCTION public.get_seller_payroll_summary(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_seller_payroll_summary(date, date)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8) get_seller_sales_details
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.product_primary_image_url(p products)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    NULLIF(btrim(p.image_url), ''),
    CASE
      WHEN COALESCE(array_length(p.additional_images, 1), 0) > 0 THEN
        NULLIF(btrim(p.additional_images[1]), '')
      ELSE NULL
    END
  );
$$;

CREATE OR REPLACE FUNCTION public.get_seller_sales_details(
  p_seller_code text,
  p_date_from date,
  p_date_to date
)
RETURNS TABLE (
  sale_id text,
  sold_at timestamptz,
  sku text,
  product_name text,
  metal_category text,
  metal_label text,
  weight_grams numeric,
  price_krw integer,
  commission_percent numeric,
  commission_krw integer,
  is_return boolean,
  image_url text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    sh.id::text AS sale_id,
    sh.sold_at_utc AS sold_at,
    sh.sku,
    COALESCE(
      NULLIF(btrim(p.name ->> 'ru'), ''),
      NULLIF(btrim(p.name ->> 'ko'), ''),
      NULLIF(btrim(p.name ->> 'en'), ''),
      sh.sku
    ) AS product_name,
    COALESCE(
      sh.metal_category,
      public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
      'other'
    ) AS metal_category,
    COALESCE(
      NULLIF(btrim(p.metal_type), ''),
      NULLIF(btrim(p.metal), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'metal_type'), ''),
      NULLIF(btrim(sh.raw_legacy_payload ->> 'metal'), '')
    ) AS metal_label,
    COALESCE(p.weight_grams, (sh.raw_legacy_payload ->> 'weight_grams')::numeric) AS weight_grams,
    sh.price_krw::integer,
    sh.commission_percent,
    sh.commission_krw,
    (sh.price_krw < 0) AS is_return,
    COALESCE(
      public.product_primary_image_url(p),
      NULLIF(btrim(sh.image_url), ''),
      CASE
        WHEN jsonb_typeof(sh.raw_legacy_payload -> 'additional_images') = 'array'
          AND jsonb_array_length(sh.raw_legacy_payload -> 'additional_images') > 0 THEN
          NULLIF(btrim(sh.raw_legacy_payload -> 'additional_images' ->> 0), '')
        ELSE NULL
      END,
      NULLIF(btrim(sh.raw_legacy_payload ->> 'image_url'), '')
    ) AS image_url
  FROM public.sales_history AS sh
  LEFT JOIN public.products AS p
    ON p.id = sh.product_id
    OR (sh.product_id IS NULL AND p.sku = sh.sku)
  WHERE sh.sold_date_kst BETWEEN p_date_from AND p_date_to
    AND (
      (
        upper(btrim(p_seller_code)) = '__UNASSIGNED__'
        AND NULLIF(btrim(sh.seller_code), '') IS NULL
      )
      OR upper(btrim(sh.seller_code)) = upper(btrim(p_seller_code))
    )
  ORDER BY sh.sold_at_utc DESC NULLS LAST, sh.legacy_id DESC;
$$;

REVOKE ALL ON FUNCTION public.get_seller_sales_details(text, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_seller_sales_details(text, date, date)
  TO anon, authenticated, service_role;

COMMIT;