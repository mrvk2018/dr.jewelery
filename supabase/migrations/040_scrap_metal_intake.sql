-- Приёмка лома (золото → 585, серебро → 925): журнал, склад, списание.

BEGIN;

CREATE TABLE IF NOT EXISTS public.scrap_metal_intakes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  store_location text NOT NULL DEFAULT 'ICN'
    CHECK (store_location IN ('ICN', 'ANS')),
  accepted_by_code text,
  accepted_by_name text NOT NULL,
  notes text,
  photo_urls jsonb NOT NULL DEFAULT '[]'::jsonb,
  status text NOT NULL DEFAULT 'in_stock'
    CHECK (status IN ('in_stock', 'written_off')),
  written_off_at timestamptz,
  written_off_note text,
  gold_items jsonb NOT NULL DEFAULT '[]'::jsonb,
  gold_total_eq_585 numeric(12, 4) NOT NULL DEFAULT 0,
  gold_standard_rate_krw integer NOT NULL DEFAULT 0,
  gold_tradein_rate_krw integer NOT NULL DEFAULT 0,
  gold_purchase_offset_grams numeric(12, 4) NOT NULL DEFAULT 0,
  gold_tradein_paid_grams numeric(12, 4) NOT NULL DEFAULT 0,
  gold_standard_paid_grams numeric(12, 4) NOT NULL DEFAULT 0,
  gold_payout_krw integer NOT NULL DEFAULT 0,
  silver_items jsonb NOT NULL DEFAULT '[]'::jsonb,
  silver_total_eq_925 numeric(12, 4) NOT NULL DEFAULT 0,
  silver_standard_rate_krw integer NOT NULL DEFAULT 0,
  silver_tradein_rate_krw integer NOT NULL DEFAULT 0,
  silver_purchase_offset_grams numeric(12, 4) NOT NULL DEFAULT 0,
  silver_tradein_paid_grams numeric(12, 4) NOT NULL DEFAULT 0,
  silver_standard_paid_grams numeric(12, 4) NOT NULL DEFAULT 0,
  silver_payout_krw integer NOT NULL DEFAULT 0,
  total_payout_krw integer NOT NULL DEFAULT 0
);

COMMENT ON TABLE public.scrap_metal_intakes IS
  'Акты приёмки лома (скупка/обмен): склад in_stock, архив written_off.';

