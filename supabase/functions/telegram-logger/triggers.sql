-- Database Webhook → Edge Function `telegram-logger`
-- Требования: расширение pg_net (Supabase: Database → Extensions → pg_net).
--
-- Перед запуском замените плейсхолдеры:
--   :PROJECT_REF     — ref проекта Supabase (subdomain)
--   :SERVICE_ROLE    — service_role key (Dashboard → Settings → API)
--
-- Секреты Telegram задаются только на Edge Function:
--   supabase secrets set TELEGRAM_BOT_TOKEN=... TELEGRAM_CHAT_ID=...

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.telegram_logger_webhook()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  payload jsonb;
  edge_url text := 'https://:PROJECT_REF.supabase.co/functions/v1/telegram-logger';
  service_key text := ':SERVICE_ROLE';
BEGIN
  payload := jsonb_build_object(
    'type', TG_OP,
    'table', TG_TABLE_NAME,
    'schema', TG_TABLE_SCHEMA,
    'record', to_jsonb(NEW),
    'old_record', CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END
  );

  PERFORM net.http_post(
    url := edge_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_key
    ),
    body := payload
  );

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.telegram_logger_webhook() IS
  'POST в Edge Function telegram-logger (продажи products, трансферы product_transfers).';

DROP TRIGGER IF EXISTS product_transfers_telegram_logger_insert ON public.product_transfers;
CREATE TRIGGER product_transfers_telegram_logger_insert
  AFTER INSERT ON public.product_transfers
  FOR EACH ROW
  EXECUTE FUNCTION public.telegram_logger_webhook();

DROP TRIGGER IF EXISTS product_transfers_telegram_logger_update ON public.product_transfers;
CREATE TRIGGER product_transfers_telegram_logger_update
  AFTER UPDATE ON public.product_transfers
  FOR EACH ROW
  EXECUTE FUNCTION public.telegram_logger_webhook();

DROP TRIGGER IF EXISTS products_telegram_logger_update ON public.products;
CREATE TRIGGER products_telegram_logger_update
  AFTER UPDATE ON public.products
  FOR EACH ROW
  WHEN (
    OLD.product_status IS DISTINCT FROM NEW.product_status
    OR OLD.status IS DISTINCT FROM NEW.status
  )
  EXECUTE FUNCTION public.telegram_logger_webhook();

COMMIT;
