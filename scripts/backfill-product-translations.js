/**
 * Доперевод public.products (name / description JSONB) через бесплатный Google Translate.
 *
 * Env (.env в корне jewelry_sunlight_store):
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 *
 * Запуск:
 *   npm run translate:backfill
 *   DRY_RUN=1 npm run translate:backfill   — без записи в БД
 */

require('dotenv').config();

const ws = require('ws');
const { createClient } = require('@supabase/supabase-js');
const translate = require('google-translate-api-x');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const DRY_RUN = process.env.DRY_RUN === '1' || process.env.DRY_RUN === 'true';

const SOURCE_LANG = 'ru';
const TARGET_LANGS = ['ko', 'kk', 'uz', 'en'];
const PAGE_SIZE = 500;
const CHUNK_SIZE = Number(process.env.TRANSLATE_CHUNK_SIZE || 4);
const MIN_DELAY_MS = Number(process.env.TRANSLATE_MIN_DELAY_MS || 3000);
const MAX_DELAY_MS = Number(process.env.TRANSLATE_MAX_DELAY_MS || 6000);
const RATE_LIMIT_PAUSE_MS = Number(process.env.TRANSLATE_RATE_LIMIT_MS || 150000);
/** Ниже или равно — не переводим (артикулы/цифры часто одинаковы во всех языках). */
const MIN_RU_SOURCE_LEN = Number(process.env.MIN_RU_SOURCE_LEN || 4);

function requireEnv() {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error(
      'Задайте SUPABASE_URL и SUPABASE_SERVICE_ROLE_KEY в .env (service_role).',
    );
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function randomDelayMs() {
  return (
    MIN_DELAY_MS +
    Math.floor(Math.random() * (MAX_DELAY_MS - MIN_DELAY_MS + 1))
  );
}

function isRateLimitError(err) {
  const message = (err && err.message) || String(err);
  return /too many requests/i.test(message) || err?.code === 429;
}

function normalizeMap(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return {};
  }
  return { ...raw };
}

/**
 * Целевой язык считается непереведённым, если ключ пуст/отсутствует
 * или дословно совпадает с ru (типичный дубликат при первичном sync).
 * Короткий ru (≤ MIN_RU_SOURCE_LEN) не трогаем — артикулы и коды.
 */
function needsRetranslation(map, lang, ruSource) {
  const ru = (ruSource || '').trim();
  if (!ru || ru.length <= MIN_RU_SOURCE_LEN) {
    return false;
  }

  if (!Object.prototype.hasOwnProperty.call(map, lang)) {
    return true;
  }

  const value = map[lang];
  if (value === null || value === undefined) {
    return true;
  }
  if (typeof value !== 'string' || value.trim().length === 0) {
    return true;
  }

  return value.trim() === ru;
}

function collectMissingJobs(product) {
  const name = normalizeMap(product.name);
  const description = normalizeMap(product.description);
  const ruName = (name[SOURCE_LANG] || '').trim();
  const ruDesc = (description[SOURCE_LANG] || '').trim();
  const jobs = [];

  for (const lang of TARGET_LANGS) {
    if (ruName && needsRetranslation(name, lang, ruName)) {
      jobs.push({
        field: 'name',
        lang,
        sourceText: ruName,
      });
    }
    if (ruDesc && needsRetranslation(description, lang, ruDesc)) {
      jobs.push({
        field: 'description',
        lang,
        sourceText: ruDesc,
      });
    }
  }

  return { name, description, jobs, ruName, ruDesc };
}

async function translateWithRetry(text, toLang, contextLabel) {
  for (;;) {
    try {
      await sleep(randomDelayMs());
      const res = await translate(text, { from: SOURCE_LANG, to: toLang });
      const out = (res.text || '').trim();
      if (!out) {
        throw new Error('empty translation result');
      }
      console.log(`  ✓ ${contextLabel} → ${toLang}: ${out.slice(0, 72)}…`);
      return out;
    } catch (err) {
      if (isRateLimitError(err)) {
        const pauseSec = Math.round(RATE_LIMIT_PAUSE_MS / 1000);
        console.warn(
          `  ⚠ 429 Too Many Requests (${contextLabel} → ${toLang}). Пауза ${pauseSec}s…`,
        );
        await sleep(RATE_LIMIT_PAUSE_MS);
        continue;
      }
      console.error(`  ✗ ${contextLabel} → ${toLang}: ${err.message || err}`);
      throw err;
    }
  }
}

