-- 072: подвид «Кольцо · помолвочное» (Flutter kJewelryCategorySubtypes + фасет витрины).
-- Схема: products.name (jsonb), products.category, products.notes — text без CHECK/ENUM на подвид.
-- RPC update_draft_product / ручное создание пишут name->>'ru' как «Кольцо · помолвочное».
BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_singular_category_subtype_text(t text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            regexp_replace(
              regexp_replace(
                regexp_replace(
                  regexp_replace(
                    regexp_replace(
                      regexp_replace(
                        coalesce(t, ''),
                        'Подвески ·', 'Подвеска ·', 'gi'
                      ),
                      'Подвески', 'Подвеска', 'gi'
                    ),
                    'Кольцо · обручальные', 'Кольцо · обручальное', 'gi'
                  ),
                  'Кольцо · помолвочные', 'Кольцо · помолвочное', 'gi'
                ),
                'Кольцо · печатки', 'Кольцо · печатка', 'gi'
              ),
              'Кольцо · декоративные', 'Кольцо · декоративное', 'gi'
            ),
            'Подвеска · декоративные', 'Подвеска · декоративная', 'gi'
          ),
          'Подвеска · знаки зодиака', 'Подвеска · знак зодиака', 'gi'
        ),
        'Подвеска · православные', 'Подвеска · православная', 'gi'
      ),
      'Подвеска · мусульманские', 'Подвеска · мусульманская', 'gi'
    );
$$;

COMMENT ON FUNCTION public.normalize_singular_category_subtype_text(text) IS
  'Ед.ч. в строках «Категория · вид» (+ помолвочные→помолвочное).';

CREATE OR REPLACE FUNCTION public.showroom_advanced_facet_match(
  p public.products,
  facet text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
PARALLEL SAFE
AS $$
DECLARE
  f text;
  blob text;
BEGIN
  f := lower(btrim(coalesce(facet, '')));
  IF f = '' THEN
    RETURN false;
  END IF;

  blob := public.facet_homoglyph_normalize(public.product_facet_search_blob(p));

  IF f = 'без вставок' THEN
    RETURN (
      coalesce(nullif(btrim(p.gem_inserts::text), ''), nullif(btrim(p."insert"), ''), '') = ''
      OR coalesce(nullif(btrim(p.gem_inserts::text), ''), nullif(btrim(p."insert"), ''), '') IN ('—', '-')
      OR coalesce(p."insert", '') ILIKE '%без вставок%'
      OR coalesce(p."insert", '') ILIKE '%без камней%'
      OR coalesce(p.gem_inserts::text, '') ILIKE '%без вставок%'
      OR coalesce(p.gem_inserts::text, '') ILIKE '%без камней%'
    );
  END IF;

  IF f IN ('пусеты', 'пусет', 'пуссет') THEN
    RETURN blob ~ '(пусс?ет|гвозд)';
  END IF;

  IF f = 'гвозд' OR f LIKE 'гвозд%' THEN
    RETURN blob ~ 'гвозд';
  END IF;

  IF f IN ('продёвки', 'продёв', 'продев') THEN
    RETURN blob ~ '(продёв|продев)';
  END IF;

  IF f IN ('обручальное', 'обручальные', 'обручальн') THEN
    RETURN blob ~ 'обручальн';
  END IF;

  IF f IN ('помолвочное', 'помолвочные', 'помолвочн') THEN
    RETURN blob ~ 'помолвочн';
  END IF;

  IF f IN ('печатка', 'печатки', 'печатк') THEN
    RETURN blob ~ 'печатк';
  END IF;

  IF f = 'декоративное' THEN
    RETURN blob ~ 'декоративн' AND blob ~ 'кольц';
  END IF;

  IF f = 'декоративная' THEN
    RETURN blob ~ 'декоративн' AND blob ~ 'подвес';
  END IF;

  IF f IN ('декоративные', 'декоративн') THEN
    RETURN blob ~ 'декоративн'
      AND (blob ~ 'серьг' OR blob ~ 'пусс?ет' OR blob ~ 'кафф' OR blob ~ 'конго');
  END IF;

  IF f IN ('знак зодиака', 'знаки зодиака', 'зодиак') THEN
    RETURN blob ~ 'зодиак';
  END IF;

  IF f IN ('православная', 'православные', 'православн') THEN
    RETURN blob ~ 'православн';
  END IF;

  IF f IN ('мусульманская', 'мусульманские', 'мусульманск') THEN
    RETURN blob ~ 'мусульманск';
  END IF;

  RETURN blob LIKE '%' || f || '%';
END;
$$;

COMMENT ON FUNCTION public.showroom_advanced_facet_match(public.products, text) IS
  'Фасет подвида; помолвочн* для обручальное/помолвочное/печатка и др.';

-- Backfill legacy мн.ч. в name / notes (идемпотентно)
UPDATE public.products AS p
SET
  name =
    COALESCE(p.name, '{}'::jsonb)
    || CASE
      WHEN coalesce(p.name->>'ru', '') ~* 'помолвочные'
        THEN jsonb_build_object(
          'ru',
          public.normalize_singular_category_subtype_text(p.name->>'ru')
        )
      ELSE '{}'::jsonb
    END
    || CASE
      WHEN coalesce(p.name->>'ko', '') ~* 'помолвочные'
        THEN jsonb_build_object(
          'ko',
          public.normalize_singular_category_subtype_text(p.name->>'ko')
        )
      ELSE '{}'::jsonb
    END
    || CASE
      WHEN coalesce(p.name->>'en', '') ~* 'помолвочные'
        THEN jsonb_build_object(
          'en',
          public.normalize_singular_category_subtype_text(p.name->>'en')
        )
      ELSE '{}'::jsonb
    END,
  updated_at = now()
WHERE coalesce(p.name->>'ru', '') ~* 'Кольцо · помолвочные'
   OR coalesce(p.name->>'ko', '') ~* 'Кольцо · помолвочные'
   OR coalesce(p.name->>'en', '') ~* 'Кольцо · помолвочные';

UPDATE public.products
SET
  notes = public.normalize_singular_category_subtype_text(notes),
  updated_at = now()
WHERE coalesce(notes, '') ~* 'Кольцо · помолвочные';

COMMIT;