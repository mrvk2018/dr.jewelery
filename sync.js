/**
 * DrJaw (MSSQL) → Supabase public.products
 * Cron/server: npm run sync (polls sync_tasks; runs import only if sync_requested)
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 */

require('dotenv').config();

const sql = require('mssql');
const ws = require('ws');
const { createClient } = require('@supabase/supabase-js');
const translate = require('google-translate-api-x');
const sharp = require('sharp');

const PROGRESS_EVERY = Number(process.env.SYNC_PROGRESS_EVERY || 15);
const SYNC_LOG_EACH_ROW = process.env.SYNC_LOG_EACH_ROW === '1';

/** TCP/login к MSSQL (склад часто отвечает дольше 5 с). */
const MSSQL_CONNECT_TIMEOUT_MS = Number(
  process.env.MSSQL_CONNECT_TIMEOUT_MS ||
    process.env.MSSQL_TIMEOUT_MS ||
    30000,
);
/** SELECT каталога Items ⨝ Articuls. */
const MSSQL_QUERY_TIMEOUT_MS = Number(process.env.MSSQL_QUERY_TIMEOUT_MS || 60000);
/** BLOB Articuls.Image — отдельный лимит на скачивание. */
const MSSQL_BLOB_TIMEOUT_MS = Number(process.env.MSSQL_BLOB_TIMEOUT_MS || 25000);

const MSSQL_CONFIG = {
  server: process.env.MSSQL_HOST || '211.176.43.226',
  port: Number(process.env.MSSQL_PORT || 1433),
  user: process.env.MSSQL_USER || 'DrJ_Reader',
  password: process.env.MSSQL_PASSWORD || 'Read_only11!',
  database: process.env.MSSQL_DATABASE || 'DrJaw',
  connectionTimeout: MSSQL_CONNECT_TIMEOUT_MS,
  /** Верхняя граница для tedious; точные лимиты — request.timeout в каждом запросе. */
  requestTimeout: MSSQL_BLOB_TIMEOUT_MS,
  options: {
    encrypt: false,
    trustServerCertificate: true,
  },
  pool: { max: 5, min: 0, idleTimeoutMillis: 30000 },
};

/**
 * MSSQL-операция с Promise.race (на случай зависания ниже драйвера).
 * @param {string} label
 * @param {(import('mssql').ConnectionPool) => Promise<T>} operation
 * @param {import('mssql').ConnectionPool | null} pool
 * @param {number} [timeoutMs=MSSQL_QUERY_TIMEOUT_MS]
 * @returns {Promise<T>}
 */
async function runMssqlWithTimeout(label, operation, pool, timeoutMs = MSSQL_QUERY_TIMEOUT_MS) {
  let timer;
  const timeoutPromise = new Promise((_, reject) => {
    timer = setTimeout(() => {
      reject(new Error(`${label}: MSSQL timeout after ${timeoutMs}ms`));
    }, timeoutMs);
  });
  try {
    return await Promise.race([operation(pool), timeoutPromise]);
  } finally {
    clearTimeout(timer);
  }
}

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const STORAGE_BUCKET = 'product-images';
const STORAGE_FOLDER = 'products';
/** Бизнес «В наличии»; в DrJaw фактически `InStock` (кириллица в БД не используется). */
const IN_STOCK_STATUSES = ['InStock', 'В наличии'];
const TARGET_LANGS = ['ko', 'kk', 'uz', 'en'];

/** Не перезаписывать из MSSQL и не удалять при cleanup (checkout / продажи / скрытые). */
const SYNC_SKIP_STATUSES = new Set(['reserved', 'sold', 'hidden']);

/** PostgREST max rows per select; paginate with `.range()`. */
const SUPABASE_PAGE_SIZE = 1000;
/** Max ids per `.delete().in('id', chunk)` to stay within URL/filter limits. */
const DELETE_CHUNK_SIZE = 500;

/** Поля products для зеркальной сверки MSSQL ↔ Supabase. */
const MIRROR_PRODUCT_COLUMNS =
  'id, sku, stock_quantity, status, name, description, metal, sale_price, old_price, ' +
  'discount_percent, category, insert, icon_index, available_sizes, warehouse_attributes, ' +
  'weight_grams, image_url, images';

const MIRROR_SCALAR_KEYS = [
  'sku',
  'stock_quantity',
  'status',
  'name',
  'description',
  'metal',
  'sale_price',
  'old_price',
  'discount_percent',
  'category',
  'insert',
  'icon_index',
  'available_sizes',
  'warehouse_attributes',
  'weight_grams',
];

const SYNC_TASK_ID = 'catalog_sync';

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

/** Отпечатки BLOB/Storage в warehouse_attributes (сверка без смены URL). */
const WA_IMAGE_SLOT_MSSQL_BYTES = 'image_slot_mssql_bytes';
const WA_IMAGE_SLOT_STORAGE_BYTES = 'image_slot_storage_bytes';
const WA_IMAGE_FINGERPRINTS_AT = 'image_fingerprints_synced_at';

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

