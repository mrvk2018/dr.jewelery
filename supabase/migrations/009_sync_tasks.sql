-- Очередь ручной синхронизации каталога (Edge sync-catalog → локальный sync.js)

BEGIN;

CREATE TABLE IF NOT EXISTS public.sync_tasks (
  id             text PRIMARY KEY,
  sync_requested boolean NOT NULL DEFAULT false,
  updated_at     timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.sync_tasks IS
  'Тумблер импорта DrJaw→Supabase: Edge ставит sync_requested=true, sync.js сбрасывает после успеха.';
COMMENT ON COLUMN public.sync_tasks.sync_requested IS
  'true — локальный воркер должен выполнить полный sync.js';

INSERT INTO public.sync_tasks (id, sync_requested, updated_at)
VALUES ('catalog_sync', FALSE, NOW())
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.sync_tasks ENABLE ROW LEVEL SECURITY;

COMMIT;