CREATE INDEX IF NOT EXISTS idx_scrap_metal_intakes_created_at
  ON public.scrap_metal_intakes (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_scrap_metal_intakes_store_location
  ON public.scrap_metal_intakes (store_location);

CREATE INDEX IF NOT EXISTS idx_scrap_metal_intakes_status
  ON public.scrap_metal_intakes (status);

CREATE OR REPLACE FUNCTION public.scrap_metal_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_scrap_metal_intakes_updated_at ON public.scrap_metal_intakes;
CREATE TRIGGER trg_scrap_metal_intakes_updated_at
  BEFORE UPDATE ON public.scrap_metal_intakes
  FOR EACH ROW
  EXECUTE FUNCTION public.scrap_metal_touch_updated_at();

ALTER TABLE public.scrap_metal_intakes ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public._scrap_norm_items(
  p_items jsonb,
  p_standard numeric,
  p_eq_key text
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  elem jsonb;
  result jsonb := '[]'::jsonb;
  fineness numeric;
  gross numeric;
  stone_pct numeric;
  net_w numeric;
  eq_w numeric;
  row_obj jsonb;
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RETURN '[]'::jsonb;
  END IF;
  FOR elem IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    fineness := COALESCE((elem->>'fineness')::numeric, 0);
    gross := COALESCE((elem->>'gross_weight')::numeric, 0);
    stone_pct := COALESCE((elem->>'stone_discount_percent')::numeric, 0);
    IF gross <= 0 OR fineness <= 0 THEN
      CONTINUE;
    END IF;
    net_w := gross * (1 - LEAST(GREATEST(stone_pct, 0), 100) / 100.0);
    eq_w := net_w * fineness / NULLIF(p_standard, 0);
    row_obj := jsonb_build_object(
      'fineness', fineness,
      'gross_weight', round(gross, 4),
      'stone_discount_percent', round(stone_pct, 2),
      'net_weight', round(net_w, 4)
    );
    row_obj := row_obj || jsonb_build_object(p_eq_key, round(eq_w, 4));
    result := result || jsonb_build_array(row_obj);
  END LOOP;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public._scrap_total_eq(p_items jsonb, p_eq_key text)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  elem jsonb;
  v_sum numeric := 0;
  v_part numeric;
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RETURN 0;
  END IF;
  FOR elem IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_part := COALESCE((elem->>p_eq_key)::numeric, 0);
    IF v_part > 0 THEN
      v_sum := v_sum + v_part;
    END IF;
  END LOOP;
  RETURN v_sum;
END;
$$;

CREATE OR REPLACE FUNCTION public._scrap_payout_split(
  p_total_eq numeric,
  p_offset numeric,
  p_standard_rate integer,
  p_tradein_rate integer
)
RETURNS TABLE(
  tradein_paid_grams numeric,
  standard_paid_grams numeric,
  payout_krw integer
)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_total numeric := GREATEST(COALESCE(p_total_eq, 0), 0);
  v_offset numeric := GREATEST(COALESCE(p_offset, 0), 0);
  v_tradein numeric;
  v_standard numeric;
BEGIN
  v_tradein := LEAST(v_offset, v_total);
  v_standard := GREATEST(v_total - v_tradein, 0);
  tradein_paid_grams := round(v_tradein, 4);
  standard_paid_grams := round(v_standard, 4);
  payout_krw := GREATEST(
    round(v_tradein * GREATEST(COALESCE(p_tradein_rate, 0), 0))::integer
    + round(v_standard * GREATEST(COALESCE(p_standard_rate, 0), 0))::integer,
    0
  );
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_scrap_metal_intake(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_store text;
  v_gold_items jsonb;
  v_silver_items jsonb;
  v_gold_total numeric;
  v_silver_total numeric;
  v_gold_split record;
  v_silver_split record;
  v_row public.scrap_metal_intakes%ROWTYPE;
BEGIN
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Некорректный payload');
  END IF;

  v_store := upper(btrim(COALESCE(p_payload->>'store_location', 'ICN')));
  IF v_store NOT IN ('ICN', 'ANS') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Магазин должен быть ICN или ANS');
  END IF;

  IF NULLIF(btrim(COALESCE(p_payload->>'accepted_by_name', '')), '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите, кто принял лом');
  END IF;

  v_gold_items := public._scrap_norm_items(
    COALESCE(p_payload->'gold_items', '[]'::jsonb),
    585,
    'equivalent_585_weight'
  );
  v_silver_items := public._scrap_norm_items(
    COALESCE(p_payload->'silver_items', '[]'::jsonb),
    925,
    'equivalent_925_weight'
  );

  v_gold_total := public._scrap_total_eq(v_gold_items, 'equivalent_585_weight');
  v_silver_total := public._scrap_total_eq(v_silver_items, 'equivalent_925_weight');

  SELECT * INTO v_gold_split FROM public._scrap_payout_split(
    v_gold_total,
    COALESCE((p_payload->>'gold_purchase_offset_grams')::numeric, 0),
    COALESCE((p_payload->>'gold_standard_rate_krw')::integer, 0),
    COALESCE((p_payload->>'gold_tradein_rate_krw')::integer, 0)
  );

  SELECT * INTO v_silver_split FROM public._scrap_payout_split(
    v_silver_total,
    COALESCE((p_payload->>'silver_purchase_offset_grams')::numeric, 0),
    COALESCE((p_payload->>'silver_standard_rate_krw')::integer, 0),
    COALESCE((p_payload->>'silver_tradein_rate_krw')::integer, 0)
  );

  v_id := NULLIF(btrim(COALESCE(p_payload->>'id', '')), '')::uuid;

  IF v_id IS NULL THEN
    INSERT INTO public.scrap_metal_intakes (
      store_location,
      accepted_by_code,
      accepted_by_name,
      notes,
      photo_urls,
      status,
      gold_items,
      gold_total_eq_585,
      gold_standard_rate_krw,
      gold_tradein_rate_krw,
      gold_purchase_offset_grams,
      gold_tradein_paid_grams,
      gold_standard_paid_grams,
      gold_payout_krw,
      silver_items,
      silver_total_eq_925,
      silver_standard_rate_krw,
      silver_tradein_rate_krw,
      silver_purchase_offset_grams,
      silver_tradein_paid_grams,
      silver_standard_paid_grams,
      silver_payout_krw,
      total_payout_krw
    ) VALUES (
      v_store,
      NULLIF(btrim(COALESCE(p_payload->>'accepted_by_code', '')), ''),
      btrim(p_payload->>'accepted_by_name'),
      NULLIF(btrim(COALESCE(p_payload->>'notes', '')), ''),
      COALESCE(p_payload->'photo_urls', '[]'::jsonb),
      'in_stock',
      v_gold_items,
      v_gold_total,
      GREATEST(COALESCE((p_payload->>'gold_standard_rate_krw')::integer, 0), 0),
      GREATEST(COALESCE((p_payload->>'gold_tradein_rate_krw')::integer, 0), 0),
      GREATEST(COALESCE((p_payload->>'gold_purchase_offset_grams')::numeric, 0), 0),
      v_gold_split.tradein_paid_grams,
      v_gold_split.standard_paid_grams,
      v_gold_split.payout_krw,
      v_silver_items,
      v_silver_total,
      GREATEST(COALESCE((p_payload->>'silver_standard_rate_krw')::integer, 0), 0),
      GREATEST(COALESCE((p_payload->>'silver_tradein_rate_krw')::integer, 0), 0),
      GREATEST(COALESCE((p_payload->>'silver_purchase_offset_grams')::numeric, 0), 0),
      v_silver_split.tradein_paid_grams,
      v_silver_split.standard_paid_grams,
      v_silver_split.payout_krw,
      v_gold_split.payout_krw + v_silver_split.payout_krw
    )
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('ok', true, 'id', v_id::text);
  END IF;

  UPDATE public.scrap_metal_intakes AS s
  SET
    store_location = v_store,
    accepted_by_code = NULLIF(btrim(COALESCE(p_payload->>'accepted_by_code', '')), ''),
    accepted_by_name = btrim(p_payload->>'accepted_by_name'),
    notes = NULLIF(btrim(COALESCE(p_payload->>'notes', '')), ''),
    photo_urls = COALESCE(p_payload->'photo_urls', '[]'::jsonb),
    gold_items = v_gold_items,
    gold_total_eq_585 = v_gold_total,
    gold_standard_rate_krw = GREATEST(COALESCE((p_payload->>'gold_standard_rate_krw')::integer, 0), 0),
    gold_tradein_rate_krw = GREATEST(COALESCE((p_payload->>'gold_tradein_rate_krw')::integer, 0), 0),
    gold_purchase_offset_grams = GREATEST(COALESCE((p_payload->>'gold_purchase_offset_grams')::numeric, 0), 0),
    gold_tradein_paid_grams = v_gold_split.tradein_paid_grams,
    gold_standard_paid_grams = v_gold_split.standard_paid_grams,
    gold_payout_krw = v_gold_split.payout_krw,
    silver_items = v_silver_items,
    silver_total_eq_925 = v_silver_total,
    silver_standard_rate_krw = GREATEST(COALESCE((p_payload->>'silver_standard_rate_krw')::integer, 0), 0),
    silver_tradein_rate_krw = GREATEST(COALESCE((p_payload->>'silver_tradein_rate_krw')::integer, 0), 0),
    silver_purchase_offset_grams = GREATEST(COALESCE((p_payload->>'silver_purchase_offset_grams')::numeric, 0), 0),
    silver_tradein_paid_grams = v_silver_split.tradein_paid_grams,
    silver_standard_paid_grams = v_silver_split.standard_paid_grams,
    silver_payout_krw = v_silver_split.payout_krw,
    total_payout_krw = v_gold_split.payout_krw + v_silver_split.payout_krw
  WHERE s.id = v_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Акт не найден');
  END IF;

  RETURN jsonb_build_object('ok', true, 'id', v_id::text);
END;
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

CREATE OR REPLACE FUNCTION public.write_off_scrap_metal_intakes(
  p_ids uuid[],
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer := 0;
BEGIN
  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Выберите акты для списания');
  END IF;

  UPDATE public.scrap_metal_intakes AS s
  SET
    status = 'written_off',
    written_off_at = now(),
    written_off_note = NULLIF(btrim(COALESCE(p_note, '')), '')
  WHERE s.id = ANY (p_ids)
    AND s.status = 'in_stock';

  GET DIAGNOSTICS v_count = ROW_COUNT;

  IF v_count = 0 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Нет актов на складе с указанными id'
    );
  END IF;

  RETURN jsonb_build_object('ok', true, 'written_off', v_count);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_scrap_metal_intake(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите id');
  END IF;

  DELETE FROM public.scrap_metal_intakes WHERE id = p_id;

  IF FOUND THEN
    RETURN jsonb_build_object('ok', true);
  END IF;

  RETURN jsonb_build_object('ok', false, 'error', 'Акт не найден');
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_scrap_metal_intake(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_scrap_metal_intakes(text, text, text, date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.write_off_scrap_metal_intakes(uuid[], text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_scrap_metal_intake(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.upsert_scrap_metal_intake(jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_scrap_metal_intakes(text, text, text, date, date) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.write_off_scrap_metal_intakes(uuid[], text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.delete_scrap_metal_intake(uuid) TO anon, authenticated, service_role;

COMMIT;