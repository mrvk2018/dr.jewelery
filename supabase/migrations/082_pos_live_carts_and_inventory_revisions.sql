-- POS live cart (per auth.uid) + collaborative showroom inventory (QR revision).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) pos_user_cart_items
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pos_user_cart_items (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  product_id        text NOT NULL REFERENCES public.products (id) ON DELETE CASCADE,
  discount_percent  integer NOT NULL DEFAULT 0
    CHECK (discount_percent IN (0, 3, 5, 7, 10, 15, 20)),
  sort_order        integer NOT NULL DEFAULT 0,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pos_user_cart_items_user_product_unique UNIQUE (user_id, product_id)
);

CREATE INDEX IF NOT EXISTS pos_user_cart_items_user_idx
  ON public.pos_user_cart_items (user_id, sort_order);

COMMENT ON TABLE public.pos_user_cart_items IS
  'Живая POS-корзина веб-панели: синхронизация между устройствами одного auth.uid().';

ALTER TABLE public.pos_user_cart_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pos_user_cart_items_select_own ON public.pos_user_cart_items;
DROP POLICY IF EXISTS pos_user_cart_items_insert_own ON public.pos_user_cart_items;
DROP POLICY IF EXISTS pos_user_cart_items_update_own ON public.pos_user_cart_items;
DROP POLICY IF EXISTS pos_user_cart_items_delete_own ON public.pos_user_cart_items;

CREATE POLICY pos_user_cart_items_select_own
  ON public.pos_user_cart_items FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY pos_user_cart_items_insert_own
  ON public.pos_user_cart_items FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY pos_user_cart_items_update_own
  ON public.pos_user_cart_items FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY pos_user_cart_items_delete_own
  ON public.pos_user_cart_items FOR DELETE TO authenticated
  USING (user_id = auth.uid());

REVOKE ALL ON TABLE public.pos_user_cart_items FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.pos_user_cart_items TO authenticated;

-- ---------------------------------------------------------------------------
-- 2) inventory_sessions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.inventory_sessions (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  status                 text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'completed', 'cancelled')),
  branch_scope           text NOT NULL
    CHECK (branch_scope IN ('ICN', 'ANS', 'ALL')),
  started_by_user_id     uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  started_by_name        text NOT NULL DEFAULT '',
  started_at             timestamptz NOT NULL DEFAULT now(),
  completed_at           timestamptz,
  expected_product_ids   text[] NOT NULL DEFAULT '{}',
  expected_count         integer NOT NULL DEFAULT 0,
  summary                jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at             timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS inventory_sessions_one_active_idx
  ON public.inventory_sessions ((status))
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS inventory_sessions_completed_at_idx
  ON public.inventory_sessions (completed_at DESC NULLS LAST)
  WHERE status = 'completed';

COMMENT ON TABLE public.inventory_sessions IS
  'Совместная QR-ревизия витрин; одна активная сессия на проект.';

ALTER TABLE public.inventory_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS inventory_sessions_select_authenticated ON public.inventory_sessions;
DROP POLICY IF EXISTS inventory_sessions_insert_authenticated ON public.inventory_sessions;
DROP POLICY IF EXISTS inventory_sessions_update_authenticated ON public.inventory_sessions;

CREATE POLICY inventory_sessions_select_authenticated
  ON public.inventory_sessions FOR SELECT TO authenticated
  USING (true);

CREATE POLICY inventory_sessions_insert_authenticated
  ON public.inventory_sessions FOR INSERT TO authenticated
  WITH CHECK (started_by_user_id = auth.uid());

CREATE POLICY inventory_sessions_update_authenticated
  ON public.inventory_sessions FOR UPDATE TO authenticated
  USING (true)
  WITH CHECK (true);

