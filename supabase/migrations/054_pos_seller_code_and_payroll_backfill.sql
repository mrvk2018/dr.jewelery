-- 054: POS — seller_code, POS-комиссии (gold/silver), resolve по имени, бэкфилл ноября.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) resolve_seller_by_name — имя кассира → карточка sellers (POS-ставки)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_seller_by_name(p_name text)
RETURNS TABLE (
  promo_code text,
  name text,
  gold_commission_percent numeric,
  silver_commission_percent numeric
)
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_norm text;
BEGIN
  v_norm := lower(btrim(COALESCE(p_name, '')));

  IF v_norm IN ('андрей', 'наталья') THEN
    RETURN QUERY
    SELECT
      s.promo_code::text,
      s.name::text,
      s.gold_commission_percent,
      s.silver_commission_percent
    FROM public.sellers AS s
    WHERE s.promo_code = 'ADMIN'
      AND s.is_active;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    s.promo_code::text,
    s.name::text,
    s.gold_commission_percent,
    s.silver_commission_percent
  FROM public.sellers AS s
  WHERE lower(btrim(s.name)) = v_norm
    AND s.is_active;
END;
$$;

COMMENT ON FUNCTION public.resolve_seller_by_name(text) IS
  'POS/payroll: сопоставление seller_name → promo_code; Андрей/Наталья → ADMIN (0%).';

-- ---------------------------------------------------------------------------
-- 2) archive_admin_pos_sale — seller_code + POS commission_percent/krw
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.archive_admin_pos_sale(jsonb, text, text);
DROP FUNCTION IF EXISTS public.archive_admin_pos_sale(jsonb, text, text, text);

CREATE OR REPLACE FUNCTION public.archive_admin_pos_sale(
  p_lines jsonb,
  p_seller_name text DEFAULT NULL,
  p_payment_method text DEFAULT NULL,
  p_seller_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line jsonb;
  v_pid text;
  v_discount integer;
  v_row public.products%ROWTYPE;
  v_list bigint;
  v_final bigint;
  v_store text;
  v_payment text;
  v_seller text;
  v_metal text;
  v_sold bigint := 0;
  v_order_id text;
  v_history_id uuid;
  v_code_input text;
  v_seller_code text;
  v_resolved_name text;
  v_gold_pct numeric;
  v_silver_pct numeric;
  v_display_seller_name text;
  v_commission_pct numeric;
  v_commission_krw integer;
BEGIN
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array'
     OR jsonb_array_length(p_lines) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'empty_cart');
  END IF;

  v_seller := NULLIF(btrim(COALESCE(p_seller_name, '')), '');
  v_payment := NULLIF(btrim(COALESCE(p_payment_method, '')), '');
  IF v_payment IS NOT NULL
     AND v_payment NOT IN ('cash', 'card', 'transfer') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_payment_method');
  END IF;
  IF v_seller IS NULL OR v_payment IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'seller_and_payment_required');
  END IF;

  v_code_input := NULLIF(upper(btrim(COALESCE(p_seller_code, ''))), '');
  IF v_code_input IS NOT NULL THEN
    SELECT
      s.promo_code,
      s.name,
      s.gold_commission_percent,
      s.silver_commission_percent
    INTO v_seller_code, v_resolved_name, v_gold_pct, v_silver_pct
    FROM public.sellers AS s
    WHERE s.promo_code = v_code_input
      AND s.is_active;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'seller_not_found');
    END IF;
  ELSE
    SELECT
      r.promo_code,
      r.name,
      r.gold_commission_percent,
      r.silver_commission_percent
    INTO v_seller_code, v_resolved_name, v_gold_pct, v_silver_pct
    FROM public.resolve_seller_by_name(v_seller) AS r
    LIMIT 1;

    IF v_seller_code IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'seller_not_resolved');
    END IF;
  END IF;

  v_display_seller_name := CASE
    WHEN v_seller_code = 'ADMIN' THEN v_seller
    ELSE COALESCE(v_resolved_name, v_seller)
  END;

  v_order_id := 'pos_' || replace(gen_random_uuid()::text, '-', '');

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_pid := NULLIF(btrim(COALESCE(v_line ->> 'product_id', '')), '');
    IF v_pid IS NULL THEN
      CONTINUE;
    END IF;

    v_discount := GREATEST(
      COALESCE((v_line ->> 'discount_percent')::integer, 0),
      0
    );
    v_discount := LEAST(v_discount, 100);

    SELECT * INTO v_row
    FROM public.products AS p
    WHERE p.id = v_pid
    FOR UPDATE;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', format('product_not_found:%s', v_pid));
    END IF;

    IF v_row.status NOT IN ('active', 'reserved', 'hidden') THEN
      RETURN jsonb_build_object('ok', false, 'error', format('product_unavailable:%s', v_pid));
    END IF;

    v_list := GREATEST(COALESCE(v_row.sale_price, 0), 0)::bigint;
    v_final := round(v_list::numeric * (100 - v_discount) / 100.0)::bigint;
    v_store := public._norm_store_icn_ans(v_row.store_location);
    v_metal := public.classify_jewelry_metal_category(
      NULLIF(btrim(v_row.metal), ''),
      NULLIF(btrim(v_row.metal_type), '')
    );

    v_commission_pct := public.seller_commission_rate_for_metal(
      v_gold_pct,
      v_silver_pct,
      v_metal
    );
    v_commission_krw := round(
      v_final::numeric * COALESCE(v_commission_pct, 0) / 100.0
    )::integer;

    UPDATE public.products AS p
    SET
      status = 'sold',
      stock_quantity = 0,
      updated_at = now()
    WHERE p.id = v_pid;

    SELECT sh.id
    INTO v_history_id
    FROM public.sales_history AS sh
    WHERE sh.product_id = v_pid
    ORDER BY sh.sold_at_utc DESC NULLS LAST, sh.legacy_id DESC
    LIMIT 1;

    IF v_history_id IS NULL THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', format('sales_history_missing_after_trigger:%s', v_pid)
      );
    END IF;

    UPDATE public.sales_history AS sh
    SET
      price_krw = v_final,
      list_price_krw = v_list,
      discount_percent = v_discount,
      payment_method = v_payment,
      seller_code = v_seller_code,
      seller_name = v_display_seller_name,
      store_location = v_store,
      metal_category = v_metal,
      commission_percent = COALESCE(v_commission_pct, 0),
      commission_krw = COALESCE(v_commission_krw, 0),
      migration_meta = COALESCE(sh.migration_meta, '{}'::jsonb) || jsonb_build_object(
        'pos_order_id', v_order_id,
        'pos_seller_name', v_seller,
        'pos_seller_code', v_seller_code,
        'pos_payment_method', v_payment,
        'logged_by', 'archive_admin_pos_sale'
      )
    WHERE sh.id = v_history_id;
  END LOOP;

  v_sold := jsonb_array_length(p_lines);

  RETURN jsonb_build_object(
    'ok', true,
    'order_id', v_order_id,
    'lines', v_sold,
    'seller_code', v_seller_code
  );
