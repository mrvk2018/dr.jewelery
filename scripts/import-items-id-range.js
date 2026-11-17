/**
 * Точечный импорт DrJaw Items.Id → Supabase products (те же правила, что sync.js).
 * Usage: node scripts/import-items-id-range.js [minId] [maxId]
 */
require('dotenv').config();
const sql = require('mssql');
const { createClient } = require('@supabase/supabase-js');
const ws = require('ws');

const sync = require('../sync.js');

const MIN_ID = Number(process.argv[2] || 20190);
const MAX_ID = Number(process.argv[3] || 20215);

async function fetchMssqlIdRange(pool, minId, maxId) {
  return sync.runMssqlWithTimeout(`fetchItems_${minId}_${maxId}`, async (activePool) => {
    const request = activePool.request();
    request.timeout = 60000;
    const result = await request
      .input('minId', sql.Int, minId)
      .input('maxId', sql.Int, maxId)
      .query(`
      SELECT
        i.Id,
        i.Articul,
        i.Price,
        i.Weight,
        i.Size,
        i.Stones,
        i.Status,
        i.Mart,
        i.Comment,
        a.Type,
        a.Metall
      FROM Items AS i
      INNER JOIN Articuls AS a ON i.Articul = a.Articul
      WHERE i.Id >= @minId AND i.Id <= @maxId
      ORDER BY i.Id
    `);
    return result.recordset || [];
  }, pool);
}

async function findMaxNumericProductIdBefore(supabase, threshold) {
  let maxBelow = null;
  let from = 0;
  const pageSize = 1000;
  for (;;) {
    const to = from + pageSize - 1;
    const { data, error } = await supabase
      .from('products')
      .select('id')
      .order('id', { ascending: true })
      .range(from, to);
    if (error) throw error;
    if (!data?.length) break;
    for (const row of data) {
      const id = String(row.id).trim();
      if (!/^\d+$/.test(id)) continue;
      const n = Number(id);
      if (n < threshold && (maxBelow === null || n > maxBelow)) {
        maxBelow = n;
      }
    }
    if (data.length < pageSize) break;
    from += pageSize;
  }
  return maxBelow;
}

async function idsPresentInSupabase(supabase, ids) {
  const { data, error } = await supabase.from('products').select('id').in('id', ids);
  if (error) throw error;
  return new Set((data || []).map((r) => String(r.id)));
}

async function importRange(supabase, pool, rows) {
  const articulSlotsCache = new Map();
  const payloads = [];
  const rowErrors = [];

  for (const row of rows) {
    const id = String(row.Id);
    const sku = String(row.Articul || '').trim();
    try {
      const { scalars } = await sync.buildDesiredScalarsForRow(row);
      scalars.status = 'active';
      scalars.stock_quantity = 1;

      const { slots } = await sync.fetchArticulImageBuffers(pool, sku);
      articulSlotsCache.set(sku, slots);

      const uploaded = await sync.uploadImageUrlsFromSlots(supabase, sku, slots, {
        productId: id,
      });
      const mssqlByteSizes = uploaded.mssqlBytes;
      const storageByteSizes = uploaded.storageBytes;

      const payload = {
        id,
        ...scalars,
        warehouse_attributes: sync.mergeWarehouseImageFingerprints(
          row,
          mssqlByteSizes,
          storageByteSizes,
        ),
      };
      if (uploaded.imageUrls.length > 0) {
        payload.image_url = uploaded.imageUrls[0];
        payload.images = uploaded.imageUrls;
      }
      payloads.push(payload);
      console.log(
        `[import] prepared id=${id} sku=${sku} images=${uploaded.imageUrls.length} ` +
          `store=${scalars.store_location} price=${scalars.sale_price}`,
      );
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      rowErrors.push({ id, sku, error: msg });
      console.error(`[import] failed id=${id} sku=${sku}: ${msg}`);
    }
  }

  if (payloads.length > 0) {
    await sync.upsertProductsInChunks(supabase, payloads);
  }

  return { payloads, rowErrors };
}

function summarizeImported(rows, payloads) {
  const byMetal = {};
  const byStore = { ICN: 0, ANS: 0, other: 0 };
  let minPrice = Infinity;
  let maxPrice = -Infinity;

  for (const p of payloads) {
    const metal = String(p.metal_type || p.metal || '—');
    byMetal[metal] = (byMetal[metal] || 0) + 1;
    const store = p.store_location || sync.resolveStoreLocationFromMart(null);
    if (store === 'ICN' || store === 'ANS') byStore[store] += 1;
    else byStore.other += 1;
    const price = Number(p.sale_price);
    if (Number.isFinite(price)) {
      minPrice = Math.min(minPrice, price);
      maxPrice = Math.max(maxPrice, price);
    }
  }

  return {
    count: payloads.length,
    mssqlRowsFetched: rows.length,
    byMetal,
    byStore,
    priceRangeKrw:
      minPrice === Infinity ? null : { min: minPrice, max: maxPrice },
  };
}

(async () => {
  sync.requireEnv();
  const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    realtime: { transport: ws },
  });

  const maxNumericBefore = await findMaxNumericProductIdBefore(supabase, MIN_ID);
  console.log(
    `[precheck] max numeric products.id strictly before ${MIN_ID}: ` +
      `${maxNumericBefore ?? 'none'}`,
  );
  if (maxNumericBefore !== null && maxNumericBefore < MIN_ID - 1) {
    console.warn(
      `[precheck] gap: last warehouse id ${maxNumericBefore}, next batch starts at ${MIN_ID} ` +
        `(missing ${MIN_ID - maxNumericBefore - 1} id(s) in Supabase)`,
    );
  }

  let pool;
  try {
    pool = await sync.runMssqlWithTimeout(
      'sql.connect',
      () => sql.connect(sync.MSSQL_CONFIG),
      null,
      sync.MSSQL_CONNECT_TIMEOUT_MS,
    );
    const rows = await fetchMssqlIdRange(pool, MIN_ID, MAX_ID);
    console.log(`[mssql] Items ${MIN_ID}..${MAX_ID}: ${rows.length} row(s)`);
    if (rows.length !== MAX_ID - MIN_ID + 1) {
      console.warn(
        `[mssql] expected ${MAX_ID - MIN_ID + 1} rows, got ${rows.length} — проверьте склад`,
      );
    }

    const { payloads, rowErrors } = await importRange(supabase, pool, rows);
    const expectedIds = rows.map((r) => String(r.Id));
    const present = await idsPresentInSupabase(supabase, expectedIds);
    const ok = expectedIds.filter((id) => present.has(id));
    const summary = summarizeImported(rows, payloads);

    const report = {
      idRange: { min: MIN_ID, max: MAX_ID },
      maxNumericProductIdBeforeMin: maxNumericBefore,
      mssqlRows: rows.length,
      preparedForUpsert: payloads.length,
      confirmedInSupabase: ok.length,
      failedPrepare: rowErrors.length,
      rowErrors,
      summary,
      confirmedIds: ok,
    };
    console.log('\n=== IMPORT REPORT ===');
    console.log(JSON.stringify(report, null, 2));
    if (ok.length !== rows.length) {
      process.exitCode = 1;
    }
  } finally {
    if (pool) {
      try {
        await pool.close();
      } catch (_) {
        /* ignore */
      }
    }
  }
})().catch((err) => {
  console.error(err);
  process.exit(1);
});