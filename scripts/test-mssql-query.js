require('dotenv').config();
const sql = require('mssql');

const c = {
  server: '211.176.43.226',
  port: 1433,
  user: 'DrJ_Reader',
  password: 'Read_only11!',
  database: 'DrJaw',
  options: { encrypt: false, trustServerCertificate: true },
};

(async () => {
  const p = await sql.connect(c);
  const r = await p.request().query('SELECT COUNT(*) AS n FROM Items');
  console.log('items count', r.recordset[0]);
  try {
    const r2 = await p.request().query(`
      SELECT TOP 1 i.Id, i.Articul, i.Mart, a.Type, a.Metall
      FROM Items AS i
      LEFT JOIN Articuls AS a ON a.Articul = i.Articul
    `);
    console.log('sample join ok', r2.recordset[0]);
  } catch (e) {
    console.error('join failed:', e.message);
  }
  await p.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
