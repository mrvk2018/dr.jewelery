/**
 * Мониторинг HARD RE-SYNC с рабочей машины (без доступа к складскому ПК).
 *
 *   node scripts/track-sync.js
 *   npm run sync:track
 *
 * Env (.env в корне проекта):
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 *   SYNC_TRACK_POLL_MS — интервал опроса (по умолчанию 30000)
 *   SYNC_CATALOG_EXPECTED — знаменатель для «N из M» (по умолчанию 1500)
 *
 * Флаги:
 *   --exit-on-done — выйти, когда sync_requested станет false (после хотя бы одного true)
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const ws = require('ws');
const { createClient } = require('@supabase/supabase-js');

const SYNC_TASK_ID = 'catalog_sync';
const POLL_MS = Number(process.env.SYNC_TRACK_POLL_MS || 30_000);
const EXPECTED_WEBP =
  Number(process.env.SYNC_CATALOG_EXPECTED || 0) > 0
    ? Number(process.env.SYNC_CATALOG_EXPECTED)
    : 1500;

const exitOnDone = process.argv.includes('--exit-on-done');

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function formatTs(date) {
  return date.toISOString().replace('T', ' ').slice(0, 19);
}

function requireSupabase() {
  const url = process.env.SUPABASE_URL?.trim();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (!url || !key) {
    throw new Error('SUPABASE_URL и SUPABASE_SERVICE_ROLE_KEY обязательны в .env');
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    realtime: { transport: ws },
  });
}

async function fetchSyncTaskRow(supabase) {
  const { data, error } = await supabase
    .from('sync_tasks')
    .select('sync_requested, updated_at')
    .eq('id', SYNC_TASK_ID)
    .maybeSingle();

  if (error) throw error;
  return data;
}

async function countProductsWebpImageUrl(supabase) {
  const { count, error } = await supabase
    .from('products')
    .select('id', { count: 'exact', head: true })
    .ilike('image_url', '%.webp%');

  if (error) throw error;
  return count ?? 0;
}

async function countProductsTotal(supabase) {
  const { count, error } = await supabase
    .from('products')
    .select('id', { count: 'exact', head: true });

  if (error) throw error;
  return count ?? 0;
}

function printStatusLine({ syncRequested, updatedAt, webpCount, totalProducts }) {
  const target = EXPECTED_WEBP;
  const pct =
    target > 0 ? ((webpCount / target) * 100).toFixed(1) : '—';
  const flagLabel = syncRequested ? 'В РАБОТЕ (sync_requested=true)' : 'ОЖИДАНИЕ (sync_requested=false)';
  const updated = updatedAt ? String(updatedAt) : '—';

  console.log(
    `[${formatTs(new Date())}] ${flagLabel} | sync_tasks.updated_at=${updated}`,
  );
  console.log(
    `  WebP в products.image_url: ${webpCount} из ~${target} (${pct}%) | всего строк products: ${totalProducts}`,
  );
}

async function main() {
  const supabase = requireSupabase();
  let sawSyncRequested = false;

  console.log(
    `[track-sync] Старт. task=${SYNC_TASK_ID}, опрос каждые ${POLL_MS / 1000}s, ` +
      `цель WebP ≈ ${EXPECTED_WEBP}. Ctrl+C для выхода.`,
  );
  console.log(
    '[track-sync] Перед мониторингом выполните в Supabase SQL: UPDATE public.sync_tasks SET sync_requested=true WHERE id=\'catalog_sync\';',
  );

  while (true) {
    try {
      const row = await fetchSyncTaskRow(supabase);
      const syncRequested = Boolean(row?.sync_requested);
      if (syncRequested) sawSyncRequested = true;

      const [webpCount, totalProducts] = await Promise.all([
        countProductsWebpImageUrl(supabase),
        countProductsTotal(supabase),
      ]);

      printStatusLine({
        syncRequested,
        updatedAt: row?.updated_at,
        webpCount,
        totalProducts,
      });

      if (exitOnDone && sawSyncRequested && !syncRequested) {
        console.log(
          '[track-sync] Импорт завершён: sync_requested=false. Складской sync.js сбросил флаг после успеха.',
        );
        process.exit(0);
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(`[track-sync] ошибка опроса: ${message}`);
    }

    await sleep(POLL_MS);
  }
}

main().catch((err) => {
  console.error('[track-sync] fatal:', err);
  process.exit(1);
});
