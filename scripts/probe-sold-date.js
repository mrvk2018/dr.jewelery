require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const sql = require('mssql');

const sku = process.argv[2] || '921-000004';

const MSSQL_CONFIG = {
  server: process.env.MSSQL_HOST || '211.176.43.226',
  port: Number(process.env.MSSQL_PORT || 1433),
  user: process.env.MSSQL_USER || 'DrJ_Reader',
  password: process.env.MSSQL_PASSWORD || 'Read_only11!',
  database: process.env.MSSQL_DATABASE || 'DrJaw',
  options: { encrypt: false, trustServerCertificate: true },
};

function parseCartIdTimestamp(cartId) {
  if (!cartId || typeof cartId !== 'string') return null;
  const m = cartId.match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/);
  if (!m) return null;
  const [, y, mo, d, h, mi, s] = m;
  const storeSuffix = cartId.slice(14);
  return {
    isoLocal: `${y}-${mo}-${d}T${h}:${mi}:${s}`,
    store: storeSuffix || null,
  };
}

(async () => {
  const pool = await sql.connect(MSSQL_CONFIG);
  const allTables = await pool.request().query(`
    SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'dbo' ORDER BY TABLE_NAME
  `);
  console.log('All dbo tables:', allTables.recordset.map((r) => r.TABLE_NAME).join(', '));

  const item = await pool
    .request()
    .input('sku', sql.NVarChar, sku)
    .query(`
      SELECT Id, Articul, Status, CartId, Mart, Manager, Price
      FROM Items WHERE Articul = @sku
    `);
  const row = item.recordset[0];
  console.log('\nItems:', JSON.stringify(row, null, 2));
  if (row?.CartId) {
    console.log('\nCartId parsed:', parseCartIdTimestamp(row.CartId));
  }

  const byCart = row?.CartId
    ? await pool
        .request()
        .input('cartId', sql.NVarChar, row.CartId)
        .query(`SELECT Id, Articul, Status FROM Items WHERE CartId = @cartId ORDER BY Id`)
    : null;
  if (byCart?.recordset?.length) {
    console.log('\nOther Items in same CartId:', JSON.stringify(byCart.recordset, null, 2));
  }

  await pool.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
