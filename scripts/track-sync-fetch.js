/**
 * Мониторинг без node_modules — только fetch (Node 18+).
 * Anon key: прогресс WebP по active products (RLS). sync_tasks — если есть service_role в .env.
 */

const fs = require('fs');
const path = require('path');

function loadDotEnv() {
  const envPath = path.join(__dirname, '..', '.env');
  if (!fs.existsSync(envPath)) return;
  for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    const key = trimmed.slice(0, eq).trim();
    const val = trimmed.slice(eq + 1).trim();
    if (!process.env[key]) process.env[key] = val;
  }
}

loadDotEnv();

const POLL_MS = Number(process.env.SYNC_TRACK_POLL_MS || 30_000);
const EXPECTED = Number(process.env.SYNC_CATALOG_EXPECTED || 1500);
const exitOnDone = process.argv.includes('--exit-on-done');

const BASE =
  process.env.SUPABASE_URL?.trim() ||
  'https://iuezgsvihzhfnrdpdbzn.supabase.co';
const ANON =
  process.env.SUPABASE_ANON_KEY?.trim() ||
  'sb_publishable_JO1MyY5BK8O1SJBvKbs7KA_dRci-qja';
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
const SYNC_TASK_ID = 'catalog_sync';

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function fmt(d) {
  return d.toISOString().replace('T', ' ').slice(0, 19);
}

async function restCount(path, apiKey) {
  const res = await fetch(`${BASE}/rest/v1/${path}`, {
    headers: {
      apikey: apiKey,
      Authorization: `Bearer ${apiKey}`,
      Prefer: 'count=exact',
    },
  });
  const range = res.headers.get('content-range') || '';
  const m = range.match(/\/(\d+)$/);
  if (!m) return null;
  return Number(m[1]);
}

async function fetchSyncTask(serviceKey) {
  const res = await fetch(
    `${BASE}/rest/v1/sync_tasks?id=eq.${SYNC_TASK_ID}&select=sync_requested,updated_at`,
    {
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
      },
    },
  );
  if (!res.ok) return null;
  const rows = await res.json();
  return rows[0] || null;
}

async function main() {
  const useService =
    SERVICE && !SERVICE.includes('your_service') && SERVICE.length > 20;
  const countKey = useService ? SERVICE : ANON;

  console.log(
    `[track-sync] BASE=${BASE} | опрос ${POLL_MS / 1000}s | цель WebP ~${EXPECTED}`,
  );
  if (!useService) {
    console.log(
      '[track-sync] SUPABASE_SERVICE_ROLE_KEY не задан — sync_tasks недоступен, считаем WebP по products (active, RLS).',
    );
  }

  let sawSyncRequested = false;
  let lastWebp = -1;

  while (true) {
    try {
      let flagLine = 'sync_tasks: n/a';
      if (useService) {
        const task = await fetchSyncTask(SERVICE);
        if (task) {
          if (task.sync_requested) sawSyncRequested = true;
          flagLine = `sync_requested=${task.sync_requested} updated_at=${task.updated_at}`;
        }
      }

      const [webpCount, totalVisible] = await Promise.all([
        restCount(
          'products?select=id&image_url=ilike.%25.webp%25&limit=1',
          countKey,
        ),
        restCount('products?select=id&limit=1', countKey),
      ]);

      const webp = webpCount ?? 0;
      const total = totalVisible ?? 0;
      const pct = ((webp / EXPECTED) * 100).toFixed(1);

      console.log(`[${fmt(new Date())}] ${flagLine}`);
      console.log(
        `  WebP в products.image_url: ${webp} из ~${EXPECTED} (${pct}%) | видно в каталоге (RLS): ${total} строк`,
      );

      if (webp !== lastWebp && lastWebp >= 0) {
        console.log(`  Δ WebP с прошлого опроса: +${webp - lastWebp}`);
      }
      lastWebp = webp;

      if (exitOnDone && useService && sawSyncRequested) {
        const task = await fetchSyncTask(SERVICE);
        if (task && !task.sync_requested) {
          console.log('[track-sync] Импорт завершён (sync_requested=false).');
          process.exit(0);
        }
      }
    } catch (e) {
      console.error('[track-sync] ошибка:', e.message || e);
    }

    await sleep(POLL_MS);
  }
}

main().catch((e) => {
  console.error('[track-sync] fatal:', e);
  process.exit(1);
});