function warehouseAttributesForScalarCompare(attrs) {
  if (!attrs || typeof attrs !== 'object') return attrs;
  const copy = { ...attrs };
  delete copy[WA_IMAGE_SLOT_MSSQL_BYTES];
  delete copy[WA_IMAGE_SLOT_STORAGE_BYTES];
  delete copy[WA_IMAGE_FINGERPRINTS_AT];
  return copy;
}

/** Размеры BLOB со склада (MSSQL varbinary) по слотам 0..3. */
function slotMssqlByteSizes(slots) {
  const sizes = [0, 0, 0, 0];
  for (let i = 0; i < Math.min(slots.length, sizes.length); i += 1) {
    const buf = slots[i];
    sizes[i] = buf && Buffer.isBuffer(buf) ? buf.length : 0;
  }
  return sizes;
}

function readStoredByteArray(warehouseAttributes, key) {
  const wa = warehouseAttributes || {};
  const arr = wa[key];
  if (!Array.isArray(arr)) return null;
  return arr.map((n) => Number(n) || 0);
}

function byteSizeArraysEqual(a, b) {
  if (!a || !b || a.length !== b.length) return false;
  for (let i = 0; i < a.length; i += 1) {
    if (Number(a[i]) !== Number(b[i])) return false;
  }
  return true;
}

function mergeWarehouseImageFingerprints(row, mssqlBytes, storageBytes) {
  return buildWarehouseAttributes(row, {
    [WA_IMAGE_SLOT_MSSQL_BYTES]: mssqlBytes,
    [WA_IMAGE_SLOT_STORAGE_BYTES]: storageBytes,
    [WA_IMAGE_FINGERPRINTS_AT]: new Date().toISOString(),
  });
}

function logProgress(processed, total, photosUploaded, skippedProtected) {
  console.log(
    `[Синхронизация] Обработано: ${processed} из ${total} товаров... ` +
      `Загружено фото: ${photosUploaded}... Пропущено (защищённые статусы): ${skippedProtected}`,
  );
}

/** Суффиксы Storage: image1 → .webp, image2 → _1.webp, … */
const ARTICUL_IMAGE_SLOT_SUFFIXES = ['', '_1', '_2', '_3'];
const PRODUCT_IMAGE_MAX_SIDE_PX = 1600;
const PRODUCT_IMAGE_WEBP_QUALITY = 85;

function mssqlVarbinaryToBuffer(value) {
  if (value === null || value === undefined) return null;
  const buf = Buffer.isBuffer(value) ? value : Buffer.from(value);
  return buf.length > 0 ? buf : null;
}

/**
 * Все BLOB артикула: Articuls.Image + articul_images.image2..image4.
 * @returns {Promise<{ image1: Buffer|null, image2: Buffer|null, image3: Buffer|null, image4: Buffer|null, slots: (Buffer|null)[] }>}
 */
async function fetchArticulImageBuffers(pool, articul) {
  const empty = {
    image1: null,
    image2: null,
    image3: null,
    image4: null,
    slots: [null, null, null, null],
  };

  return runMssqlWithTimeout(
    `fetchArticulImageBuffers(${articul})`,
    async (activePool) => {
      const request = activePool.request();
      request.timeout = MSSQL_BLOB_TIMEOUT_MS;
      const result = await request
        .input('articul', sql.NVarChar, articul)
        .query(`
      SELECT TOP 1
        a.Image AS image1,
        ai.image2,
        ai.image3,
        ai.image4
      FROM dbo.Articuls AS a
      LEFT JOIN dbo.articul_images AS ai ON a.Articul = ai.articul
      WHERE a.Articul = @articul
    `);
      const row = result.recordset?.[0];
      if (!row) return empty;

      const image1 = mssqlVarbinaryToBuffer(row.image1);
      const image2 = mssqlVarbinaryToBuffer(row.image2);
      const image3 = mssqlVarbinaryToBuffer(row.image3);
      const image4 = mssqlVarbinaryToBuffer(row.image4);
      return {
        image1,
        image2,
        image3,
        image4,
        slots: [image1, image2, image3, image4],
      };
    },
    pool,
    MSSQL_BLOB_TIMEOUT_MS,
  );
}

/**
 * BLOB со склада → WebP (resize + quality) перед Storage.
 * @param {Buffer} imageBuffer
 * @returns {Promise<Buffer|null>}
 */
async function optimizeProductImageBuffer(imageBuffer, logContext = {}) {
  const blobBytes = imageBuffer?.length ?? 0;
  try {
    return await sharp(imageBuffer)
      .resize(PRODUCT_IMAGE_MAX_SIDE_PX, PRODUCT_IMAGE_MAX_SIDE_PX, {
        fit: 'inside',
        withoutEnlargement: true,
      })
      .webp({ quality: PRODUCT_IMAGE_WEBP_QUALITY })
      .toBuffer();
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(
      `[sync:image] sharp failed sku=${logContext.sku ?? '?'} slot=${logContext.slotIndex ?? '?'} ` +
        `productId=${logContext.productId ?? '?'} blobBytes=${blobBytes}: ${message}`,
    );
    return null;
  }
}