END;
$$;

REVOKE ALL ON FUNCTION public.archive_admin_pos_sale(jsonb, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.archive_admin_pos_sale(jsonb, text, text, text)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) Бэкфилл seller_code / комиссии (ноябрь 2026+, без seller_code)
-- ---------------------------------------------------------------------------
WITH candidates AS (
  SELECT
    sh.id,
    sh.seller_name AS orig_name,
    sh.price_krw,
    r.promo_code,
    r.name AS resolved_name,
    r.gold_commission_percent,
    r.silver_commission_percent,
    COALESCE(
      sh.metal_category,
      public.classify_metal_from_sales_payload(sh.raw_legacy_payload),
      'other'
    ) AS m_cat
  FROM public.sales_history AS sh
  CROSS JOIN LATERAL public.resolve_seller_by_name(sh.seller_name) AS r
  WHERE sh.sold_date_kst >= DATE '2026-11-01'
    AND sh.price_krw > 0
    AND NULLIF(btrim(sh.seller_code), '') IS NULL
    AND NULLIF(btrim(sh.seller_name), '') IS NOT NULL
    AND r.promo_code IS NOT NULL
)
UPDATE public.sales_history AS sh
SET
  seller_code = c.promo_code,
  seller_name = CASE
    WHEN c.promo_code = 'ADMIN'
         AND lower(btrim(c.orig_name)) IN ('андрей', 'наталья')
      THEN btrim(c.orig_name)
    ELSE c.resolved_name
  END,
  metal_category = c.m_cat,
  commission_percent = CASE
    WHEN c.promo_code = 'ADMIN' THEN 0::numeric
    ELSE public.seller_commission_rate_for_metal(
      c.gold_commission_percent,
      c.silver_commission_percent,
      c.m_cat
    )
  END,
  commission_krw = CASE
    WHEN c.promo_code = 'ADMIN' THEN 0
    ELSE round(
      c.price_krw::numeric
        * public.seller_commission_rate_for_metal(
            c.gold_commission_percent,
            c.silver_commission_percent,
            c.m_cat
          ) / 100.0
    )::integer
  END
FROM candidates AS c
WHERE sh.id = c.id;

COMMIT;