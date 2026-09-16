/**
 * DrJaw (MSSQL) → Supabase public.products
 * Cron/server: npm run sync
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 */

require('dotenv').config();

const sql = require('mssql');
const ws = require('ws');
const { createClient } = require('@supabase/supabase-js');
const translate = require('google-translate-api-x');

const PROGRESS_EVERY = 15;

const MSSQL_CONFIG = {
  server: process.env.MSSQL_HOST || '211.176.43.226',
  port: Number(process.env.MSSQL_PORT || 1433),
  user: process.env.MSSQL_USER || 'DrJ_Reader',
  password: process.env.MSSQL_PASSWORD || 'Read_only11!',
  database: process.env.MSSQL_DATABASE || 'DrJaw',
  options: {
    encrypt: false,
    trustServerCertificate: true,
  },
  pool: { max: 5, min: 0, idleTimeoutMillis: 30000 },
};

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const STORAGE_BUCKET = 'product-images';
const STORAGE_FOLDER = 'products';
/** Бизнес «В наличии»; в DrJaw фактически `InStock` (кириллица в БД не используется). */
const IN_STOCK_STATUSES = ['InStock', 'В наличии'];
const TARGET_LANGS = ['ko', 'kk', 'uz', 'en'];

/** Кэш переводов: Type|Articul|Stones → name jsonb */
const translationCache = Object.create(null);

function requireEnv() {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error(
      'Задайте SUPABASE_URL и SUPABASE_SERVICE_ROLE_KEY в .env (service_role, только сервер).',
    );
  }
  if (!SUPABASE_URL.includes('.supabase.co')) {
    throw new Error(
      `SUPABASE_URL должен быть Project URL вида https://<ref>.supabase.co (сейчас: ${SUPABASE_URL})`,
    );
  }
}

function translationCacheKey(row) {
  const type = (row.Type || '').trim();
  const articul = (row.Articul || '').trim();
  const stones = (row.Stones || '').trim();
  return `${type}|${articul}|${stones}`;
}

function buildRussianTitle(row) {
  const type = (row.Type || '').trim();
  const articul = (row.Articul || '').trim();
  const stones = (row.Stones || '').trim();
  const stonesPart = stones ? ` с ${stones}` : '';
  return `${type} ${articul}${stonesPart}`.replace(/\s+/g, ' ').trim();
}

function isRateLimitError(err) {
  const message = (err && err.message) || String(err);
  return /too many requests/i.test(message) || err?.code === 429;
}

/** Fallback: артикул во все локали, чтобы upsert не сорвался. */
function fallbackNameFromArticul(row, russianTitle) {
  const articul = String(row.Articul || '').trim() || russianTitle;
  return {
    ru: articul,
    ko: articul,
    kk: articul,
    uz: articul,
    en: articul,
  };
}

/**
 * Перевод с защитой от rate limit: при Too Many Requests — Articul во все 5 языков.
 */
async function safeTranslate(row) {
  const russianTitle = buildRussianTitle(row);
  const cacheKey = translationCacheKey(row);
  if (translationCache[cacheKey]) {
    return {
      russianTitle,
      name: translationCache[cacheKey],
      fromCache: true,
      usedArticulFallback: false,
    };
  }

  const name = { ru: russianTitle };

  try {
    for (const lang of TARGET_LANGS) {
      try {
        const res = await translate(russianTitle, { from: 'ru', to: lang });
        name[lang] = res.text || russianTitle;
      } catch (err) {
        if (isRateLimitError(err)) {
          console.warn(
            `safeTranslate: Too Many Requests (${lang}) — Articul для всех языков, sku=${row.Articul}`,
          );
          const fallback = fallbackNameFromArticul(row, russianTitle);
          translationCache[cacheKey] = fallback;
          return {
            russianTitle,
            name: fallback,
            fromCache: false,
            usedArticulFallback: true,
          };
        }
        console.warn(`safeTranslate ${lang}:`, err.message);
        name[lang] = russianTitle;
      }
    }
    translationCache[cacheKey] = name;
    return {
      russianTitle,
      name,
      fromCache: false,
      usedArticulFallback: false,
    };
  } catch (err) {
    console.warn('safeTranslate fatal (fallback Articul):', err.message);
    const fallback = fallbackNameFromArticul(row, russianTitle);
    translationCache[cacheKey] = fallback;
    return {
      russianTitle,
      name: fallback,
      fromCache: false,
      usedArticulFallback: true,
    };
  }
}

async function getNameMapForRow(row) {
  return safeTranslate(row);
}