/**
 * @param {number} slotIndex 0..3 → .webp, _1.webp, _2.webp, _3.webp
 * @param {number} [cacheVersion] общий ?v= для всех кадров одного upsert
 */
async function uploadArticulImageSlot(
  supabase,
  articul,
  imageBuffer,
  slotIndex,
  cacheVersion = Date.now(),
  logContext = {},
) {
  const sku = String(articul || '').trim();
  const ctx = { sku, slotIndex, productId: logContext.productId ?? '?' };

  if (!imageBuffer || !Buffer.isBuffer(imageBuffer) || imageBuffer.length === 0) {
    console.error(
      `[sync:image] empty blob sku=${sku} slot=${slotIndex} productId=${ctx.productId}`,
    );
    return null;
  }

  const optimizedBuffer = await optimizeProductImageBuffer(imageBuffer, ctx);
  if (!optimizedBuffer || optimizedBuffer.length === 0) {
    console.error(
      `[sync:image] optimize returned empty sku=${sku} slot=${slotIndex} ` +
        `productId=${ctx.productId} blobBytes=${imageBuffer.length}`,
    );
    return null;
  }

  const safeArticul = sku.replace(/[^\w.-]+/g, '_');
  if (safeArticul !== sku) {
    console.warn(
      `[sync:image] sku sanitized for storage: "${sku}" → "${safeArticul}" slot=${slotIndex}`,
    );
  }
  const suffix =
    ARTICUL_IMAGE_SLOT_SUFFIXES[slotIndex] ??
    `_${Math.max(0, slotIndex)}`;
  const objectPath = `${STORAGE_FOLDER}/${safeArticul}${suffix}.webp`;
  const { error: uploadError } = await supabase.storage
    .from(STORAGE_BUCKET)
    .upload(objectPath, optimizedBuffer, {
      contentType: 'image/webp',
      upsert: true,
    });
  if (uploadError) {
    console.error(
      `[sync:image] storage upload failed sku=${sku} slot=${slotIndex} path=${objectPath} ` +
        `productId=${ctx.productId}: ${uploadError.message}`,
    );
    return null;
  }
  const { data } = supabase.storage.from(STORAGE_BUCKET).getPublicUrl(objectPath);
  const publicUrl = data.publicUrl?.trim();
  if (!publicUrl) {
    console.error(
      `[sync:image] no public URL sku=${sku} slot=${slotIndex} path=${objectPath} ` +
        `productId=${ctx.productId}`,
    );
    return null;
  }
  return {
    url: `${publicUrl}?v=${cacheVersion}`,
    mssqlSourceBytes: imageBuffer.length,
    storageBytes: optimizedBuffer.length,
  };
}

async function fetchDrJawRows(pool) {
  return runMssqlWithTimeout('fetchDrJawRows', async (activePool) => {
    const request = activePool.request();
    request.timeout = MSSQL_QUERY_TIMEOUT_MS;
    const result = await request
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
  }, pool);
}

/**
 * @param {import('@supabase/supabase-js').SupabaseClient} supabase
 * @param {string} columns — аргумент `.select()`, напр. `'id, status'`
 * @param {string | null} [statusFilter] — если задан, `.eq('status', statusFilter)`
 * @returns {Promise<Record<string, unknown>[]>}
 */
async function fetchAllProducts(supabase, columns, statusFilter = null) {
  const all = [];
  let from = 0;
  let page = 0;

  for (;;) {
    page += 1;
    const to = from + SUPABASE_PAGE_SIZE - 1;
    let query = supabase
      .from('products')
      .select(columns)
      .order('id', { ascending: true })
      .range(from, to);

    if (statusFilter != null) {
      query = query.eq('status', statusFilter);
    }

    const { data, error } = await query;
    if (error) {
      console.error(
        `[sync:fetch] page=${page} range=${from}-${to} statusFilter=${statusFilter ?? 'all'} failed:`,
        error.message,
      );
      throw error;
    }
    if (!data || data.length === 0) {
      console.log(
        `[sync:fetch] page=${page} range=${from}-${to} empty — done, total=${all.length}`,
      );
      break;
    }

    all.push(...data);
    console.log(
      `[sync:fetch] page=${page} range=${from}-${to} got=${data.length} cumulative=${all.length}`,
    );

    if (data.length < SUPABASE_PAGE_SIZE) break;
    from += SUPABASE_PAGE_SIZE;
  }

  if (all.length > 0 && all.length % SUPABASE_PAGE_SIZE === 0) {
    console.warn(
      `[sync:fetch] row count ${all.length} is an exact multiple of page size ${SUPABASE_PAGE_SIZE} — ` +
        'verify pagination did not truncate (expect one more empty page).',
    );
  }

  return all;
}

async function fetchSupabaseProductMap(supabase) {
  const rows = await fetchAllProducts(supabase, MIRROR_PRODUCT_COLUMNS);
  console.log(`[sync:mirror] Supabase products loaded: ${rows.length}`);

  const byId = new Map();
  const statusMap = new Map();
  for (const row of rows) {
    const id = String(row.id);
    byId.set(id, row);
    statusMap.set(id, row.status);
  }
  return { byId, statusMap };
}

