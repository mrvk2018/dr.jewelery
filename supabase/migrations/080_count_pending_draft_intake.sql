-- Счётчик непринятых черновиков для бейджа «Приёмка черновиков» (как search_draft_products без фильтра).
CREATE OR REPLACE FUNCTION public.count_pending_draft_intake()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count bigint;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.products AS p
  WHERE p.stock_quantity = 0
    AND p.status IN ('hidden', 'active', 'in_transfer');

  RETURN jsonb_build_object('ok', true, 'count', COALESCE(v_count, 0));
END;
$$;

REVOKE ALL ON FUNCTION public.count_pending_draft_intake() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.count_pending_draft_intake()
  TO anon, authenticated, service_role;