async function fetchAllProducts(supabase) {
  const all = [];
  let from = 0;

  for (;;) {
    const to = from + PAGE_SIZE - 1;
    const { data, error } = await supabase
      .from('products')
      .select('id, sku, name, description')
      .order('id', { ascending: true })
      .range(from, to);

    if (error) throw error;
    if (!data || data.length === 0) break;

    all.push(...data);
    if (data.length < PAGE_SIZE) break;
    from += PAGE_SIZE;
  }

  return all;
}

async function processProduct(supabase, product, index, total) {
  const { name, description, jobs, ruName, ruDesc } = collectMissingJobs(product);

  if (jobs.length === 0) {
    return { updated: false, skipped: true };
  }

  console.log(
    `\n[${index + 1}/${total}] id=${product.id} sku=${product.sku} — ${jobs.length} перевод(ов)`,
  );
  if (!ruName && !ruDesc) {
    console.log('  skip: нет ru текста');
    return { updated: false, skipped: true };
  }

  for (const job of jobs) {
    const label = `${job.field}/${product.sku}`;
    const translated = await translateWithRetry(
      job.sourceText,
      job.lang,
      label,
    );
    if (job.field === 'name') {
      name[job.lang] = translated;
    } else {
      description[job.lang] = translated;
    }
  }

  if (DRY_RUN) {
    console.log('  DRY_RUN: update пропущен');
    return { updated: false, skipped: false, dryRun: true };
  }

  const { error } = await supabase
    .from('products')
    .update({ name, description })
    .eq('id', product.id);

  if (error) {
    throw new Error(`Supabase update id=${product.id}: ${error.message}`);
  }

  console.log('  ✓ Supabase update OK');
  return { updated: true, skipped: false };
}

async function main() {
  requireEnv();
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: fetch.bind(globalThis) },
    realtime: { transport: ws },
  });

  console.log('Загрузка products из Supabase…');
  const products = await fetchAllProducts(supabase);
  console.log(`Всего строк: ${products.length}`);

  const pending = products.filter((p) => collectMissingJobs(p).jobs.length > 0);
  console.log(`Требуют доперевода: ${pending.length}`);
  if (pending.length === 0) {
    console.log('Готово — нечего переводить.');
    return;
  }

  let updated = 0;
  let skipped = 0;
  let errors = 0;

  for (let i = 0; i < pending.length; i += CHUNK_SIZE) {
    const chunk = pending.slice(i, i + CHUNK_SIZE);
    console.log(
      `\n=== Chunk ${Math.floor(i / CHUNK_SIZE) + 1} (${chunk.length} товаров) ===`,
    );

    for (let j = 0; j < chunk.length; j += 1) {
      const product = chunk[j];
      const globalIndex = i + j;
      try {
        const result = await processProduct(
          supabase,
          product,
          globalIndex,
          pending.length,
        );
        if (result.skipped) skipped += 1;
        else if (result.updated) updated += 1;
      } catch (err) {
        errors += 1;
        console.error(`Ошибка id=${product.id}: ${err.message || err}`);
      }
    }

    if (i + CHUNK_SIZE < pending.length) {
      const between = randomDelayMs();
      console.log(`Пауза между chunk ${between}ms…`);
      await sleep(between);
    }
  }

  console.log('\n========== Итог ==========');
  console.log(`Обновлено: ${updated}`);
  console.log(`Пропущено (без jobs): ${skipped}`);
  console.log(`Ошибок: ${errors}`);
  if (DRY_RUN) {
    console.log('Режим DRY_RUN — в БД ничего не записано.');
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