function stripUrlCacheBuster(url) {
  const s = String(url || '').trim();
  if (!s) return '';
  const q = s.indexOf('?');
  return q >= 0 ? s.slice(0, q) : s;
}

function normalizeJsonValue(value) {
  if (value === null || value === undefined) return null;
  if (Array.isArray(value)) return value.map(normalizeJsonValue);
  if (typeof value === 'object') {
    const sorted = {};
    for (const key of Object.keys(value).sort()) {
      sorted[key] = normalizeJsonValue(value[key]);
    }
    return sorted;
  }
  return value;
}

function stableJson(value) {
  return JSON.stringify(normalizeJsonValue(value));
}

function normalizeWeightForCompare(weightValue) {
  const n = parseWeight(weightValue);
  return n === null ? null : n;
}

function imagesComparableJson(imageUrl, images) {
  let list = [];
  if (Array.isArray(images) && images.length > 0) {
    list = images.map((u) => stripUrlCacheBuster(u)).filter((u) => u.length > 0);
  } else if (imageUrl) {
    const stripped = stripUrlCacheBuster(imageUrl);
    if (stripped) list = [stripped];
  }
  return JSON.stringify(list);
}

function storagePublicUrlBase(supabase, articul, slotIndex) {
  const safeArticul = String(articul).replace(/[^\w.-]+/g, '_');
  const suffix =
    ARTICUL_IMAGE_SLOT_SUFFIXES[slotIndex] ??
    `_${Math.max(0, slotIndex)}`;
  const objectPath = `${STORAGE_FOLDER}/${safeArticul}${suffix}.webp`;
  const { data } = supabase.storage.from(STORAGE_BUCKET).getPublicUrl(objectPath);
  return data.publicUrl?.trim() || '';
}

function expectedImageUrlsFromSlots(supabase, sku, slots) {
  const urls = [];
  for (let slot = 0; slot < slots.length; slot += 1) {
    if (!slots[slot]) continue;
    const base = storagePublicUrlBase(supabase, sku, slot);
    if (base) urls.push(base);
  }
  return urls;
}

function mirrorImageUrlsMatch(supabase, sku, slots, existingRow) {
  const expectedJson = JSON.stringify(expectedImageUrlsFromSlots(supabase, sku, slots));
  const existingJson = imagesComparableJson(existingRow.image_url, existingRow.images);
  return expectedJson === existingJson;
}

/**
 * Сверка отпечатков: размер BLOB varbinary на складе (байты) vs сохранённый в warehouse_attributes.
 * @returns {{ match: boolean, mssqlMismatch: boolean }}
 */
function mirrorImageFingerprintsMatch(slots, existingRow) {
  const desiredMssql = slotMssqlByteSizes(slots);
  const storedMssql = readStoredByteArray(
    existingRow?.warehouse_attributes,
    WA_IMAGE_SLOT_MSSQL_BYTES,
  );

  const mssqlMismatch =
    storedMssql === null || !byteSizeArraysEqual(desiredMssql, storedMssql);

  return {
    match: !mssqlMismatch,
    mssqlMismatch,
  };
}

function mirrorScalarsMatch(desiredScalars, supabaseRow) {
  for (const key of MIRROR_SCALAR_KEYS) {
    const desired = desiredScalars[key];
    const existing = supabaseRow[key];

    if (key === 'weight_grams') {
      if (normalizeWeightForCompare(desired) !== normalizeWeightForCompare(existing)) {
        return false;
      }
      continue;
    }

    if (
      key === 'name' ||
      key === 'description' ||
      key === 'available_sizes'
    ) {
      if (stableJson(desired) !== stableJson(existing)) return false;
      continue;
    }

    if (key === 'warehouse_attributes') {
      const desiredWa = warehouseAttributesForScalarCompare(desired);
      const existingWa = warehouseAttributesForScalarCompare(existing);
      if (stableJson(desiredWa) !== stableJson(existingWa)) return false;
      continue;
    }

    if (key === 'sale_price' || key === 'old_price' || key === 'discount_percent' || key === 'stock_quantity' || key === 'icon_index') {
      if (Number(desired) !== Number(existing)) return false;
      continue;
    }

    if (String(desired ?? '') !== String(existing ?? '')) return false;
  }
  return true;
}

async function buildDesiredScalarsForRow(row) {
  const { russianTitle, name, fromCache } = await getNameMapForRow(row);
  const { status, stock_quantity } = mapWarehouseStatus(row.Status);
  const salePrice = parsePriceKrw(row.Price);

  const scalars = {
    sku: String(row.Articul || '').trim(),
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
    weight_grams: parseWeight(row.Weight),
  };

  return { scalars, fromCache };
}

async function getArticulSlotsCached(pool, sku, slotsCache) {
  if (slotsCache.has(sku)) return slotsCache.get(sku);
  const { slots } = await fetchArticulImageBuffers(pool, sku);
  slotsCache.set(sku, slots);
  return slots;
}

