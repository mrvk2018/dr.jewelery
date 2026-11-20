-- 065: Отправка в трансфер (Ансан) по выбранным id черновиков.
BEGIN;

CREATE OR REPLACE FUNCTION public.send_drafts_to_ansan_by_ids(
  p_actor_code text,
  p_ids text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor text := upper(btrim(coalesce(p_actor_code, '')));
  v_count integer := 0;
BEGIN
  IF v_actor = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите код сотрудника');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.sellers AS s WHERE s.promo_code = v_actor AND s.is_active = true
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Код сотрудника не активен');
  END IF;

  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Укажите массив id черновиков');
  END IF;

  WITH updated AS (
    UPDATE public.products AS p
    SET
      status = 'in_transfer',
      updated_at = now()
  FROM unnest(p_ids) AS pid(id)
    WHERE p.id = NULLIF(btrim(pid.id), '')
      AND p.stock_quantity = 0
      AND p.status IN ('hidden', 'active')
      AND p.store_location = 'ANS'
  RETURNING 1
  )
  SELECT count(*)::integer INTO v_count FROM updated;

  RETURN jsonb_build_object('ok', true, 'sent_count', coalesce(v_count, 0));
END;
$$;

REVOKE ALL ON FUNCTION public.send_drafts_to_ansan_by_ids(text, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_drafts_to_ansan_by_ids(text, text[])
  TO anon, authenticated, service_role;

COMMIT;