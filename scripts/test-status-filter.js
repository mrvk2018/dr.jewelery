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
  const g = await p.request().query(`
    SELECT TOP 15 Status, COUNT(*) AS cnt
    FROM Items
    GROUP BY Status
    ORDER BY cnt DESC
  `);
  console.log('Status groups:', g.recordset);
  const exact = await p.request().query(`
    SELECT COUNT(*) AS n FROM Items WHERE Status = N'В наличии'
  `);
  console.log('exact В наличии:', exact.recordset[0]);
  const join = await p.request().query(`
    SELECT COUNT(*) AS n
    FROM Items i
    INNER JOIN Articuls a ON i.Articul = a.Articul
    WHERE i.Status = N'InStock'
  `);
  console.log('join InStock:', join.recordset[0]);
  await p.close();
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