/**
 * @returns {Promise<{ imageUrls: string[], mssqlBytes: number[], storageBytes: number[] }>}
 */
async function uploadImageUrlsFromSlots(supabase, sku, slots, logContext = {}) {
  const imageUrls = [];
  const mssqlBytes = [0, 0, 0, 0];
  const storageBytes = [0, 0, 0, 0];
  const cacheVersion = Date.now();
  let expectedSlots = 0;
  let failedSlots = 0;

  for (let slot = 0; slot < slots.length; slot += 1) {
    const imageBuffer = slots[slot];
    if (!imageBuffer) continue;
    expectedSlots += 1;
    const uploaded = await uploadArticulImageSlot(
      supabase,
      sku,
      imageBuffer,
      slot,
      cacheVersion,
      logContext,
    );
    if (uploaded?.url) {
      imageUrls.push(uploaded.url);
      mssqlBytes[slot] = uploaded.mssqlSourceBytes;
      storageBytes[slot] = uploaded.storageBytes;
    } else {
      failedSlots += 1;
    }
  }

  if (expectedSlots > 0 && failedSlots > 0) {
    console.error(
      `[sync:image] partial upload sku=${sku} productId=${logContext.productId ?? '?'} ` +
        `ok=${imageUrls.length}/${expectedSlots} failedSlots=${failedSlots}`,
    );
  }

  return { imageUrls, mssqlBytes, storageBytes, expectedSlots, failedSlots };
}

async function upsertProductsInChunks(supabase, payloads) {
  if (payloads.length === 0) return;

  const totalChunks = Math.ceil(payloads.length / DELETE_CHUNK_SIZE);
  for (let i = 0; i < payloads.length; i += DELETE_CHUNK_SIZE) {
    const chunk = payloads.slice(i, i + DELETE_CHUNK_SIZE);
    const chunkIndex = Math.floor(i / DELETE_CHUNK_SIZE) + 1;
    const { error } = await supabase.from('products').upsert(chunk, {
      onConflict: 'id',
    });
    if (error) throw error;
    console.log(
      `[sync:mirror] upsert chunk ${chunkIndex}/${totalChunks}: ${chunk.length} rows`,
    );
  }
}

