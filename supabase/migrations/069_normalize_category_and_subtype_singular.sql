-- 069: единственное число категорий/подвидов в products + stem-фасеты (после 068).
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
                      coalesce(t, ''),
                      'Подвески ·', 'Подвеска ·', 'gi'
                    ),
                    'Подвески', 'Подвеска', 'gi'
                  ),
                  'Кольцо · обручальные', 'Кольцо · обручальное', 'gi'
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
  'Фасет подвида: основы слов (ед./мн.ч.), пусеты, декоративн* с контекстом категории.';

CREATE OR REPLACE FUNCTION public.showroom_category_facet_match(
  p public.products,
  facet text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
PARALLEL SAFE
AS $$
DECLARE
  c text;
  blob text;
  f text;
BEGIN
  c := lower(btrim(coalesce(p.category, '')));
  blob := public.facet_homoglyph_normalize(public.product_facet_search_blob(p));
  f := lower(btrim(coalesce(facet, '')));
  IF f = '' THEN
    RETURN false;
  END IF;

  CASE f
    WHEN 'кольцо' THEN
      RETURN c LIKE '%кольц%' OR blob LIKE '%кольц%' OR blob LIKE '%обручаль%';
    WHEN 'серьги' THEN
      RETURN blob ~ '(серьг|пусс?ет|гвозд|кафф|конго|продёв|продев)';
    WHEN 'цепь' THEN
      RETURN c LIKE '%цеп%' OR blob LIKE '%цеп%';
    WHEN 'подвески', 'подвеска' THEN
      RETURN c LIKE '%подвес%' OR blob LIKE '%подвес%'
        OR blob LIKE '%икон%';
    WHEN 'крест' THEN
      RETURN c LIKE '%крест%' OR blob LIKE '%крест%';
    WHEN 'колье' THEN
      RETURN c LIKE '%колье%' OR blob LIKE '%колье%';
    WHEN 'браслет' THEN
      RETURN c LIKE '%браслет%' OR blob LIKE '%браслет%';
    WHEN 'браслет (женский)' THEN
      RETURN c LIKE '%браслет (женский)%' OR blob LIKE '%браслет (женский)%'
        OR (c LIKE '%браслет%' AND c LIKE '%жен%')
        OR (blob LIKE '%браслет%' AND blob LIKE '%жен%');
    WHEN 'браслет (мужской)' THEN
      RETURN c LIKE '%браслет (мужский)%' OR blob LIKE '%браслет (мужский)%'
        OR (c LIKE '%браслет%' AND c LIKE '%муж%')
        OR (blob LIKE '%браслет%' AND blob LIKE '%муж%');
    WHEN 'пирсинг' THEN
      RETURN c LIKE '%пирсинг%' OR blob LIKE '%пирсинг%';
    WHEN 'гайтан' THEN
      RETURN c LIKE '%гайтан%' OR blob LIKE '%гайтан%';
    WHEN 'брошь' THEN
      RETURN c LIKE '%брош%' OR blob LIKE '%брош%';
    ELSE
      RETURN c LIKE '%' || f || '%' OR blob LIKE '%' || f || '%';
  END CASE;
END;
$$;

COMMENT ON FUNCTION public.showroom_category_facet_match(public.products, text) IS
  'Чип категории: подвески/подвеска, серьги+пусеты, …';

-- ─── Предпросмотр (можно выполнить отдельно до COMMIT) ───
-- SELECT 'category Подвески->Подвеска' AS step, count(*) AS rows
-- FROM public.products WHERE category = 'Подвески';

DO $$
DECLARE
  v_cat int;
  v_name int;
  v_notes int;
  v_wh int;
BEGIN
  SELECT count(*) INTO v_cat FROM public.products WHERE category = 'Подвески';

  SELECT count(*) INTO v_name
  FROM public.products p
  WHERE coalesce(p.name::text, '') ~* 'Подвески|обручальные|печатки|знаки зодиака|православные|мусульманские'
    AND (
      coalesce(p.name->>'ru', '') <> public.normalize_singular_category_subtype_text(p.name->>'ru')
      OR coalesce(p.name->>'ko', '') <> public.normalize_singular_category_subtype_text(coalesce(p.name->>'ko', ''))
      OR coalesce(p.name->>'en', '') <> public.normalize_singular_category_subtype_text(coalesce(p.name->>'en', ''))
    );

  SELECT count(*) INTO v_notes
  FROM public.products
  WHERE coalesce(notes, '') ~* 'Подвески ·|Кольцо · обручальные|Кольцо · печатки|Кольцо · декоративные';

  SELECT count(*) INTO v_wh
  FROM public.products
  WHERE warehouse_attributes::text ~* 'Подвески ·|Кольцо · обручальные';

  RAISE NOTICE '069 backfill preview: category=% name_locales=% notes=% warehouse_attributes=%',
    v_cat, v_name, v_notes, v_wh;
END $$;

UPDATE public.products
SET category = 'Подвеска'
WHERE category = 'Подвески';

UPDATE public.products p
SET name =
  COALESCE(p.name, '{}'::jsonb)
  || CASE
    WHEN p.name ? 'ru' AND coalesce(p.name->>'ru', '') <> ''
      THEN jsonb_build_object(
        'ru',
        public.normalize_singular_category_subtype_text(p.name->>'ru')
      )
    ELSE '{}'::jsonb
  END
  || CASE
    WHEN p.name ? 'ko' AND coalesce(p.name->>'ko', '') <> ''
      THEN jsonb_build_object(
        'ko',
        public.normalize_singular_category_subtype_text(p.name->>'ko')
      )
    ELSE '{}'::jsonb
  END
  || CASE
    WHEN p.name ? 'en' AND coalesce(p.name->>'en', '') <> ''
      THEN jsonb_build_object(
        'en',
        public.normalize_singular_category_subtype_text(p.name->>'en')
      )
    ELSE '{}'::jsonb
  END
WHERE p.name IS NOT NULL
  AND (
    coalesce(p.name->>'ru', '') ~* 'Подвески|Кольцо · (обручальные|печатки|декоративные)|Подвески ·'
    OR coalesce(p.name->>'ko', '') ~* 'Подвески|Кольцо · (обручальные|печатки|декоративные)|Подвески ·'
    OR coalesce(p.name->>'en', '') ~* 'Подвески|Кольцо · (обручальные|печатки|декоративные)|Подвески ·'
    OR coalesce(p.name->>'ru', '') ~* 'Подвес(ка|ки) · (декоративные|знаки зодиака|православные|мусульманские)'
    OR coalesce(p.name->>'ko', '') ~* 'Подвес(ка|ки) · (декоративные|знаки зодиака|православные|мусульманские)'
    OR coalesce(p.name->>'en', '') ~* 'Подвес(ка|ки) · (декоративные|знаки зодиака|православные|мусульманские)'
  );

UPDATE public.products
SET notes = public.normalize_singular_category_subtype_text(notes)
WHERE coalesce(notes, '') ~* 'Подвески|Кольцо · обручальные|Кольцо · печатки|Кольцо · декоративные';

UPDATE public.products
SET warehouse_attributes = (
  SELECT jsonb_object_agg(
    e.key,
    CASE
      WHEN jsonb_typeof(e.value) = 'string' THEN
        to_jsonb(public.normalize_singular_category_subtype_text(e.value #>> '{}'))
      ELSE e.value
    END
  )
  FROM jsonb_each(COALESCE(warehouse_attributes, '{}'::jsonb)) AS e(key, value)
)
WHERE warehouse_attributes::text ~* 'Подвески|Кольцо · обручальные|Кольцо · печатки';

COMMIT;