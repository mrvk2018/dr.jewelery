require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const sql = require('mssql');

const MSSQL_CONFIG = {
  server: process.env.MSSQL_HOST || '211.176.43.226',
  port: Number(process.env.MSSQL_PORT || 1433),
  user: process.env.MSSQL_USER || 'DrJ_Reader',
  password: process.env.MSSQL_PASSWORD || 'Read_only11!',
  database: process.env.MSSQL_DATABASE || 'DrJaw',
  options: { encrypt: false, trustServerCertificate: true },
};

(async () => {
  const pool = await sql.connect(MSSQL_CONFIG);
  const cols = await pool.request().query(`
    SELECT COLUMN_NAME, DATA_TYPE
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Items'
    ORDER BY ORDINAL_POSITION
  `);
  console.log('Items columns:');
  for (const c of cols.recordset) console.log(`  ${c.COLUMN_NAME} (${c.DATA_TYPE})`);

  const tables = await pool.request().query(`
    SELECT TABLE_NAME
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'dbo'
      AND (
        TABLE_NAME LIKE '%Item%'
        OR TABLE_NAME LIKE '%Hist%'
        OR TABLE_NAME LIKE '%Log%'
        OR TABLE_NAME LIKE '%Sold%'
        OR TABLE_NAME LIKE '%Status%'
      )
    ORDER BY TABLE_NAME
  `);
  console.log('\nRelated tables:', tables.recordset.map((r) => r.TABLE_NAME).join(', '));

  const sku = process.argv[2] || '921-000004';
  const row = await pool
    .request()
    .input('sku', sql.NVarChar, sku)
    .query(`SELECT * FROM Items WHERE Articul = @sku`);
  console.log(`\nFull Items row for ${sku}:`);
  console.log(JSON.stringify(row.recordset[0] || null, (k, v) => {
    if (v instanceof Date) return v.toISOString();
    if (Buffer.isBuffer(v)) return `<Buffer ${v.length} bytes>`;
    return v;
  }, 2));

  await pool.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