async function syncProducts(supabase, pool, allInStockRows, rowsToProcess) {
  const { byId: supabaseById, statusMap } = await fetchSupabaseProductMap(supabase);
  const mssqlIds = new Set(
    allInStockRows
      .map((row) => String(row.Id))
      .filter((id) => id && id !== 'undefined'),
  );

  const toInsert = [];
  const toUpdate = [];
  let skippedIdentical = 0;
  let skippedProtected = 0;
  let rowErrors = 0;
  let photosUploaded = 0;
  let photosReuploadedDueToSize = 0;
  let translationApiCalls = 0;
  const total = rowsToProcess.length;
  const articulSlotsCache = new Map();
  const skippedProtectedDetails = [];

  for (let index = 0; index < rowsToProcess.length; index += 1) {
    const row = rowsToProcess[index];
    const id = String(row.Id);
    const sku = String(row.Articul || '').trim();
    if (!id || !sku) continue;

    if (SYNC_SKIP_STATUSES.has(statusMap.get(id))) {
      skippedProtected += 1;
      skippedProtectedDetails.push({ id, sku, status: statusMap.get(id) });
      console.warn(
        `[sync:skip-protected] id=${id} sku=${sku} status=${statusMap.get(id)} — not updated from MSSQL`,
      );
      continue;
    }

    try {
      const { scalars, fromCache } = await buildDesiredScalarsForRow(row);
      if (!fromCache) translationApiCalls += 1;

      const existing = supabaseById.get(id);
      const isNew = !existing;

      let scalarsMatch = false;
      let imagesMatch = false;
      let fingerprintMismatch = false;
      let slots = null;

      if (!isNew) {
        scalarsMatch = mirrorScalarsMatch(scalars, existing);
        slots = await getArticulSlotsCached(pool, sku, articulSlotsCache);
        const urlsMatch = mirrorImageUrlsMatch(supabase, sku, slots, existing);
        const fingerprints = mirrorImageFingerprintsMatch(slots, existing);
        fingerprintMismatch = !fingerprints.match;
        imagesMatch = urlsMatch && fingerprints.match;
      }

      if (!isNew && scalarsMatch && imagesMatch) {
        skippedIdentical += 1;
        if (SYNC_LOG_EACH_ROW) {
          console.log(`[sync:mirror skip] id=${id} sku=${sku} (identical)`);
        }
      } else {
        let imageUrls = [];
        let mssqlByteSizes = slotMssqlByteSizes(slots ?? []);
        let storageByteSizes = readStoredByteArray(
          existing?.warehouse_attributes,
          WA_IMAGE_SLOT_STORAGE_BYTES,
        ) ?? [0, 0, 0, 0];
        let needUploadImages = isNew || !imagesMatch;

        if (needUploadImages) {
          try {
            slots = slots ?? (await getArticulSlotsCached(pool, sku, articulSlotsCache));
            mssqlByteSizes = slotMssqlByteSizes(slots);
            const uploaded = await uploadImageUrlsFromSlots(supabase, sku, slots, {
              productId: id,
            });
            imageUrls = uploaded.imageUrls;
            mssqlByteSizes = uploaded.mssqlBytes;
            storageByteSizes = uploaded.storageBytes;
            photosUploaded += imageUrls.length;
            if (!isNew && fingerprintMismatch) {
              photosReuploadedDueToSize += imageUrls.length;
            }
            if (uploaded.expectedSlots > 0 && uploaded.failedSlots > 0) {
              rowErrors += 1;
            }
          } catch (imageErr) {
            rowErrors += 1;
            const imageMessage =
              imageErr instanceof Error ? imageErr.message : String(imageErr);
            console.error(
              `[sync:image] fatal id=${id} sku=${sku}: ${imageMessage}`,
              imageErr instanceof Error ? imageErr.stack : '',
            );
            if (!isNew && existing) {
              imageUrls = Array.isArray(existing.images)
                ? [...existing.images]
                : existing.image_url
                  ? [existing.image_url]
                  : [];
            }
          }
        } else if (existing) {
          imageUrls = Array.isArray(existing.images)
            ? existing.images.map((u) => String(u))
            : existing.image_url
              ? [String(existing.image_url)]
              : [];
          mssqlByteSizes = slotMssqlByteSizes(
            slots ?? (await getArticulSlotsCached(pool, sku, articulSlotsCache)),
          );
        }

        const payload = {
          id,
          ...scalars,
          warehouse_attributes: mergeWarehouseImageFingerprints(
            row,
            mssqlByteSizes,
            storageByteSizes,
          ),
        };

        if (imageUrls.length > 0) {
          payload.image_url = imageUrls[0];
          payload.images = imageUrls;
        } else if (needUploadImages && slots) {
          const blobCount = slots.filter((b) => b && Buffer.isBuffer(b) && b.length > 0).length;
          if (blobCount > 0) {
            console.error(
              `[sync:image] upsert without images id=${id} sku=${sku} — ` +
                `${blobCount} MSSQL blob(s) but 0 URLs (check errors above)`,
            );
            rowErrors += 1;
          }
        }

        if (isNew) toInsert.push(payload);
        else toUpdate.push(payload);

        if (SYNC_LOG_EACH_ROW) {
          console.log(
            `[sync:mirror ${isNew ? 'insert' : 'update'}] ${index + 1}/${total} ` +
              `id=${id} sku=${sku} webp_slots=${imageUrls.length}`,
          );
        }
      }
    } catch (err) {
      rowErrors += 1;
      const message = err instanceof Error ? err.message : String(err);
      console.error(
        `[sync row skip] id=${id} sku=${sku}: ${message}`,
        err instanceof Error ? err.stack : '',
      );
    }

    const processed = index + 1;
    if (processed % PROGRESS_EVERY === 0 || processed === total) {
      logProgress(processed, total, photosUploaded, skippedProtected);
    }
  }

  const upsertPayloads = [...toInsert, ...toUpdate];
  await upsertProductsInChunks(supabase, upsertPayloads);

  if (rowErrors > 0) {
    console.warn(`[sync] строк с ошибками (пропущено): ${rowErrors}`);
  }
  if (skippedProtectedDetails.length > 0) {
    console.warn(
      `[sync:skip-protected] total=${skippedProtectedDetails.length}: ` +
        skippedProtectedDetails.map((r) => `${r.sku}(${r.status})`).join(', '),
    );
  }

  const mirrorStats = {
    mssqlTotal: mssqlIds.size,
    toUpdate: toUpdate.length,
    toInsert: toInsert.length,
    skippedIdentical,
    photosReuploadedDueToSize,
  };

  return {
    mssqlIds,
    upserted: upsertPayloads.length,
    skippedProtected,
    rowErrors,
    photosUploaded,
    translationApiCalls,
    cacheSize: Object.keys(translationCache).length,
    statusMap,
    mirrorStats,
  };
}

async function cleanupRemovedFromMssql(supabase, mssqlIds, statusMap) {
  const toDelete = [];
  for (const [id, status] of statusMap) {
    const sid = String(id);
    if (mssqlIds.has(sid)) continue;
    if (SYNC_SKIP_STATUSES.has(status)) continue;
    toDelete.push(sid);
  }

  if (toDelete.length === 0) {
    console.log('[cleanup] ghosts to delete: 0');
    return 0;
  }

  const totalChunks = Math.ceil(toDelete.length / DELETE_CHUNK_SIZE);
  console.log(
    `[cleanup] ghosts to delete: ${toDelete.length} ` +
      `(supabase rows=${statusMap.size}, mssql InStock=${mssqlIds.size}, ` +
      `chunks=${totalChunks}×≤${DELETE_CHUNK_SIZE})`,
  );

  let deleted = 0;
  for (let i = 0; i < toDelete.length; i += DELETE_CHUNK_SIZE) {
    const chunk = toDelete.slice(i, i + DELETE_CHUNK_SIZE);
    const chunkIndex = Math.floor(i / DELETE_CHUNK_SIZE) + 1;

    const { error: deleteError } = await supabase
      .from('products')
      .delete()
      .in('id', chunk);

    if (deleteError) throw deleteError;

    deleted += chunk.length;
    console.log(
      `[cleanup] chunk ${chunkIndex}/${totalChunks}: deleted ${chunk.length} ` +
        `(running total ${deleted}/${toDelete.length})`,
    );
  }

  console.log(`[cleanup] done: deleted=${deleted}`);
  return deleted;
}

