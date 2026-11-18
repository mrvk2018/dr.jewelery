/**
 * Предпусковая сверка DrJaw ↔ Supabase (read-only).
 * node scripts/full-cutover-audit.js
 */
require('dotenv').config();
const sql = require('mssql');
const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const SYNC_UTC = '2026-11-16T12:59:42.079Z';
const SYNC_MS = Date.parse(SYNC_UTC);
const GAP_RANGE = { min: 20179, max: 20189 };
const BATCH_MIN = 20190;

/** В БД черновики = status hidden (см. draft_intake / RPC). */
const DRAFT_STATUSES = new Set(['hidden']);
const COVERED_FOR_MSSQL_ITEM = new Set(['active', 'hidden', 'sold', 'in_transfer', 'reserved']);

const MSSQL_CONFIG = {
  server: process.env.MSSQL_HOST || '211.176.43.226',
  port: Number(process.env.MSSQL_PORT || 1433),
  user: process.env.MSSQL_USER || 'DrJ_Reader',
  password: process.env.MSSQL_PASSWORD || 'Read_only11!',
  database: process.env.MSSQL_DATABASE || 'DrJaw',
  options: { encrypt: false, trustServerCertificate: true },
  requestTimeout: 600000,
};

const PAGE = 1000;

function resolveStoreFromMart(mart) {
  const raw = String(mart ?? '').trim();
  const lower = raw.toLowerCase();
  if (
    raw === 'D.Y №2' ||
    lower.includes('№2') ||
    lower.includes('d.y') ||
    lower === 'ans' ||
    lower.includes('ансан')
  ) {
    return 'ANS';
  }
  return 'ICN';
}

function isWarehouseId(id) {
  return /^\d+$/.test(String(id ?? '').trim());
}

function weightClose(a, b) {
  return Math.abs(Number(a) - Number(b)) < 0.02;
}

function priceEqual(a, b) {
  return Math.round(Number(a)) === Math.round(Number(b));
}

function bumpStore(bucket, store, n = 1) {
  if (store === 'ICN' || store === 'ANS') bucket[store] += n;
  else bucket.other += n;
}

async function fetchAllProducts(supabase) {
  const all = [];
  let from = 0;
  for (;;) {
    const to = from + PAGE - 1;
    const { data, error } = await supabase
      .from('products')
      .select(
        'id, sku, status, stock_quantity, sale_price, weight_grams, store_location, updated_at, name, metal_type, metal',
      )
      .order('id', { ascending: true })
      .range(from, to);
    if (error) throw error;
    if (!data?.length) break;
    all.push(...data);
    if (data.length < PAGE) break;
    from += PAGE;
  }
  return all;
}

async function fetchMssqlItems(pool) {
  const result = await pool.request().query(`
    SELECT i.Id, i.Articul, i.Status, i.Price, i.Weight, i.Mart, i.Size, i.Stones,
           a.Metall, a.Type
    FROM dbo.Items AS i
    LEFT JOIN dbo.Articuls AS a ON a.Articul = i.Articul
  `);
  return result.recordset || [];
}

function buildSkuIndex(products) {
  const bySku = new Map();
  for (const p of products) {
    const sku = String(p.sku ?? '').trim();
    if (!sku) continue;
    if (!bySku.has(sku)) bySku.set(sku, []);
    bySku.get(sku).push(p);
  }
  return bySku;
}

function findManualDuplicates(msRow, bySku) {
  const sku = String(msRow.Articul ?? '').trim();
  const candidates = bySku.get(sku) || [];
  const dup = [];
  const msId = String(msRow.Id);
  const w = Number(msRow.Weight);
  const p = Math.round(Number(msRow.Price));
  for (const row of candidates) {
    if (String(row.id) === msId) continue;
    if (!weightClose(row.weight_grams, w)) continue;
    if (!priceEqual(row.sale_price, p)) continue;
    dup.push({
      supabaseId: row.id,
      sku: row.sku,
      status: row.status,
      store_location: row.store_location,
    });
  }
  return dup;
}

function titleFromName(name) {
  if (!name || typeof name !== 'object') return '—';
  return name.ru || name.ko || name.en || '—';
}

