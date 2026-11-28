-- 084: продавцы — полное чтение лома/истории (все филиалы), вес лома до сотых.
BEGIN;

CREATE OR REPLACE FUNCTION public._scrap_item_net_g(p_elem jsonb)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT round(
    CASE
      WHEN COALESCE(public._scrap_num(p_elem ->> 'net_weight'), 0) > 0
        THEN public._scrap_num(p_elem ->> 'net_weight')
      ELSE
        COALESCE(public._scrap_num(p_elem ->> 'gross_weight'), 0)
        * (
          1 - LEAST(
            GREATEST(COALESCE(public._scrap_num(p_elem ->> 'stone_discount_percent'), 0), 0),
            100
          ) / 100.0
        )
    END,
    2
  );
$$;

CREATE OR REPLACE FUNCTION public.list_scrap_metal_intakes(
  p_store_location text DEFAULT NULL,
  p_metal text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT NULL
)
RETURNS SETOF public.scrap_metal_intakes
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_store text := NULLIF(upper(btrim(COALESCE(p_store_location, ''))), '');
  v_metal text := lower(btrim(COALESCE(p_metal, '')));
  v_status text := lower(btrim(COALESCE(p_status, '')));
BEGIN
  IF v_store IN ('', 'ALL') THEN
    v_store := NULL;
  END IF;

  RETURN QUERY
  SELECT s.*
  FROM public.scrap_metal_intakes AS s
  WHERE
    (v_store IS NULL OR s.store_location = v_store)
    AND (
      v_metal IS NULL OR v_metal = '' OR v_metal = 'all'
      OR (v_metal = 'gold' AND s.gold_total_eq_585 > 0)
      OR (v_metal = 'silver' AND s.silver_total_eq_925 > 0)
    )
    AND (
      v_status IS NULL OR v_status = '' OR v_status = 'all'
      OR s.status = v_status
    )
    AND (
      p_date_from IS NULL
      OR (s.created_at AT TIME ZONE 'Asia/Seoul')::date >= p_date_from
    )
    AND (
      p_date_to IS NULL
      OR (s.created_at AT TIME ZONE 'Asia/Seoul')::date <= p_date_to
    )
  ORDER BY s.created_at DESC
  LIMIT 1000;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_scrap_balances(p_branch text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch text := NULLIF(upper(btrim(COALESCE(p_branch, ''))), '');
  v_rows jsonb;
  v_by_branch jsonb;
  v_grand jsonb;
BEGIN
  IF v_branch IN ('', 'ALL') THEN
    v_branch := NULL;
  ELSIF public._norm_store_icn_ans(v_branch) IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_branch');
  ELSE
    v_branch := public._norm_store_icn_ans(v_branch);
  END IF;

  WITH grouped AS (
    SELECT
      l.branch,
      l.purity,
      round(COALESCE(sum(l.weight_delta_g), 0), 2) AS total_weight_g,
      round(COALESCE(sum(l.weight_delta_g) FILTER (WHERE l.weight_delta_g > 0), 0), 2) AS total_intake_g,
      round(COALESCE(-sum(l.weight_delta_g) FILTER (WHERE l.weight_delta_g < 0), 0), 2) AS total_writeoff_g,
      count(*)::integer AS operation_count
    FROM public.scrap_ledger AS l
    WHERE v_branch IS NULL OR l.branch = v_branch
    GROUP BY l.branch, l.purity
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'branch', g.branch,
      'purity', g.purity,
      'total_weight_g', g.total_weight_g,
      'total_intake_g', g.total_intake_g,
      'total_writeoff_g', g.total_writeoff_g,
      'operation_count', g.operation_count
    )
    ORDER BY g.branch, g.purity
  ), '[]'::jsonb)
  INTO v_rows
  FROM grouped AS g;

  WITH by_branch AS (
    SELECT
      l.branch,
      round(COALESCE(sum(l.weight_delta_g), 0), 2) AS total_weight_g,
      round(COALESCE(sum(l.weight_delta_g) FILTER (WHERE l.weight_delta_g > 0), 0), 2) AS total_intake_g,
      round(COALESCE(-sum(l.weight_delta_g) FILTER (WHERE l.weight_delta_g < 0), 0), 2) AS total_writeoff_g,
      count(*)::integer AS operation_count
    FROM public.scrap_ledger AS l
    WHERE v_branch IS NULL OR l.branch = v_branch
    GROUP BY l.branch
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'branch', b.branch,
      'total_weight_g', b.total_weight_g,
      'total_intake_g', b.total_intake_g,
      'total_writeoff_g', b.total_writeoff_g,
      'operation_count', b.operation_count
    )
    ORDER BY b.branch
  ), '[]'::jsonb)
  INTO v_by_branch
  FROM by_branch AS b;

  SELECT jsonb_build_object(
    'total_weight_g', round(COALESCE(sum(l.weight_delta_g), 0), 2),
    'total_intake_g', round(COALESCE(sum(l.weight_delta_g) FILTER (WHERE l.weight_delta_g > 0), 0), 2),
    'total_writeoff_g', round(COALESCE(-sum(l.weight_delta_g) FILTER (WHERE l.weight_delta_g < 0), 0), 2),
    'operation_count', count(*)::integer
  )
  INTO v_grand
  FROM public.scrap_ledger AS l
  WHERE v_branch IS NULL OR l.branch = v_branch;

  RETURN jsonb_build_object(
    'ok', true,
    'branch', COALESCE(v_branch, 'ALL'),
    'rows', v_rows,
    'by_branch', v_by_branch,
    'total', v_grand
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.write_off_scrap(
  p_branch text,
  p_purity text,
  p_weight_g numeric,
  p_movement_type text DEFAULT 'write_off',
  p_recipient_or_reason text DEFAULT NULL,
  p_comment text DEFAULT NULL,
  p_seller_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch text;
  v_purity text;
  v_weight numeric;
  v_type text := lower(btrim(COALESCE(p_movement_type, 'write_off')));
  v_reason text := NULLIF(btrim(COALESCE(p_recipient_or_reason, '')), '');
  v_balance numeric := 0;
  v_id uuid;
BEGIN
  v_branch := public._norm_store_icn_ans(p_branch);
  IF v_branch IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_branch');
  END IF;

  v_purity := public._scrap_ledger_purity(public._scrap_num(p_purity));
  IF v_purity IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_purity');
  END IF;

  v_weight := round(COALESCE(p_weight_g, 0), 2);
  IF v_weight <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_weight');
  END IF;

  IF v_type NOT IN ('write_off', 'adjustment') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_movement_type');
  END IF;

  IF v_type = 'write_off' AND v_reason IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'recipient_required');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_branch || ':' || v_purity, 0));

  PERFORM 1
  FROM public.scrap_ledger
  WHERE branch = v_branch
    AND purity = v_purity
  FOR UPDATE;

  SELECT round(COALESCE(sum(weight_delta_g), 0), 2)
  INTO v_balance
  FROM public.scrap_ledger
  WHERE branch = v_branch
    AND purity = v_purity;

  IF v_balance < v_weight THEN
    RAISE EXCEPTION 'insufficient_scrap_weight'
      USING ERRCODE = 'P0001',
            DETAIL = format('balance_g=%s requested_g=%s', v_balance, v_weight);
  END IF;

  INSERT INTO public.scrap_ledger (
    branch,
    purity,
    movement_type,
    weight_delta_g,
    recipient_or_reason,
    comment,
    seller_code,
    created_by
  ) VALUES (
    v_branch,
    v_purity,
    v_type,
    -v_weight,
    v_reason,
    NULLIF(btrim(COALESCE(p_comment, '')), ''),
    NULLIF(upper(btrim(COALESCE(p_seller_code, ''))), ''),
    NULLIF(upper(btrim(COALESCE(p_seller_code, ''))), '')
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'ok', true,
    'id', v_id,
    'branch', v_branch,
    'purity', v_purity,
    'movement_type', v_type,
    'weight_delta_g', -v_weight,
    'balance_g', round(v_balance - v_weight, 2)
  );
END;
$$;

DROP POLICY IF EXISTS scrap_metal_intakes_select_authenticated
  ON public.scrap_metal_intakes;
CREATE POLICY scrap_metal_intakes_select_authenticated
  ON public.scrap_metal_intakes FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS scrap_ledger_select_authenticated ON public.scrap_ledger;
CREATE POLICY scrap_ledger_select_authenticated
  ON public.scrap_ledger FOR SELECT TO authenticated
  USING (true);

GRANT EXECUTE ON FUNCTION public.list_scrap_metal_intakes(text, text, text, date, date)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_scrap_balances(text)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_scrap_ledger(text, text, text, date, date, integer, integer)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.write_off_scrap(text, text, numeric, text, text, text, text)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_sales_history_report(date, date, text, integer, integer)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_sales_history_summary(date, date, text)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_shift_cash_summary(date, date, text, text)
  TO anon, authenticated, service_role;

COMMIT;