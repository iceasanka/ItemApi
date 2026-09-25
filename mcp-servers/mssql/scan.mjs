import sql from "mssql";
const cs = "Server=PRASADA1;Database=easyway;User Id=ice;Password=ice@123;TrustServerCertificate=True";
const pool = await sql.connect(cs);

for (const t of ['z_tb_Item','z_tb_ItemDet','z_tb_User']) {
  console.log(`=== ${t} columns ===`);
  const r = await pool.request().query(`SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='${t}' ORDER BY ORDINAL_POSITION`);
  console.log(r.recordset.map(c => `${c.COLUMN_NAME} (${c.DATA_TYPE})`).join(", "));
}

console.log("=== Any table already using Loca_Code as a per-row column (legacy multi-location pattern) ===");
const r2 = await pool.request().query(`
  SELECT TABLE_NAME, COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
  WHERE COLUMN_NAME IN ('Loca_Code','LocaCode','BranchId','BranchCode')`);
console.log(r2.recordset);

await pool.close();
