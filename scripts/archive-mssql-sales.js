/**
 * Сверка DrJaw Items (Sold) ↔ Supabase products (active).
 * По умолчанию — только отчёт; --apply вызывает mark_product_sold_manual.
 *
 * Usage:
 *   node scripts/archive-mssql-sales.js              # dry-run (default)
 *   node scripts/archive-mssql-sales.js --dry-run
 *   node scripts/archive-mssql-sales.js --apply      # изменения в Supabase
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, MSSQL_* (как sync.js)
 */
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const sql = require('mssql');
const { createClient } = require('@supabase/supabase-js');

const BACKUP_DIR = path.join(__dirname, 'backups');

const ADMIN_EMAIL = 'dr.jewelry.korea@gmail.com';
const DEFAULT_SYNC_MARKER_UTC = '2026-11-16T12:59:42.079Z';
const MANUAL_IMPORT_MIN_ID = 20190;

const args = new Set(process.argv.slice(2));
const apply = args.has('--apply');
const dryRun = !apply || args.has('--dry-run');

const MSSQL_CONFIG = {
  server: process.env.MSSQL_HOST || '211.176.43.226',
  port: Number(process.env.MSSQL_PORT || 1433),
  user: process.env.MSSQL_USER || 'DrJ_Reader',
  password: process.env.MSSQL_PASSWORD || 'Read_only11!',
  database: process.env.MSSQL_DATABASE || 'DrJaw',
  options: { encrypt: false, trustServerCertificate: true },
  requestTimeout: 300000,
};

function resolveStore(mart) {
  const raw = String(mart ?? '').trim();
  const lower = raw.toLowerCase();
  if (raw === 'D.Y №2' || lower.includes('№2') || lower.includes('ансан') || lower === 'ans') {
    return 'ANS';
  }
  return 'ICN';
}

function titleFromType(type) {
  const t = String(type ?? '').trim();
  return t || '—';
}

async function fetchLastSyncUtc(supabase) {
  const { data, error } = await supabase
    .from('sync_tasks')
    .select('updated_at')
    .eq('id', 'catalog_sync')
    .maybeSingle();
  if (error) throw error;
  return data?.updated_at || DEFAULT_SYNC_MARKER_UTC;
}

async function fetchMssqlSold(pool) {
  const result = await pool.request().query(`
    SELECT i.Id, i.Articul, i.Status, i.Price, i.Weight, i.Mart, i.Size, i.Stones,
           a.Metall, a.Type
    FROM dbo.Items AS i
    LEFT JOIN dbo.Articuls AS a ON a.Articul = i.Articul
    WHERE i.Status = N'Sold'
    ORDER BY i.Id
  `);
  return result.recordset || [];
}

async function fetchSupabaseByIds(supabase, ids, select = 'id, sku, status, sale_price, weight_grams, store_location, name') {
  const map = new Map();
  const chunk = 200;
  for (let i = 0; i < ids.length; i += chunk) {
    const slice = ids.slice(i, i + chunk);
    const { data, error } = await supabase.from('products').select(select).in('id', slice);
    if (error) throw error;
    for (const row of data || []) map.set(String(row.id), row);
  }
  return map;
}

function writeApplyBackup(report, productSnapshots) {
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const file = path.join(BACKUP_DIR, `archive-mssql-sales-${stamp}.json`);
  const payload = {
    createdAt: new Date().toISOString(),
    action: 'mark_product_sold_manual',
    report,
    productSnapshotsBeforeApply: productSnapshots,
  };
  fs.writeFileSync(file, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
  console.log(`[backup] ${file}`);
  return file;
}

function buildStaleRows(soldRows, sbById) {
  const stale = [];
  for (const ms of soldRows) {
    const id = String(ms.Id);
    const numId = Number(id);
    if (numId >= MANUAL_IMPORT_MIN_ID) continue;
    const sb = sbById.get(id);
    if (!sb || sb.status !== 'active') continue;
    stale.push({
      id,
      sku: ms.Articul,
      title: titleFromType(ms.Type),
      metal: ms.Metall || '—',
      weight_g: Number(ms.Weight),
      price_krw: Number(ms.Price),
      store: resolveStore(ms.Mart),
      mssql_status: ms.Status,
      supabase_status: sb.status,
      sale_date_mssql: null,
    });
  }
  return stale;
}

async function markSold(supabase, productId) {
  const { data, error } = await supabase.rpc('mark_product_sold_manual', {
    p_product_id: productId,
    p_admin_email: ADMIN_EMAIL,
  });
  if (error) throw error;
  return Boolean(data);
}

(async () => {
  const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const lastSyncUtc = await fetchLastSyncUtc(supabase);

  const pool = await sql.connect(MSSQL_CONFIG);
  const soldRows = await fetchMssqlSold(pool);
  await pool.close();

  const ids = soldRows.map((r) => String(r.Id));
  const sbById = await fetchSupabaseByIds(supabase, ids);
  const stale = buildStaleRows(soldRows, sbById);

  const byStore = { ICN: 0, ANS: 0 };
  for (const row of stale) byStore[row.store] += 1;

  const report = {
    mode: dryRun ? 'dry-run' : 'apply',
    lastStandardSyncUtc: lastSyncUtc,
    mssqlSalesByDay: {
      supported: false,
      reason:
        'DrJaw (DrJ_Reader): нет datetime-колонок и нет таблиц чеков; дневная разбивка продаж в MSSQL недоступна.',
    },
    staleActiveCount: stale.length,
    byStore,
    items: stale,
  };

  console.log(JSON.stringify(report, null, 2));

  if (dryRun) {
    console.log('\n[dry-run] Изменений в Supabase нет. Для архивации: node scripts/archive-mssql-sales.js --apply');
    return;
  }

  if (stale.length === 0) {
    console.log('\n[apply] Нет позиций для архивации.');
    return;
  }

  const staleIds = stale.map((r) => r.id);
  const snapshots = await fetchSupabaseByIds(supabase, staleIds, '*');
  writeApplyBackup(
    report,
    staleIds.map((id) => ({ id, row: snapshots.get(id) || null })),
  );

  let ok = 0;
  let fail = 0;
  for (const row of stale) {
    try {
      const success = await markSold(supabase, row.id);
      if (success) ok += 1;
      else fail += 1;
      console.log(`[apply] id=${row.id} sku=${row.sku} → ${success ? 'sold' : 'skip'}`);
    } catch (err) {
      fail += 1;
      console.error(`[apply] id=${row.id} failed:`, err.message || err);
    }
  }
  console.log(`\n[apply] done ok=${ok} fail=${fail}`);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});