REVOKE ALL ON TABLE public.inventory_sessions FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE ON TABLE public.inventory_sessions TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) inventory_session_scans
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.inventory_session_scans (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id          uuid NOT NULL REFERENCES public.inventory_sessions (id) ON DELETE CASCADE,
  product_id          text REFERENCES public.products (id) ON DELETE SET NULL,
  scanned_by_user_id  uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  scanned_by_name     text NOT NULL DEFAULT '',
  scan_result         text NOT NULL
    CHECK (scan_result IN ('matched', 'wrong_store', 'wrong_status', 'unknown')),
  raw_payload         text NOT NULL DEFAULT '',
  product_sku         text NOT NULL DEFAULT '',
  store_location      text,
  product_status      text,
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS inventory_session_scans_session_product_uidx
  ON public.inventory_session_scans (session_id, product_id)
  WHERE product_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS inventory_session_scans_session_created_idx
  ON public.inventory_session_scans (session_id, created_at DESC);

ALTER TABLE public.inventory_session_scans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS inventory_session_scans_select_authenticated ON public.inventory_session_scans;
DROP POLICY IF EXISTS inventory_session_scans_insert_authenticated ON public.inventory_session_scans;

CREATE POLICY inventory_session_scans_select_authenticated
  ON public.inventory_session_scans FOR SELECT TO authenticated
  USING (true);

CREATE POLICY inventory_session_scans_insert_authenticated
  ON public.inventory_session_scans FOR INSERT TO authenticated
  WITH CHECK (scanned_by_user_id = auth.uid());

REVOKE ALL ON TABLE public.inventory_session_scans FROM PUBLIC;
GRANT SELECT, INSERT ON TABLE public.inventory_session_scans TO authenticated;

-- ---------------------------------------------------------------------------
-- 4) Helpers + RPC
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._inventory_resolve_product(p_payload text)
RETURNS public.products
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_raw text := btrim(COALESCE(p_payload, ''));
  v_row public.products%ROWTYPE;
