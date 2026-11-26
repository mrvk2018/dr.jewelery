-- 078: журнал лома по фактическому весу и пробе.
-- Деньги кассы не трогаются: выплата уже прошла в момент приёмки или Trade-In.
-- Вес строки — net_weight (г металла после скидки на камни), не equivalent_585/925.

BEGIN;

CREATE TABLE IF NOT EXISTS public.scrap_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch text NOT NULL CHECK (branch IN ('ICN', 'ANS')),
  purity text NOT NULL CHECK (btrim(purity) <> ''),
  movement_type text NOT NULL CHECK (
    movement_type IN ('intake', 'trade_in', 'write_off', 'adjustment')
  ),
  weight_delta_g numeric(12, 3) NOT NULL CHECK (weight_delta_g <> 0),
  source_id text,
  source_table text,
  recipient_or_reason text,
  comment text,
  seller_code text,
  created_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT scrap_ledger_delta_sign CHECK (
    (movement_type IN ('intake', 'trade_in') AND weight_delta_g > 0)
    OR (movement_type = 'write_off' AND weight_delta_g < 0)
    OR movement_type = 'adjustment'
  )
);

COMMENT ON TABLE public.scrap_ledger IS
  'Движения лома в граммах по филиалу и пробе. Не касса и не денежный эквивалент.';

CREATE INDEX IF NOT EXISTS idx_scrap_ledger_branch_purity
  ON public.scrap_ledger (branch, purity);