function mapWarehouseStatus(mssqlStatus) {
  const normalized = (mssqlStatus || '').trim();
  if (IN_STOCK_STATUSES.includes(normalized)) {
    return { status: 'active', stock_quantity: 1 };
  }
  return { status: 'hidden', stock_quantity: 0 };
}

function parseSizeArray(sizeValue) {
  if (sizeValue === null || sizeValue === undefined || sizeValue === '') {
    return [];
  }
  const n = parseFloat(String(sizeValue).replace(',', '.'));
  if (Number.isNaN(n)) return [];
  return [n];
}

function parseWeight(weightValue) {
  if (weightValue === null || weightValue === undefined || weightValue === '') {
    return null;
  }
  const n = parseFloat(String(weightValue).replace(',', '.'));
  return Number.isNaN(n) ? null : n;
}

function parsePriceKrw(priceValue) {
  const n = Math.round(Number(priceValue));
  return Number.isFinite(n) && n >= 0 ? n : 0;
}

const JEWELRY_TYPE_KEYWORDS = [
  'Кольцо',
  'Серьги',
  'Подвеска',
  'Цепь',
  'Браслет',
  'Брошь',
  'Колье',
];

const ACCESSORIES_TYPE_KEYWORDS = [
  'Коробочка',
  'Футляр',
  'Проставки',
  'Икона',
  'Упаковка',
  'Пакет',
];

function typeMatchesKeyword(typeRaw, keyword) {
  const type = String(typeRaw || '').trim();
  if (!type) return false;
  return type === keyword || type.includes(keyword);
}

function resolveMenuTypeFromItemType(typeRaw) {
  const type = String(typeRaw || '').trim();
  if (!type) return 'jewelry';

  if (ACCESSORIES_TYPE_KEYWORDS.some((kw) => typeMatchesKeyword(type, kw))) {
    return 'accessories';
  }
  if (JEWELRY_TYPE_KEYWORDS.some((kw) => typeMatchesKeyword(type, kw))) {
    return 'jewelry';
  }
  return 'jewelry';
}

/** Сборка warehouse_attributes: существующие ключи сохраняются, menu_type добавляется/обновляется. */
function buildWarehouseAttributes(row, extra = {}) {
  const base = {
    original_mart: row.Mart != null ? String(row.Mart) : null,
    ...extra,
  };
  return {
    ...base,
    menu_type: resolveMenuTypeFromItemType(row.Type),
  };
}

function logProgress(processed, total, photosUploaded, skippedSold) {
  console.log(
    `[Синхронизация] Обработано: ${processed} из ${total} товаров... ` +
      `Загружено фото: ${photosUploaded}... Пропущено (sold в Supabase): ${skippedSold}`,
  );
}

async function uploadArticulImage(supabase, articul, imageBuffer) {
  if (!imageBuffer || !Buffer.isBuffer(imageBuffer) || imageBuffer.length === 0) {
    return null;
  }
  const safeArticul = String(articul).replace(/[^\w.-]+/g, '_');
  const objectPath = `${STORAGE_FOLDER}/${safeArticul}.jpg`;
  const { error: uploadError } = await supabase.storage
    .from(STORAGE_BUCKET)
    .upload(objectPath, imageBuffer, {
      contentType: 'image/jpeg',
      upsert: true,
    });
  if (uploadError) {
    console.warn(`Storage upload ${objectPath}:`, uploadError.message);
    return null;
  }
  const { data } = supabase.storage.from(STORAGE_BUCKET).getPublicUrl(objectPath);
  return data.publicUrl || null;
}

async function fetchArticulImageBuffer(pool, articul) {
  const result = await pool
    .request()
    .input('articul', sql.NVarChar, articul)
    .query(`
      SELECT TOP 1 a.Image
      FROM Articuls AS a
      WHERE a.Articul = @articul
    `);
  const row = result.recordset?.[0];
  if (!row?.Image) return null;
  return Buffer.isBuffer(row.Image) ? row.Image : Buffer.from(row.Image);
}

