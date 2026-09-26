-- Колонка для RPC checkout (reserve / release / confirm) и аудита изменений витрины.

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