BEGIN
  IF v_raw = '' THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_row FROM public.products WHERE id = v_raw LIMIT 1;
  IF FOUND THEN
    RETURN v_row;
  END IF;

  SELECT * INTO v_row FROM public.products WHERE qr_code_payload = v_raw LIMIT 1;
  IF FOUND THEN
    RETURN v_row;
  END IF;

  SELECT * INTO v_row
  FROM public.products
  WHERE lower(btrim(sku)) = lower(btrim(v_raw))
  ORDER BY updated_at DESC NULLS LAST, id DESC
  LIMIT 1;
  IF FOUND THEN
    RETURN v_row;
  END IF;

  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.inventory_start_session(
  p_branch_scope text,
  p_starter_name text DEFAULT ''
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch text;
  v_ids text[];
  v_cnt integer;
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501';
  END IF;

  v_branch := upper(btrim(COALESCE(p_branch_scope, 'ALL')));
  IF v_branch NOT IN ('ICN', 'ANS', 'ALL') THEN
    RAISE EXCEPTION 'invalid_branch' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (SELECT 1 FROM public.inventory_sessions s WHERE s.status = 'active') THEN
    RAISE EXCEPTION 'active_session_exists' USING ERRCODE = '23505';
  END IF;

  SELECT coalesce(array_agg(p.id ORDER BY p.sku), '{}')
  INTO v_ids
  FROM public.products p
  WHERE p.status = 'active'
    AND p.stock_quantity > 0
    AND (
      v_branch = 'ALL'
      OR upper(btrim(COALESCE(p.store_location, 'ICN'))) = v_branch
    );

  v_cnt := coalesce(array_length(v_ids, 1), 0);

  INSERT INTO public.inventory_sessions (
    status,
    branch_scope,
    started_by_user_id,
    started_by_name,
    expected_product_ids,
    expected_count
  )
  VALUES (
    'active',
    v_branch,
    auth.uid(),
    btrim(COALESCE(p_starter_name, '')),
    v_ids,
    v_cnt
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.inventory_record_scan(
  p_session_id uuid,
  p_raw_payload text,
  p_scanner_name text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.inventory_sessions%ROWTYPE;
  v_row public.products%ROWTYPE;
  v_result text;
  v_store text;
  v_existing public.inventory_session_scans%ROWTYPE;
  v_scan_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_session
  FROM public.inventory_sessions
  WHERE id = p_session_id AND status = 'active';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'session_not_active');
  END IF;

  v_row := public._inventory_resolve_product(p_raw_payload);

  IF v_row.id IS NULL THEN
    v_result := 'unknown';
    INSERT INTO public.inventory_session_scans (
      session_id,
      product_id,
      scanned_by_user_id,
      scanned_by_name,
      scan_result,
      raw_payload,
      product_sku
    )
    VALUES (
      p_session_id,
      NULL,
      auth.uid(),
      btrim(COALESCE(p_scanner_name, '')),
      v_result,
      btrim(COALESCE(p_raw_payload, '')),
      ''
    )
  RETURNING id INTO v_scan_id;

    RETURN jsonb_build_object(
      'ok', true,
      'duplicate', false,
      'scan_id', v_scan_id,
      'scan_result', v_result
    );
  END IF;

  SELECT * INTO v_existing
  FROM public.inventory_session_scans
  WHERE session_id = p_session_id AND product_id = v_row.id;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok', true,
      'duplicate', true,
      'scan_result', v_existing.scan_result,
      'scanned_by_name', v_existing.scanned_by_name,
      'product_id', v_row.id,
      'product_sku', v_row.sku
    );
  END IF;

  v_store := upper(btrim(COALESCE(v_row.store_location, 'ICN')));

  IF v_row.status <> 'active' OR v_row.stock_quantity <= 0 THEN
    v_result := 'wrong_status';
  ELSIF v_session.branch_scope <> 'ALL' AND v_store <> v_session.branch_scope THEN
    v_result := 'wrong_store';
  ELSE
    v_result := 'matched';
  END IF;

  INSERT INTO public.inventory_session_scans (
    session_id,
    product_id,
    scanned_by_user_id,
    scanned_by_name,
    scan_result,
    raw_payload,
    product_sku,
    store_location,
    product_status
  )
  VALUES (
    p_session_id,
    v_row.id,
    auth.uid(),
    btrim(COALESCE(p_scanner_name, '')),
    v_result,
    btrim(COALESCE(p_raw_payload, '')),
    COALESCE(v_row.sku, ''),
    v_store,
    COALESCE(v_row.status, '')
  )
  RETURNING id INTO v_scan_id;

  RETURN jsonb_build_object(
    'ok', true,
    'duplicate', false,
    'scan_id', v_scan_id,
    'scan_result', v_result,
    'product_id', v_row.id,
    'product_sku', v_row.sku
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.inventory_complete_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.inventory_sessions%ROWTYPE;
  v_matched integer;
  v_wrong integer;
  v_unknown integer;
  v_scanned_product_ids text[];
  v_missing text[];
  v_summary jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_session
  FROM public.inventory_sessions
  WHERE id = p_session_id AND status = 'active'
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'session_not_active');
  END IF;

  SELECT
    count(*) FILTER (WHERE scan_result = 'matched'),
    count(*) FILTER (WHERE scan_result IN ('wrong_store', 'wrong_status')),
    count(*) FILTER (WHERE scan_result = 'unknown')
  INTO v_matched, v_wrong, v_unknown
  FROM public.inventory_session_scans
  WHERE session_id = p_session_id;

  SELECT coalesce(array_agg(DISTINCT product_id), '{}')
  INTO v_scanned_product_ids
  FROM public.inventory_session_scans
  WHERE session_id = p_session_id
    AND product_id IS NOT NULL
    AND scan_result = 'matched';

  SELECT coalesce(array_agg(eid), '{}')
  INTO v_missing
  FROM unnest(v_session.expected_product_ids) AS eid
  WHERE eid IS NOT NULL
    AND NOT (eid = ANY (v_scanned_product_ids));

  v_summary := jsonb_build_object(
    'matched', v_matched,
    'wrong_store_or_status', v_wrong,
    'unknown', v_unknown,
    'expected', v_session.expected_count,
    'missing_count', coalesce(array_length(v_missing, 1), 0),
    'missing_product_ids', to_jsonb(v_missing)
  );

  UPDATE public.inventory_sessions
  SET status = 'completed',
      completed_at = now(),
      summary = v_summary
  WHERE id = p_session_id;

  RETURN jsonb_build_object('ok', true, 'summary', v_summary);
END;
$$;

CREATE OR REPLACE FUNCTION public.pos_user_cart_clear()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM public.pos_user_cart_items WHERE user_id = auth.uid();
  SELECT true;
$$;

GRANT EXECUTE ON FUNCTION public.inventory_start_session(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.inventory_record_scan(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.inventory_complete_session(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pos_user_cart_clear() TO authenticated;

-- ---------------------------------------------------------------------------
-- 5) Realtime publication
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'pos_user_cart_items'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.pos_user_cart_items;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'inventory_sessions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.inventory_sessions;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'inventory_session_scans'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.inventory_session_scans;
  END IF;
END
$$;

COMMIT;