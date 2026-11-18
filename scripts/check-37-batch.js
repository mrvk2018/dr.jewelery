/**
 * Поштучная сверка партии Items.Id 20179..20215 (read-only).
 * node scripts/check-37-batch.js
 */
require('dotenv').config();
const sql = require('mssql');
const { createClient } = require('@supabase/supabase-js');

const SYNC_UTC = '2026-11-16T12:59:42.079Z';
const SYNC_MS = Date.parse(SYNC_UTC);
const MIN_ID = 20179;
const MAX_ID = 20215;
const GAP_MAX = 20189;

const MSSQL_CONFIG = {
  server: process.env.MSSQL_HOST || '211.176.43.226',
  port: Number(process.env.MSSQL_PORT || 1433),
  user: process.env.MSSQL_USER || 'DrJ_Reader',
  password: process.env.MSSQL_PASSWORD || 'Read_only11!',
  database: process.env.MSSQL_DATABASE || 'DrJaw',
  options: { encrypt: false, trustServerCertificate: true },
  requestTimeout: 120000,
};

function resolveStore(mart) {
  const raw = String(mart ?? '').trim();
  const lower = raw.toLowerCase();
  if (raw === 'D.Y №2' || lower.includes('№2') || lower.includes('ансан') || lower === 'ans') return 'ANS';
  return 'ICN';
}

function weightMatch(a, b, tol = 0.01) {
  return Math.abs(Number(a) - Number(b)) <= tol;
}

function priceMatch(a, b) {
  return Math.round(Number(a)) === Math.round(Number(b));
}

const PAGE_SIZE = 1000;

async function fetchAllProducts(supabase) {
  const pageSize = 1000;
  let from = 0;
  const all = [];
  for (;;) {
    const to = from + pageSize - 1;
    const { data, error } = await supabase
      .from('products')
      .select('id, sku, status, sale_price, weight_grams, store_location, updated_at, name, metal_type')
      .order('id', { ascending: true })
      .range(from, to);
    if (error) throw error;
    if (!data?.length) break;
    all.push(...data);
    if (data.length < PAGE_SIZE) break;
    from += pageSize;
  }
  return all;
}

function classifyGapItem(msRow, products, sbById) {
  const id = String(msRow.Id);
  const sku = String(msRow.Articul ?? '').trim();
  const w = Number(msRow.Weight);
  const p = Math.round(Number(msRow.Price));

  if (sbById.has(id)) {
    return {
      level: 'ID_EXISTS',
      mssqlId: id,
      sku,
      supabase: sbById.get(id),
    };
  }

  const sameSku = products.filter((r) => String(r.sku ?? '').trim() === sku);
  const levelA = sameSku.filter(
    (r) => weightMatch(r.weight_grams, w) && priceMatch(r.sale_price, p),
  );
  if (levelA.length) {
    return {
      level: 'A',
      mssqlId: id,
      sku,
      mssql: { weight_g: w, price_krw: p, store: resolveStore(msRow.Mart), status: msRow.Status },
      matches: levelA.map(mapSbRow),
    };
  }

  if (sameSku.length) {
    return {
      level: 'B',
      mssqlId: id,
      sku,
      mssql: { weight_g: w, price_krw: p, store: resolveStore(msRow.Mart), status: msRow.Status },
      matches: sameSku.map(mapSbRow),
    };
  }

  return {
    level: 'V',
    mssqlId: id,
    sku,
    mssql: { weight_g: w, price_krw: p, store: resolveStore(msRow.Mart), status: msRow.Status },
    matches: [],
  };
}

function mapSbRow(r) {
  const updatedAfterSync = r.updated_at ? Date.parse(r.updated_at) > SYNC_MS : false;
  return {
    id: r.id,
    sku: r.sku,
    status: r.status,
    store_location: r.store_location,
    weight_g: r.weight_grams,
    price_krw: r.sale_price,
    updated_at: r.updated_at,
    updated_after_sync: updatedAfterSync,
  };
}

(async () => {
  const pool = await sql.connect(MSSQL_CONFIG);
  const result = await pool.request().query(`
    SELECT i.Id, i.Articul, i.Price, i.Weight, i.Mart, i.Status, i.Size, i.Stones,
           a.Type, a.Metall
    FROM dbo.Items AS i
    LEFT JOIN dbo.Articuls AS a ON a.Articul = i.Articul
    WHERE i.Id >= ${MIN_ID} AND i.Id <= ${MAX_ID}
    ORDER BY i.Id
  `);
  await pool.close();

  const mssqlRows = result.recordset || [];
  const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const products = await fetchAllProducts(supabase);
  const sbById = new Map(products.map((p) => [String(p.id), p]));

  const batchList = mssqlRows.map((r) => ({
    Id: r.Id,
    SKU: r.Articul,
    type: r.Type,
    metal: r.Metall,
    Weight: Number(r.Weight),
    Price: Math.round(Number(r.Price)),
    Mart: r.Mart,
    store: resolveStore(r.Mart),
    Status: r.Status,
    inSupabase: sbById.has(String(r.Id)),
    supabaseStatus: sbById.get(String(r.Id))?.status ?? null,
  }));

  const gapRows = mssqlRows.filter((r) => Number(r.Id) <= GAP_MAX);
  const gapAnalysis = gapRows.map((r) => classifyGapItem(r, products, sbById));

  const summary = {
    A: gapAnalysis.filter((x) => x.level === 'A'),
    B: gapAnalysis.filter((x) => x.level === 'B'),
    V: gapAnalysis.filter((x) => x.level === 'V'),
    ID_EXISTS: gapAnalysis.filter((x) => x.level === 'ID_EXISTS'),
  };

  const report = {
    meta: {
      range: `${MIN_ID}..${MAX_ID}`,
      gapRange: `${MIN_ID}..${GAP_MAX}`,
      countMssql: mssqlRows.length,
      syncMarkerKst: '2026-11-16 21:59:42',
    },
    mssqlBatch37: batchList,
    gap11Analysis: gapAnalysis,
    summary: {
      levelA_exact_duplicate: summary.A.length,
      levelB_same_sku_diff_dims: summary.B.length,
      levelV_import_safe: summary.V.length,
      id_already_in_supabase: summary.ID_EXISTS.length,
      importCandidateIds: summary.V.map((x) => x.mssqlId),
      needsConfirmationIds: summary.B.map((x) => x.mssqlId),
      skipDuplicateIds: [...summary.A, ...summary.ID_EXISTS].map((x) => x.mssqlId),
    },
  };

  console.log(JSON.stringify(report, null, 2));
})().catch((e) => {
  console.error(e);
  process.exit(1);
});