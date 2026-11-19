-- Синхронизация products.size_value <-> products.available_sizes (склад + ручной ввод).

BEGIN;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS size_value numeric;

COMMENT ON COLUMN public.products.size_value IS
  'Размер изделия (число); дублируется в available_sizes[0] триггером sync_product_size_fields.';

-- ---------------------------------------------------------------------------
-- Первое положительное число в jsonb-массиве available_sizes
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._product_first_positive_size_from_array(
  p_sizes jsonb
)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_sizes jsonb;
  v_len int;
  v_i int;
  v_elem text;
  v_num numeric;
BEGIN
  IF p_sizes IS NULL OR jsonb_typeof(p_sizes) IS DISTINCT FROM 'array' THEN
    RETURN NULL;
  END IF;

  v_sizes := p_sizes;
  v_len := jsonb_array_length(v_sizes);
  IF v_len IS NULL OR v_len <= 0 THEN
    RETURN NULL;
  END IF;

  FOR v_i IN 0 .. v_len - 1 LOOP
    v_elem := NULLIF(btrim(v_sizes ->> v_i), '');
    IF v_elem IS NULL THEN
      CONTINUE;
    END IF;
    BEGIN
      v_num := replace(v_elem, ',', '.')::numeric;
    EXCEPTION
      WHEN others THEN
        v_num := NULL;
    END;
    IF v_num IS NOT NULL AND v_num > 0 THEN
      RETURN v_num;
    END IF;
  END LOOP;

  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- BEFORE INSERT/UPDATE: выравнивание size_value и available_sizes
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_product_size_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_first numeric;
  v_sizes_changed boolean;
  v_size_changed boolean;
  v_avail_empty boolean;
BEGIN
  v_sizes_changed := TG_OP = 'UPDATE'
    AND NEW.available_sizes IS DISTINCT FROM OLD.available_sizes;
  v_size_changed := TG_OP = 'UPDATE'
    AND NEW.size_value IS DISTINCT FROM OLD.size_value;

  v_avail_empty := NEW.available_sizes IS NULL
    OR jsonb_typeof(NEW.available_sizes) IS DISTINCT FROM 'array'
    OR jsonb_array_length(NEW.available_sizes) = 0;

  IF TG_OP = 'INSERT' THEN
    IF NEW.size_value IS NOT NULL AND NEW.size_value > 0 THEN
      IF v_avail_empty THEN
        NEW.available_sizes := jsonb_build_array(NEW.size_value);
      END IF;
    ELSIF NEW.size_value IS NULL THEN
      v_first := public._product_first_positive_size_from_array(NEW.available_sizes);
      IF v_first IS NOT NULL THEN
        NEW.size_value := v_first;
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF v_size_changed THEN
    IF NEW.size_value IS NOT NULL AND NEW.size_value > 0 THEN
      IF NOT v_sizes_changed OR v_avail_empty THEN
        NEW.available_sizes := jsonb_build_array(NEW.size_value);
      END IF;
    ELSIF NEW.size_value IS NULL THEN
      IF NOT v_sizes_changed THEN
        NEW.available_sizes := '[]'::jsonb;
      END IF;
    END IF;
  END IF;

  IF v_sizes_changed THEN
    v_first := public._product_first_positive_size_from_array(NEW.available_sizes);
    IF v_first IS NOT NULL THEN
      NEW.size_value := v_first;
    ELSIF v_avail_empty AND NOT v_size_changed THEN
      NEW.size_value := NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_sync_size_fields ON public.products;

CREATE TRIGGER trg_products_sync_size_fields
  BEFORE INSERT OR UPDATE OF size_value, available_sizes
  ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_product_size_fields();

-- ---------------------------------------------------------------------------
-- Backfill: выровнять существующие строки
-- ---------------------------------------------------------------------------
UPDATE public.products AS p
SET size_value = public._product_first_positive_size_from_array(p.available_sizes)
WHERE (p.size_value IS NULL OR p.size_value <= 0)
  AND public._product_first_positive_size_from_array(p.available_sizes) IS NOT NULL;

UPDATE public.products AS p
SET available_sizes = jsonb_build_array(p.size_value)
WHERE p.size_value IS NOT NULL
  AND p.size_value > 0
  AND (
    p.available_sizes IS NULL
    OR jsonb_typeof(p.available_sizes) IS DISTINCT FROM 'array'
    OR jsonb_array_length(p.available_sizes) = 0
  );

COMMIT;

-- Проверка (результат в SQL Editor)
SELECT
  count(*) FILTER (WHERE status = 'active' AND stock_quantity > 0) AS total_active,
  count(*) FILTER (
    WHERE status = 'active'
      AND stock_quantity > 0
      AND size_value IS NOT NULL
      AND size_value > 0
  ) AS with_size_value,
  count(*) FILTER (
    WHERE status = 'active'
      AND stock_quantity > 0
      AND available_sizes IS NOT NULL
      AND jsonb_typeof(available_sizes) = 'array'
      AND jsonb_array_length(available_sizes) > 0
  ) AS with_available_sizes
FROM public.products;