CREATE INDEX IF NOT EXISTS idx_scrap_ledger_created_at
  ON public.scrap_ledger (created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS scrap_ledger_source_purity_uidx
  ON public.scrap_ledger (source_table, source_id, purity)
  WHERE source_id IS NOT NULL;

ALTER TABLE public.scrap_ledger ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public._scrap_num(p_text text)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_text IS NULL OR btrim(p_text) = '' THEN NULL
    WHEN btrim(p_text) ~ '^-?[0-9]+(\.[0-9]+)?$' THEN btrim(p_text)::numeric
    ELSE NULL
  END;
$$;

CREATE OR REPLACE FUNCTION public._scrap_ledger_purity(p_fineness numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_fineness IS NULL OR p_fineness <= 0 THEN NULL
    WHEN p_fineness = trunc(p_fineness)
      THEN trunc(p_fineness)::integer::text
    ELSE rtrim(rtrim(to_char(p_fineness, 'FM999990.999'), '0'), '.')
  END;
$$;

-- Чистый вес грамма металла. equivalent_* намеренно не читается.
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
    3
  );
$$;

CREATE OR REPLACE FUNCTION public._scrap_ledger_sync_intake(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.scrap_metal_intakes%ROWTYPE;
  v_branch text;
  v_type text;
  v_purity text;
  v_weight numeric;
BEGIN
  SELECT * INTO v_row
  FROM public.scrap_metal_intakes
  WHERE id = p_id;

  IF NOT FOUND THEN
    DELETE FROM public.scrap_ledger
    WHERE source_id = p_id::text
      AND source_table IN (
        'scrap_metal_intakes',
        'scrap_metal_intake_writeoffs',
        'scrap_trade_in_returns'
      );
    RETURN;
  END IF;

  v_branch := COALESCE(public._norm_store_icn_ans(v_row.store_location), 'ICN');
  v_type := CASE WHEN v_row.is_trade_in THEN 'trade_in' ELSE 'intake' END;

  DELETE FROM public.scrap_ledger
  WHERE source_id = p_id::text
    AND source_table = 'scrap_metal_intakes';

  FOR v_purity, v_weight IN
    WITH items AS (
      SELECT value AS elem
      FROM jsonb_array_elements(COALESCE(v_row.gold_items, '[]'::jsonb))
      UNION ALL
      SELECT value
      FROM jsonb_array_elements(COALESCE(v_row.silver_items, '[]'::jsonb))
    )
    SELECT
      public._scrap_ledger_purity(public._scrap_num(elem ->> 'fineness')) AS purity,
      round(sum(public._scrap_item_net_g(elem)), 3) AS weight_g
    FROM items
    GROUP BY 1
  LOOP
    IF v_purity IS NULL OR v_weight IS NULL OR v_weight <= 0 THEN
      CONTINUE;
    END IF;

    INSERT INTO public.scrap_ledger (
      branch, purity, movement_type, weight_delta_g,
      source_id, source_table, comment, seller_code, created_by, created_at
    ) VALUES (
      v_branch,
      v_purity,
      v_type,
      v_weight,
      p_id::text,
      'scrap_metal_intakes',
      v_row.notes,
      v_row.accepted_by_code,
      v_row.accepted_by_name,
      v_row.created_at
    );
  END LOOP;

  DELETE FROM public.scrap_ledger
  WHERE source_id = p_id::text
    AND source_table = 'scrap_metal_intake_writeoffs';

  IF v_row.status = 'written_off' THEN
    INSERT INTO public.scrap_ledger (
      branch, purity, movement_type, weight_delta_g,
      source_id, source_table, recipient_or_reason,
      seller_code, created_by, created_at
    )
    SELECT
      l.branch,
      l.purity,
      'write_off',
      round(-l.weight_delta_g, 3),
      p_id::text,
      'scrap_metal_intake_writeoffs',
      COALESCE(NULLIF(btrim(v_row.written_off_note), ''), 'Списание акта приёмки'),
      COALESCE(v_row.accepted_by_code, v_row.transferred_by_code),
      COALESCE(v_row.accepted_by_name, v_row.transferred_by_name),
      COALESCE(v_row.written_off_at, now())
    FROM public.scrap_ledger AS l
    WHERE l.source_id = p_id::text
      AND l.source_table = 'scrap_metal_intakes'
      AND l.weight_delta_g > 0;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._scrap_ledger_reverse_trade_in_if_batch_closed(
  p_batch text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch text := NULLIF(btrim(COALESCE(p_batch, '')), '');
  v_open boolean;
  v_intake public.scrap_metal_intakes%ROWTYPE;
BEGIN
  IF v_batch IS NULL THEN
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.sales_history AS s
    WHERE s.sale_batch_id = v_batch
      AND s.price_krw > 0
      AND NOT EXISTS (
        SELECT 1
        FROM public.sales_history AS r
        WHERE r.price_krw < 0
          AND (r.migration_meta ->> 'reverses_legacy_id') = s.legacy_id
      )
  ) INTO v_open;

  IF v_open THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.sales_history AS s
    WHERE s.sale_batch_id = v_batch
      AND s.price_krw > 0
  ) THEN
    RETURN;
  END IF;

  FOR v_intake IN
    SELECT *
    FROM public.scrap_metal_intakes
    WHERE sale_batch_id = v_batch
      AND is_trade_in
  LOOP
    INSERT INTO public.scrap_ledger (
      branch, purity, movement_type, weight_delta_g,
      source_id, source_table, recipient_or_reason, seller_code, created_by
    )
    SELECT
      l.branch,
      l.purity,
      'write_off',
      round(-l.weight_delta_g, 3),
      v_intake.id::text,
      'scrap_trade_in_returns',
      'Возврат чека Trade-In',
      l.seller_code,
      l.created_by
    FROM public.scrap_ledger AS l
    WHERE l.source_id = v_intake.id::text
      AND l.source_table = 'scrap_metal_intakes'
      AND l.weight_delta_g > 0
    ON CONFLICT (source_table, source_id, purity) WHERE source_id IS NOT NULL
    DO NOTHING;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_scrap_ledger_on_intake()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.scrap_ledger
    WHERE source_id = OLD.id::text
      AND source_table IN (
        'scrap_metal_intakes',
        'scrap_metal_intake_writeoffs',
        'scrap_trade_in_returns'
      );
    RETURN OLD;
  END IF;

  PERFORM public._scrap_ledger_sync_intake(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_scrap_ledger_on_intake ON public.scrap_metal_intakes;
CREATE TRIGGER trg_scrap_ledger_on_intake
  AFTER INSERT OR UPDATE OR DELETE ON public.scrap_metal_intakes
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_scrap_ledger_on_intake();

CREATE OR REPLACE FUNCTION public.trg_scrap_ledger_on_sale_return()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.price_krw < 0 AND NEW.sale_batch_id IS NOT NULL THEN
    PERFORM public._scrap_ledger_reverse_trade_in_if_batch_closed(NEW.sale_batch_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_scrap_ledger_on_sale_return ON public.sales_history;
CREATE TRIGGER trg_scrap_ledger_on_sale_return
  AFTER INSERT ON public.sales_history
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_scrap_ledger_on_sale_return();

-- Бэкфилл: приход по актам и списание уже закрытых актов / полностью возвращённых Trade-In.
SELECT public._scrap_ledger_sync_intake(s.id)
FROM public.scrap_metal_intakes AS s;

SELECT public._scrap_ledger_reverse_trade_in_if_batch_closed(s.sale_batch_id)
FROM (
  SELECT DISTINCT sale_batch_id
  FROM public.scrap_metal_intakes
  WHERE is_trade_in
    AND sale_batch_id IS NOT NULL
) AS s;

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
      round(COALESCE(sum(l.weight_delta_g), 0), 3) AS total_weight_g,
      round(COALESCE(sum(l.weight_delta_g) FILTER (WHERE l.weight_delta_g > 0), 0), 3) AS total_intake_g,
      round(COALESCE(-sum(l.weight_delta_g) FILTER (WHERE l.weight_delta_g < 0), 0), 3) AS total_writeoff_g,
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
      round(COALESCE(sum(l.weight_delta_g), 0), 3) AS total_weight_g,
      round(COALESCE(sum(l.weight_delta_g) FILTER (WHERE l.weight_delta_g > 0), 0), 3) AS total_intake_g,
      round(COALESCE(-sum(l.weight_delta_g) FILTER (WHERE l.weight_delta_g < 0), 0), 3) AS total_writeoff_g,
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
    'total_weight_g', round(COALESCE(sum(l.weight_delta_g), 0), 3),
    'total_intake_g', round(COALESCE(sum(l.weight_delta_g) FILTER (WHERE l.weight_delta_g > 0), 0), 3),
    'total_writeoff_g', round(COALESCE(-sum(l.weight_delta_g) FILTER (WHERE l.weight_delta_g < 0), 0), 3),
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
  -- Только граммы. sales_history / касса смены не изменяются.
  v_branch := public._norm_store_icn_ans(p_branch);
  IF v_branch IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_branch');
  END IF;

  v_purity := public._scrap_ledger_purity(public._scrap_num(p_purity));
  IF v_purity IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_purity');
  END IF;

  v_weight := round(COALESCE(p_weight_g, 0), 3);
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

  SELECT round(COALESCE(sum(weight_delta_g), 0), 3)
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
    'balance_g', round(v_balance - v_weight, 3)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.list_scrap_ledger(
  p_branch text DEFAULT NULL,
  p_purity text DEFAULT NULL,
  p_filter text DEFAULT 'all',
  p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch text := NULLIF(upper(btrim(COALESCE(p_branch, ''))), '');
  v_purity text := NULLIF(btrim(COALESCE(p_purity, '')), '');
  v_filter text := lower(btrim(COALESCE(p_filter, 'all')));
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_total integer;
  v_rows jsonb;
BEGIN
  IF v_branch IN ('', 'ALL') THEN
    v_branch := NULL;
  ELSIF public._norm_store_icn_ans(v_branch) IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_branch');
  ELSE
    v_branch := public._norm_store_icn_ans(v_branch);
  END IF;

  IF v_purity IS NOT NULL THEN
    v_purity := COALESCE(public._scrap_ledger_purity(public._scrap_num(v_purity)), v_purity);
  END IF;

  IF v_filter IN ('', 'all', 'все') THEN
    v_filter := 'all';
  ELSIF v_filter IN ('intake', 'in', 'приход') THEN
    v_filter := 'intake';
  ELSIF v_filter IN ('write_off', 'writeoff', 'out', 'списание') THEN
    v_filter := 'write_off';
  ELSE
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_filter');
  END IF;

  IF p_date_from IS NOT NULL AND p_date_to IS NOT NULL AND p_date_from > p_date_to THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_range');
  END IF;

  SELECT count(*)::integer
  INTO v_total
  FROM public.scrap_ledger AS l
  WHERE (v_branch IS NULL OR l.branch = v_branch)
    AND (v_purity IS NULL OR l.purity = v_purity)
    AND (
      v_filter = 'all'
      OR (v_filter = 'intake' AND l.movement_type IN ('intake', 'trade_in'))
      OR (v_filter = 'write_off' AND l.movement_type IN ('write_off', 'adjustment'))
    )
    AND (
      p_date_from IS NULL
      OR (l.created_at AT TIME ZONE 'Asia/Seoul')::date >= p_date_from
    )
    AND (
      p_date_to IS NULL
      OR (l.created_at AT TIME ZONE 'Asia/Seoul')::date <= p_date_to
    );

  SELECT COALESCE(jsonb_agg(to_jsonb(page) ORDER BY page.created_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      l.id,
      l.branch,
      l.purity,
      l.movement_type,
      l.weight_delta_g,
      l.source_id,
      l.source_table,
      l.recipient_or_reason,
      l.comment,
      l.seller_code,
      l.created_by,
      l.created_at
    FROM public.scrap_ledger AS l
    WHERE (v_branch IS NULL OR l.branch = v_branch)
      AND (v_purity IS NULL OR l.purity = v_purity)
      AND (
        v_filter = 'all'
        OR (v_filter = 'intake' AND l.movement_type IN ('intake', 'trade_in'))
        OR (v_filter = 'write_off' AND l.movement_type IN ('write_off', 'adjustment'))
      )
      AND (
        p_date_from IS NULL
        OR (l.created_at AT TIME ZONE 'Asia/Seoul')::date >= p_date_from
      )
      AND (
        p_date_to IS NULL
        OR (l.created_at AT TIME ZONE 'Asia/Seoul')::date <= p_date_to
      )
    ORDER BY l.created_at DESC
    LIMIT v_limit
    OFFSET v_offset
  ) AS page;

  RETURN jsonb_build_object(
    'ok', true,
    'total', v_total,
    'rows', v_rows
  );
END;
$$;

REVOKE ALL ON FUNCTION public._scrap_num(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._scrap_ledger_purity(numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._scrap_item_net_g(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._scrap_ledger_sync_intake(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._scrap_ledger_reverse_trade_in_if_batch_closed(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_scrap_ledger_on_intake() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_scrap_ledger_on_sale_return() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.get_scrap_balances(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.write_off_scrap(text, text, numeric, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_scrap_ledger(text, text, text, date, date, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_scrap_balances(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.write_off_scrap(text, text, numeric, text, text, text, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_scrap_ledger(text, text, text, date, date, integer, integer) TO anon, authenticated, service_role;

COMMIT;
