-- 085: Шаблон переходящих остатков лома только в public.scrap_ledger
-- (без scrap_metal_intakes, sales_history, кассы).
--
-- Схема public.scrap_ledger (миграция 078, уточнение округления в 084):
--
-- | Колонка              | Тип            | Ограничения |
-- |----------------------|----------------|-------------|
-- | id                   | uuid PK        | DEFAULT gen_random_uuid() |
-- | branch               | text NOT NULL  | IN ('ICN', 'ANS') |
-- | purity               | text NOT NULL  | btrim(purity) <> '' (проба: '375','585','750','925', …) |
-- | movement_type        | text NOT NULL  | IN ('intake','trade_in','write_off','adjustment') |
-- | weight_delta_g       | numeric(12,3)  | <> 0; знак см. scrap_ledger_delta_sign |
-- | source_id            | text           | NULL — опционально, для идемпотентности |
-- | source_table         | text           | NULL |
-- | recipient_or_reason  | text           | NULL |
-- | comment              | text           | NULL |
-- | seller_code          | text           | NULL |
-- | created_by           | text           | NULL |
-- | created_at           | timestamptz    | NOT NULL DEFAULT now() |
--
-- scrap_ledger_delta_sign:
--   intake, trade_in  → weight_delta_g > 0
--   write_off         → weight_delta_g < 0
--   adjustment        → любой знак (≠ 0)
--
-- Уникальность (идемпотентность): scrap_ledger_source_purity_uidx
--   UNIQUE (source_table, source_id, purity) WHERE source_id IS NOT NULL
--
-- Как учитывается в get_scrap_balances (084):
--   total_weight_g   = sum(weight_delta_g)
--   total_intake_g   = sum(weight_delta_g) FILTER (WHERE weight_delta_g > 0)
--   total_writeoff_g = -sum(weight_delta_g) FILTER (WHERE weight_delta_g < 0)
--   Положительный opening всегда увеличивает остаток и total_intake_g.
--
-- Как учитывается в list_scrap_ledger (078):
--   фильтр all      → все строки
--   фильтр intake   → movement_type IN ('intake', 'trade_in')  — НЕ adjustment
--   фильтр write_off→ movement_type IN ('write_off', 'adjustment')
--
-- Рекомендация для переходящих остатков:
--   movement_type = 'intake', weight_delta_g > 0, source_table = 'opening_balance',
--   стабильный source_id на пару (филиал, проба) — видно в «Приход» и в остатках.
--   adjustment (+) тоже суммируется в остаток, но в UI попадёт в фильтр «Списание».
--
-- Перед раскомментированием INSERT замените веса и даты. Повторный запуск миграции
-- не дублирует строки за счёт ON CONFLICT по (source_table, source_id, purity).

BEGIN;

-- ---------------------------------------------------------------------------
-- Шаблон: одна строка на филиал + проба (раскомментируйте и подставьте веса)
-- ---------------------------------------------------------------------------
/*
INSERT INTO public.scrap_ledger (
  branch,
  purity,
  movement_type,
  weight_delta_g,
  source_id,
  source_table,
  recipient_or_reason,
  comment,
  seller_code,
  created_by,
  created_at
) VALUES
  -- Инчхон · золото 585°
  (
    'ICN',
    '585',
    'intake',
    24.55,
    'ICN:585',
    'opening_balance',
    'Переходящий остаток на дату внедрения учёта',
    'Начальный остаток склада (миграция 085). Без акта приёмки и без движения кассы.',
    NULL,
    'ADMIN',
    timestamptz '2025-01-01 09:00:00+00'
  ),
  -- Инчхон · золото 750°
  (
    'ICN',
    '750',
    'intake',
    27.47,
    'ICN:750',
    'opening_balance',
    'Переходящий остаток на дату внедрения учёта',
    'Начальный остаток склада (миграция 085).',
    NULL,
    'ADMIN',
    timestamptz '2025-01-01 09:00:00+00'
  ),
  -- Ансан · золото 585°
  (
    'ANS',
    '585',
    'intake',
    2.56,
    'ANS:585',
    'opening_balance',
    'Переходящий остаток на дату внедрения учёта',
    'Начальный остаток склада (миграция 085).',
    NULL,
    'ADMIN',
    timestamptz '2025-01-01 09:00:00+00'
  )
ON CONFLICT (source_table, source_id, purity) WHERE source_id IS NOT NULL
DO NOTHING;
*/

-- ---------------------------------------------------------------------------
-- Альтернатива: корректировка (adjustment) — только если нужен любой знак;
-- положительный вес в get_scrap_balances идёт в total_intake_g, в list «Приход»
-- не попадёт (только «Все» или фильтр write_off из-за типа adjustment).
-- ---------------------------------------------------------------------------
/*
INSERT INTO public.scrap_ledger (
  branch, purity, movement_type, weight_delta_g,
  source_id, source_table, recipient_or_reason, comment, created_by
) VALUES (
  'ICN', '585', 'adjustment', 1.23,
  'ADJ-ICN-585-2025-01',
  'opening_balance',
  'Инвентаризационная корректировка (+)',
  'Корректировка остатка без акта.',
  'ADMIN'
)
ON CONFLICT (source_table, source_id, purity) WHERE source_id IS NOT NULL
DO NOTHING;
*/

-- Проверка после вставки (ручной запуск в SQL Editor):
-- SELECT public.get_scrap_balances('ALL');
-- SELECT public.list_scrap_ledger('ALL', NULL, 'all', NULL, NULL, 100, 0);

COMMIT;