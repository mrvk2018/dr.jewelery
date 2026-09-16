/**
 * Применяет 004_drop_products_sku_unique.sql через прямое подключение Postgres.
 * Env: SUPABASE_DB_URL (Settings → Database → Connection string → URI)
 */
require('dotenv').config();

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

async function main() {
  const dbUrl = process.env.SUPABASE_DB_URL || process.env.DATABASE_URL;
  if (!dbUrl) {
    console.error(
      'Задайте SUPABASE_DB_URL в .env (Database → Connection string → URI, postgres password).',
    );
    process.exit(1);
  }

  const sqlPath = path.join(
    __dirname,
    '..',
    'supabase',
    'migrations',
    '004_drop_products_sku_unique.sql',
  );
  const sqlText = fs.readFileSync(sqlPath, 'utf8');

  const client = new Client({
    connectionString: dbUrl,
    ssl: { rejectUnauthorized: false },
  });
  await client.connect();
  try {
    await client.query(sqlText);
    console.log('OK: products_sku_key dropped (if existed).');
  } finally {
    await client.end();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