async function applyDropSkuUniqueConstraint() {
  console.log('[Schema] products.sku без UNIQUE — upsert по Items.Id (products.id).');
}

async function fetchSyncTaskRequested(supabase) {
  const { data, error } = await supabase
    .from('sync_tasks')
    .select('sync_requested')
    .eq('id', SYNC_TASK_ID)
    .maybeSingle();

  if (error) throw error;
  return Boolean(data?.sync_requested);
}

async function clearSyncTaskRequested(supabase) {
  const { error } = await supabase
    .from('sync_tasks')
    .update({
      sync_requested: false,
      updated_at: new Date().toISOString(),
    })
    .eq('id', SYNC_TASK_ID);

  if (error) throw error;
}

function needsPrimaryPhotoResync(productRow) {
  const imageUrl = String(productRow.image_url || '');
  if (/\.jpe?g/i.test(imageUrl)) return true;
  const images = productRow.images;
  if (Array.isArray(images) && images.length > 0) {
    if (/\.jpe?g/i.test(String(images[0] || ''))) return true;
  }
  return false;
}

function mergePrimaryPhotoIntoImages(primaryUrl, existingImages) {
  const rest = Array.isArray(existingImages)
    ? existingImages
        .map((u) => String(u || '').trim())
        .filter((u) => u.length > 0)
        .slice(1)
    : [];
  return [primaryUrl, ...rest].slice(0, 4);
}

/**
 * Перезаливка фото 0 (Articuls.Image → {sku}.webp) для витрины со старым .jpg.
 * Не требует sync_tasks. Флаг --all-active: все active, не только .jpg.
 */
async function resyncStalePrimaryPhotos(supabase, pool, { allActive = false } = {}) {
  const rows = await fetchAllProducts(
    supabase,
    'id, sku, image_url, images, status',
    'active',
  );
  console.log(`[photo0] active products (full fetch): ${rows.length}`);

  const candidates = rows.filter((p) =>
    allActive ? true : needsPrimaryPhotoResync(p),
  );
  const skuToProductIds = new Map();
  for (const p of candidates) {
    const sku = String(p.sku || '').trim();
    if (!sku) continue;
    if (!skuToProductIds.has(sku)) skuToProductIds.set(sku, []);
    skuToProductIds.get(sku).push(p);
  }

  const skus = [...skuToProductIds.keys()];
  console.log(
    `[photo0] К обновлению: ${candidates.length} позиций, ${skus.length} уникальных sku` +
      (allActive ? ' (--all-active)' : ' (только legacy .jpg)'),
  );

  let skusUpdated = 0;
  let productsUpdated = 0;
  let skusSkippedNoBlob = 0;
  let skusSkippedUpload = 0;

  for (let i = 0; i < skus.length; i += 1) {
    const sku = skus[i];
    const productRows = skuToProductIds.get(sku) || [];

    let primaryUrl = null;
    try {
      const { slots } = await fetchArticulImageBuffers(pool, sku);
      const imageBuffer = slots[0];
      if (!imageBuffer) {
        skusSkippedNoBlob += 1;
        console.warn(`[photo0 skip] sku=${sku}: Articuls.Image пуст`);
        continue;
      }
      const uploadedPrimary = await uploadArticulImageSlot(
        supabase,
        sku,
        imageBuffer,
        0,
        Date.now(),
      );
      primaryUrl = uploadedPrimary?.url ?? null;
      if (!primaryUrl) {
        skusSkippedUpload += 1;
        console.warn(`[photo0 skip] sku=${sku}: upload slot 0 failed`);
        continue;
      }
    } catch (err) {
      skusSkippedUpload += 1;
      console.warn(
        `[photo0 skip] sku=${sku}:`,
        err instanceof Error ? err.message : err,
      );
      continue;
    }

    skusUpdated += 1;
    for (const row of productRows) {
      const images = mergePrimaryPhotoIntoImages(primaryUrl, row.images);
      const { error: updateError } = await supabase
        .from('products')
        .update({
          image_url: primaryUrl,
          images,
        })
        .eq('id', row.id);
      if (updateError) {
        console.error(`[photo0] update id=${row.id} sku=${sku}:`, updateError.message);
      } else {
        productsUpdated += 1;
      }
    }

    if ((i + 1) % 25 === 0 || i + 1 === skus.length) {
      console.log(
        `[photo0] Прогресс sku: ${i + 1}/${skus.length}, ` +
          `products_updated=${productsUpdated}`,
      );
    }
  }

  console.log('---');
  console.log(
    `[photo0] Готово: skus_updated=${skusUpdated}, products_updated=${productsUpdated}, ` +
      `no_blob=${skusSkippedNoBlob}, upload_fail=${skusSkippedUpload}`,
  );
  return { skusUpdated, productsUpdated, skusSkippedNoBlob, skusSkippedUpload };
}

