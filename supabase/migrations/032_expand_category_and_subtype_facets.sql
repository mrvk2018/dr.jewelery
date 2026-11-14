-- Расширение фасетов категорий витрины (10 типов + name::text).

BEGIN;

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
  n text;
  f text;
BEGIN
  c := lower(btrim(COALESCE(p.category, '')));
  n := lower(COALESCE(p.name::text, ''));
  f := lower(btrim(COALESCE(facet, '')));
  IF f = '' THEN
    RETURN false;
  END IF;

  CASE f
    WHEN 'кольцо' THEN
      RETURN c LIKE '%кольц%' OR n LIKE '%кольц%' OR c LIKE '%обручаль%' OR n LIKE '%обручаль%';
    WHEN 'серьги' THEN
      RETURN c LIKE '%серьг%' OR n LIKE '%серьг%'
        OR c LIKE '%пуссет%' OR n LIKE '%пуссет%'
        OR c LIKE '%пусет%' OR n LIKE '%пусет%'
        OR c LIKE '%кафф%' OR n LIKE '%кафф%'
        OR c LIKE '%конго%' OR n LIKE '%конго%'
        OR c LIKE '%продёв%' OR n LIKE '%продёв%'
        OR c LIKE '%продев%' OR n LIKE '%продев%';
    WHEN 'цепь' THEN
      RETURN c LIKE '%цеп%' OR n LIKE '%цеп%';
    WHEN 'подвески', 'подвеска' THEN
      RETURN c LIKE '%подвес%' OR n LIKE '%подвес%'
        OR c LIKE '%икон%' OR n LIKE '%икон%';
    WHEN 'крест' THEN
      RETURN c LIKE '%крест%' OR n LIKE '%крест%';
    WHEN 'колье' THEN
      RETURN c LIKE '%колье%' OR n LIKE '%колье%';
    WHEN 'браслет' THEN
      RETURN c LIKE '%браслет%' OR n LIKE '%браслет%';
    WHEN 'браслет (женский)' THEN
      RETURN c LIKE '%браслет (женский)%' OR n LIKE '%браслет (женский)%'
        OR (c LIKE '%браслет%' AND c LIKE '%жен%')
        OR (n LIKE '%браслет%' AND n LIKE '%жен%');
    WHEN 'браслет (мужской)' THEN
      RETURN c LIKE '%браслет (мужский)%' OR n LIKE '%браслет (мужский)%'
        OR (c LIKE '%браслет%' AND c LIKE '%муж%')
        OR (n LIKE '%браслет%' AND n LIKE '%муж%');
    WHEN 'пирсинг' THEN
      RETURN c LIKE '%пирсинг%' OR n LIKE '%пирсинг%';
    WHEN 'гайтан' THEN
      RETURN c LIKE '%гайтан%' OR n LIKE '%гайтан%';
    WHEN 'брошь' THEN
      RETURN c LIKE '%брош%' OR n LIKE '%брош%';
    ELSE
      RETURN c LIKE '%' || f || '%' OR n LIKE '%' || f || '%';
  END CASE;
END;
$$;

COMMENT ON FUNCTION public.showroom_category_facet_match(public.products, text) IS
  'Сопоставление чипа категории с products.category и products.name (ILIKE, 10+ типов).';

COMMIT;