async function fetchDrJawRows(pool) {
  const result = await pool
    .request()
    .input('inStockEn', sql.NVarChar, 'InStock')
    .input('inStockRu', sql.NVarChar, 'В наличии')
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
      a.Type,
      a.Metall
    FROM Items AS i
    INNER JOIN Articuls AS a ON i.Articul = a.Articul
    WHERE i.Status IN (@inStockEn, @inStockRu)
  `);
  return result.recordset || [];
}

async function fetchSupabaseStatusMap(supabase) {
  const { data, error } = await supabase.from('products').select('id, status');
  if (error) throw error;
  const map = new Map();
  for (const row of data || []) {
    map.set(row.id, row.status);
  }
  return map;
}

async function syncProducts(supabase, pool, allInStockRows, rowsToProcess) {
  const statusMap = await fetchSupabaseStatusMap(supabase);
  const mssqlIds = new Set(
    allInStockRows
      .map((row) => String(row.Id))
      .filter((id) => id && id !== 'undefined'),
  );

  let upserted = 0;
  let skippedSold = 0;
  let photosUploaded = 0;
  let translationApiCalls = 0;
  const total = rowsToProcess.length;

  for (let index = 0; index < rowsToProcess.length; index += 1) {
    const row = rowsToProcess[index];
    const id = String(row.Id);
    const sku = String(row.Articul || '').trim();
    if (!id || !sku) continue;

    if (statusMap.get(id) === 'sold') {
      skippedSold += 1;
    } else {
      const { russianTitle, name, fromCache } = await getNameMapForRow(row);
      if (!fromCache) translationApiCalls += 1;

      const { status, stock_quantity } = mapWarehouseStatus(row.Status);
      const imageBuffer = await fetchArticulImageBuffer(pool, sku);
      const imageUrl = await uploadArticulImage(supabase, sku, imageBuffer);
      if (imageUrl) photosUploaded += 1;

      const weightGrams = parseWeight(row.Weight);
      const salePrice = parsePriceKrw(row.Price);

      const payload = {
        id,
        sku,
        stock_quantity,
        status,
        name,
        description: {
          ru: russianTitle,
          ko: name.ko,
          kk: name.kk,
          uz: name.uz,
          en: name.en,
        },
        metal: String(row.Metall || '').trim() || '—',
        sale_price: salePrice,
        old_price: salePrice,
        discount_percent: 0,
        category: String(row.Type || '').trim() || 'Изделие',
        insert: String(row.Stones || '').trim() || '—',
        icon_index: 0,
        available_sizes: parseSizeArray(row.Size),
        warehouse_attributes: buildWarehouseAttributes(row),
        image_url: imageUrl,
        weight_grams: weightGrams,
      };

      const { error } = await supabase.from('products').upsert(payload, {
        onConflict: 'id',
      });
      if (error) {
        console.error(`upsert id=${id} sku=${sku}:`, error.message);
      } else {
        upserted += 1;
      }
    }

    const processed = index + 1;
    if (processed % PROGRESS_EVERY === 0 || processed === total) {
      logProgress(processed, total, photosUploaded, skippedSold);
    }
  }

  return {
    mssqlIds,
    upserted,
    skippedSold,
    photosUploaded,
    translationApiCalls,
    cacheSize: Object.keys(translationCache).length,
  };
}

async function cleanupRemovedFromMssql(supabase, mssqlIds) {
  const { data, error } = await supabase.from('products').select('id');
  if (error) throw error;

  const toDelete = (data || [])
    .map((r) => r.id)
    .filter((id) => !mssqlIds.has(id));

  if (toDelete.length === 0) return 0;

  const { error: deleteError } = await supabase
    .from('products')
    .delete()
    .in('id', toDelete);

  if (deleteError) throw deleteError;
  return toDelete.length;
}

async function applyDropSkuUniqueConstraint() {
  console.log('[Schema] products.sku без UNIQUE — upsert по Items.Id (products.id).');
}

async function main() {
  requireEnv();
  await applyDropSkuUniqueConstraint();
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    realtime: { transport: ws },
  });

  let pool;
  try {
    pool = await sql.connect(MSSQL_CONFIG);
    console.log('MSSQL DrJaw: connected');

    console.log(
      `Загрузка позиций «В наличии» (DrJaw: ${IN_STOCK_STATUSES.join(' / ')})…`,
    );
    const allInStockRows = await fetchDrJawRows(pool);
    console.log(`MSSQL «В наличии» (Items ⨝ Articuls): ${allInStockRows.length} строк`);

    const rowsToProcess = allInStockRows;
    console.log(`[ПОЛНЫЙ SYNC] К обработке: ${rowsToProcess.length} позиций`);

    const stats = await syncProducts(supabase, pool, allInStockRows, rowsToProcess);

    const deleted = await cleanupRemovedFromMssql(supabase, stats.mssqlIds);

    console.log('---');
    console.log(
      `Sync done: upserted=${stats.upserted}, skipped_sold=${stats.skippedSold}, ` +
        `photos=${stats.photosUploaded}, deleted=${deleted}`,
    );
    console.log(
      `Переводы: уникальных в кэше=${stats.cacheSize}, API-вызовов (новых ключей)=${stats.translationApiCalls}`,
    );
  } finally {
    if (pool) await pool.close();
  }
}

main().catch((err) => {
  console.error('sync.js fatal:', err);
  process.exit(1);
});
