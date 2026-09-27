-- RLS: клиент (authenticated) может читать статус очереди sync_tasks для опроса импорта.
-- UPDATE/INSERT/DELETE — только service_role (Edge sync-catalog, sync.js); политик записи нет.

BEGIN;

DROP POLICY IF EXISTS sync_tasks_authenticated_select ON public.sync_tasks;

CREATE POLICY sync_tasks_authenticated_select
  ON public.sync_tasks
  FOR SELECT
  TO authenticated
  USING (true);

COMMENT ON POLICY sync_tasks_authenticated_select ON public.sync_tasks IS
  'Админ-приложение опрашивает sync_requested после вызова Edge sync-catalog.';

COMMIT;