function detectSyncDaemonProcess() {
  if (process.platform !== 'win32') {
    try {
      const out = execSync('pgrep -fl "sync-daemon.js" || true', { encoding: 'utf8' }).trim();
      return { platform: process.platform, matches: out || null };
    } catch {
      return { platform: process.platform, matches: null, note: 'pgrep unavailable' };
    }
  }
  try {
    const ps = execSync(
      'powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match \'node.*sync-daemon\\.js\' } | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"',
      { encoding: 'utf8', maxBuffer: 2_000_000 },
    ).trim();
    return { platform: 'win32', running: ps || null, note: ps ? 'node sync-daemon.js найден' : 'daemon не найден' };
  } catch {
    return { platform: 'win32', matches: null };
  }
}

(async () => {
  const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  const { data: syncTask, error: syncTaskErr } = await supabase
    .from('sync_tasks')
    .select('id, sync_requested, updated_at')
    .eq('id', 'catalog_sync')
    .maybeSingle();
  if (syncTaskErr) throw syncTaskErr;

  const pool = await sql.connect(MSSQL_CONFIG);
  const mssqlRows = await fetchMssqlItems(pool);
  await pool.close();

  const products = await fetchAllProducts(supabase);
  const sbById = new Map(products.map((p) => [String(p.id), p]));
  const bySku = buildSkuIndex(products);

  const mssqlInStock = mssqlRows.filter((r) => {
    const s = String(r.Status ?? '').trim();
    return s === 'InStock' || s === 'В наличии';
  });
  const mssqlInTransfer = mssqlRows.filter((r) => String(r.Status ?? '').trim() === 'InTransfer');
  const mssqlAvailable = [...mssqlInStock, ...mssqlInTransfer];
  const mssqlSold = mssqlRows.filter((r) => String(r.Status ?? '').trim() === 'Sold');
  const mssqlAvailableIds = new Set(mssqlAvailable.map((r) => String(r.Id)));

  const mssqlInStockByStore = { ICN: 0, ANS: 0, other: 0 };
  const mssqlInTransferByStore = { ICN: 0, ANS: 0, other: 0 };
  for (const r of mssqlInStock) bumpStore(mssqlInStockByStore, resolveStoreFromMart(r.Mart));
  for (const r of mssqlInTransfer) bumpStore(mssqlInTransferByStore, resolveStoreFromMart(r.Mart));

  const missingFromSupabase = [];
  const gapRangeItems = [];
  const manualDuplicateRisks = [];

  for (const ms of mssqlAvailable) {
    const id = String(ms.Id);
    const sb = sbById.get(id);
    const store = resolveStoreFromMart(ms.Mart);
    const dupes = findManualDuplicates(ms, bySku);
    if (dupes.length) {
      manualDuplicateRisks.push({ mssqlId: id, sku: ms.Articul, manualMatches: dupes });
    }

    const inGap = Number(id) >= GAP_RANGE.min && Number(id) <= GAP_RANGE.max;
    const afterBatch = Number(id) > 20215;

    if (!sb) {
      const entry = {
        mssqlId: id,
        sku: ms.Articul,
        status_mssql: ms.Status,
        store_mssql: store,
        mart: ms.Mart,
        weight_g: Number(ms.Weight),
        price_krw: Math.round(Number(ms.Price)),
        metal: ms.Metall,
        reason: 'no products.id',
        manualDuplicates: dupes,
      };
      missingFromSupabase.push(entry);
      if (inGap || afterBatch) gapRangeItems.push(entry);
      continue;
    }

    const st = String(sb.status ?? '');
    const covered = COVERED_FOR_MSSQL_ITEM.has(st);
    const draftOrShowroom = st === 'active' || DRAFT_STATUSES.has(st) || st === 'sold';
    if (!draftOrShowroom && !covered) {
      missingFromSupabase.push({
        mssqlId: id,
        sku: ms.Articul,
        status_mssql: ms.Status,
        status_supabase: st,
        store_mssql: store,
        reason: 'id exists but not in active/draft(hidden)/sold',
        manualDuplicates: dupes,
      });
    }
  }

  const staleActiveSold = [];
  for (const ms of mssqlSold) {
    const id = String(ms.Id);
    const sb = sbById.get(id);
    if (sb?.status === 'active') {
      staleActiveSold.push({
        id,
        sku: ms.Articul,
        store_mssql: resolveStoreFromMart(ms.Mart),
        weight_g: Number(ms.Weight),
        price_krw: Math.round(Number(ms.Price)),
      });
    }
  }

  const fieldMismatches = [];
  for (const ms of mssqlInStock) {
    const id = String(ms.Id);
    const sb = sbById.get(id);
    if (!sb || sb.status !== 'active') continue;
    const storeMssql = resolveStoreFromMart(ms.Mart);
    const storeSb = String(sb.store_location ?? 'ICN').toUpperCase();
    const updatedMs = sb.updated_at ? Date.parse(sb.updated_at) : 0;
    const adminUpdatedAfterSync = updatedMs > SYNC_MS;
    const diffs = [];
    if (storeSb !== storeMssql) {
      diffs.push({ field: 'store_location', mssql: storeMssql, supabase: storeSb });
    }
    if (!weightClose(sb.weight_grams, ms.Weight)) {
      diffs.push({
        field: 'weight_grams',
        mssql: Number(ms.Weight),
        supabase: Number(sb.weight_grams),
      });
    }
    if (!priceEqual(sb.sale_price, ms.Price)) {
      diffs.push({
        field: 'sale_price',
        mssql: Math.round(Number(ms.Price)),
        supabase: Math.round(Number(sb.sale_price)),
      });
    }
    if (diffs.length) {
      fieldMismatches.push({
        id,
        sku: ms.Articul,
        adminUpdatedAfterSync,
        supabasePriority: adminUpdatedAfterSync,
        updated_at: sb.updated_at,
        diffs,
      });
    }
  }

  const draftByStore = { ICN: 0, ANS: 0, other: 0 };
  const inTransferByStore = { ICN: 0, ANS: 0, other: 0 };
  const activeByStore = { ICN: 0, ANS: 0, other: 0 };
  let draftTotalWeight = 0;
  let draftTotalPrice = 0;
  let adminActiveCount = 0;
  let adminActiveWeight = 0;
  let adminActivePrice = 0;
  const adminActiveByStore = { ICN: 0, ANS: 0, other: 0 };
  const adminActiveSamples = [];

  for (const p of products) {
    const store = String(p.store_location ?? 'ICN').toUpperCase();
    const st = String(p.status ?? '');
    if (DRAFT_STATUSES.has(st)) {
      bumpStore(draftByStore, store);
      draftTotalWeight += Number(p.weight_grams) || 0;
      draftTotalPrice += Number(p.sale_price) || 0;
    }
    if (st === 'in_transfer') bumpStore(inTransferByStore, store);
    if (st === 'active') bumpStore(activeByStore, store);

    if (st === 'active') {
      const wid = isWarehouseId(p.id);
      const inMssqlStock = mssqlAvailableIds.has(String(p.id));
      const adminNative = !wid || !inMssqlStock;
      const updatedAfterSync = p.updated_at && Date.parse(p.updated_at) > SYNC_MS;
      if (adminNative || (updatedAfterSync && !inMssqlStock)) {
        adminActiveCount += 1;
        adminActiveWeight += Number(p.weight_grams) || 0;
        adminActivePrice += Number(p.sale_price) || 0;
        bumpStore(adminActiveByStore, store);
        if (adminActiveSamples.length < 40) {
          adminActiveSamples.push({
            id: p.id,
            sku: p.sku,
            store,
            weight_g: p.weight_grams,
            price_krw: p.sale_price,
            updated_at: p.updated_at,
            reason: !wid ? 'uuid/manual id' : 'numeric id not InStock/InTransfer in MSSQL',
          });
        }
      }
    }
  }

  const missingByStore = { ICN: 0, ANS: 0, other: 0 };
  const staleByStore = { ICN: 0, ANS: 0, other: 0 };
  for (const r of missingFromSupabase) bumpStore(missingByStore, r.store_mssql);
  for (const r of staleActiveSold) bumpStore(staleByStore, r.store_mssql);

  function kpiRow(storeKey) {
    const mssqlStock = storeKey === 'ICN' ? mssqlInStockByStore.ICN : mssqlInStockByStore.ANS;
    const mssqlXfer = storeKey === 'ICN' ? mssqlInTransferByStore.ICN : mssqlInTransferByStore.ANS;
    const miss = storeKey === 'ICN' ? missingByStore.ICN : missingByStore.ANS;
    const stale = storeKey === 'ICN' ? staleByStore.ICN : staleByStore.ANS;
    const draft = storeKey === 'ICN' ? draftByStore.ICN : draftByStore.ANS;
    const adminAct = storeKey === 'ICN' ? adminActiveByStore.ICN : adminActiveByStore.ANS;
    const showroom = storeKey === 'ICN' ? activeByStore.ICN : activeByStore.ANS;
    return {
      store: storeKey,
      mssql_instock: mssqlStock,
      mssql_in_transfer: mssqlXfer,
      not_in_supabase_or_uncovered: miss,
      mssql_sold_still_active_supabase: stale,
      supabase_draft_hidden: draft,
      supabase_in_transfer: storeKey === 'ICN' ? inTransferByStore.ICN : inTransferByStore.ANS,
      supabase_admin_native_active: adminAct,
      supabase_active_showroom_fact: showroom,
      reconciled_note:
        'Факт витрины = supabase_active_showroom_fact; MS SQL — ориентир наследия, не вычитать draft/admin из MS SQL автоматически',
    };
  }

  const daemonProbe = detectSyncDaemonProcess();

  const report = {
    meta: {
      mode: 'read-only',
      generatedAt: new Date().toISOString(),
      lastStandardSyncUtc: SYNC_UTC,
      lastStandardSyncKst: '2026-11-16 21:59:42',
      draftStatusInDb: 'hidden',
    },
    syncSafety: {
      sync_tasks: syncTask,
      sync_requested_is_dangerous: Boolean(syncTask?.sync_requested),
      recommendation:
        syncTask?.sync_requested
          ? 'СРОЧНО: sync_requested=true — остановите sync-daemon или сбросьте флаг до cutover'
          : 'sync_requested=false — полный sync.js не стартует по флагу (если никто вручную не запустит sync.js)',
      sync_daemon_probe: daemonProbe,
      SYNC_SKIP_STATUSES_in_sync_js: ['reserved', 'sold', 'hidden'],
      note:
        'sync.js перезаписывает active по MSSQL; hidden/sold/reserved пропускаются. UUID-черновики не трогает cleanup по mssql id.',
    },
    layer1_mssql_heritage: {
      totals: {
        mssql_instock: mssqlInStock.length,
        mssql_in_transfer: mssqlInTransfer.length,
        mssql_sold: mssqlSold.length,
        supabase_products_total: products.length,
      },
      missing_instock_or_intransfer_not_covered: {
        count: missingFromSupabase.length,
        by_store: missingByStore,
        gap_20179_20189_and_after_20215: gapRangeItems,
        all: missingFromSupabase,
      },
      manual_duplicate_risks: {
        count: manualDuplicateRisks.length,
        items: manualDuplicateRisks.slice(0, 100),
      },
      stale_mssql_sold_supabase_active: {
        count: staleActiveSold.length,
        by_store: staleByStore,
        items: staleActiveSold,
      },
      field_mismatches_instock_vs_active: {
        count: fieldMismatches.length,
        supabase_priority_count: fieldMismatches.filter((x) => x.supabasePriority).length,
        items: fieldMismatches.slice(0, 150),
      },
    },
    layer2_admin_supabase_since_sync: {
      drafts_hidden: {
        total: draftByStore.ICN + draftByStore.ANS + draftByStore.other,
        by_store: draftByStore,
        total_weight_g: Number(draftTotalWeight.toFixed(2)),
        total_sale_price_krw: draftTotalPrice,
      },
      in_transfer: {
        by_store: inTransferByStore,
      },
      admin_native_active: {
        definition:
          'active и (UUID id ИЛИ числовой id без InStock/InTransfer в MSSQL на момент аудита)',
        total: adminActiveCount,
        by_store: adminActiveByStore,
        total_weight_g: Number(adminActiveWeight.toFixed(2)),
        total_sale_price_krw: adminActivePrice,
        samples: adminActiveSamples,
      },
    },
    kpi_cutover_table: [kpiRow('ICN'), kpiRow('ANS')],
  };

  const outPath = path.join(__dirname, 'backups', `full-cutover-audit-${Date.now()}.json`);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, `${JSON.stringify(report, null, 2)}\n`);
  console.log(`\n[report] written: ${outPath}\n`);
  console.log(JSON.stringify(report, null, 2));
})().catch((err) => {
  console.error(err);
  process.exit(1);
});