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

(async () => {
  const pool = await sql.connect(MSSQL_CONFIG);
  const items = await pool
    .request()
    .input('sku', sql.NVarChar, sku)
    .query(`
      SELECT i.Id, i.Articul, i.Status, i.Price
      FROM Items AS i
      WHERE i.Articul = @sku
    `);
  console.log('Items:', JSON.stringify(items.recordset, null, 2));
  const inStock = await pool
    .request()
    .input('sku', sql.NVarChar, sku)
    .input('inStockEn', sql.NVarChar, 'InStock')
    .input('inStockRu', sql.NVarChar, 'В наличии')
    .query(`
      SELECT i.Id, i.Status
      FROM Items AS i
      INNER JOIN Articuls AS a ON i.Articul = a.Articul
      WHERE i.Articul = @sku AND i.Status IN (@inStockEn, @inStockRu)
    `);
  console.log('InStock (sync eligible):', JSON.stringify(inStock.recordset, null, 2));
  await pool.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
