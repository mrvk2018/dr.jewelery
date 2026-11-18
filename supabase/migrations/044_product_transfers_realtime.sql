-- Realtime для бейджа трансферов в админ-PWA (postgres_changes на product_transfers).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'product_transfers'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.product_transfers;
  END IF;
END
$$;