async function mainResyncPhoto0() {
  requireEnv();
  const allActive = process.argv.includes('--all-active');
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    realtime: { transport: ws },
  });

  let pool;
  try {
    pool = await runMssqlWithTimeout(
      'sql.connect',
      () => sql.connect(MSSQL_CONFIG),
      null,
      MSSQL_CONNECT_TIMEOUT_MS,
    );
    console.log('MSSQL DrJaw: connected (photo0 resync)');
    await resyncStalePrimaryPhotos(supabase, pool, { allActive });
  } finally {
    if (pool) {
      try {
        await pool.close();
      } catch (closeErr) {
        console.warn('MSSQL pool close:', closeErr);
      }
    }
  }
}

async function main() {
  requireEnv();
  await applyDropSkuUniqueConstraint();
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    realtime: { transport: ws },
  });

  const syncRequested = await fetchSyncTaskRequested(supabase);
  if (!syncRequested) {
    console.log('No sync requested. Exit.');
    process.exit(0);
  }

  console.log(`[sync_tasks] ${SYNC_TASK_ID}: sync_requested=true — starting import…`);

  let pool;
  let fatalError = null;
  let syncSucceeded = false;

  try {
    pool = await runMssqlWithTimeout(
      'sql.connect',
      () => sql.connect(MSSQL_CONFIG),
      null,
      MSSQL_CONNECT_TIMEOUT_MS,
    );
    console.log('MSSQL DrJaw: connected');

    console.log(
      `Загрузка позиций «В наличии» (DrJaw: ${IN_STOCK_STATUSES.join(' / ')})…`,
    );
    const allInStockRows = await fetchDrJawRows(pool);
    console.log(`MSSQL «В наличии» (Items ⨝ Articuls): ${allInStockRows.length} строк`);

    const rowsToProcess = allInStockRows;
    console.log(`[ПОЛНЫЙ SYNC] К обработке: ${rowsToProcess.length} позиций`);

    const stats = await syncProducts(supabase, pool, allInStockRows, rowsToProcess);

    const deleted = await cleanupRemovedFromMssql(
      supabase,
      stats.mssqlIds,
      stats.statusMap,
    );

    const ms = stats.mirrorStats;
    console.log('[sync:mirror] Базы синхронизированы один в один:');
    console.log(`- Всего в локальной базе MSSQL: ${ms?.mssqlTotal ?? stats.mssqlIds.size}`);
    console.log(
      `- Найдено изменений (буквы/фото/цены) для обновления: ${ms?.toUpdate ?? 0}`,
    );
    console.log(`- Новых товаров добавлено: ${ms?.toInsert ?? 0}`);
    console.log(`- Пропущено (уже идеально идентичны): ${ms?.skippedIdentical ?? 0}`);
    console.log(
      `- Перезалито обновленных фото (изменился размер файла): ${ms?.photosReuploadedDueToSize ?? 0}`,
    );
    console.log(`- Полностью удалено (проданные призраки): ${deleted}`);
    console.log('---');
    console.log(
      `Sync done: upserted=${stats.upserted}, skipped_protected=${stats.skippedProtected}, ` +
        `skipped_identical=${stats.mirrorStats?.skippedIdentical ?? 0}, ` +
        `row_errors=${stats.rowErrors ?? 0}, photos=${stats.photosUploaded}, deleted=${deleted}`,
    );
    console.log(
      `Переводы: уникальных в кэше=${stats.cacheSize}, API-вызовов (новых ключей)=${stats.translationApiCalls}`,
    );
    syncSucceeded = true;
  } catch (err) {
    fatalError = err;
    console.error('sync.js import fatal:', err);
  } finally {
    if (pool) {
      try {
        await pool.close();
      } catch (closeErr) {
        console.warn('MSSQL pool close:', closeErr);
      }
    }

    if (syncSucceeded) {
      try {
        await clearSyncTaskRequested(supabase);
        console.log(`[sync_tasks] ${SYNC_TASK_ID}: sync_requested=false (success)`);
      } catch (clearErr) {
        console.error(
          `[sync_tasks] не удалось сбросить sync_requested:`,
          clearErr instanceof Error ? clearErr.message : clearErr,
        );
      }
    } else {
      console.warn(
        `[sync_tasks] ${SYNC_TASK_ID}: import failed — sync_requested остаётся true для повторного cron`,
      );
    }
  }

  if (fatalError) {
    throw fatalError;
  }
}

const isPhoto0Resync = process.argv.includes('--resync-photo0');
const entry = isPhoto0Resync ? mainResyncPhoto0 : main;

entry().catch((err) => {
  console.error(isPhoto0Resync ? 'photo0 resync fatal:' : 'sync.js fatal:', err);
  process.exit(1);
});
