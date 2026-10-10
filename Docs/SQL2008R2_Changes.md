# SQL Server 2008 R2 changes — and how to undo them

Production `easyway` runs on **SQL Server 2008 R2 RTM** (10.50.1600, Windows Server 2012 / Windows 8).
It has no `THROW`, no `OFFSET … FETCH`, no `OPENJSON` and only TLS 1.0. These changes (2026-10-10) make the back
office work on it. Undo them after production moves to SQL Server 2016 or newer.

The **till** database (`z_pos_fnt_db`) is not part of this: tills need SQL Server 2016+ (item search uses STRING_SPLIT).

## 1. What was changed

| # | Where | Change | Why |
|---|---|---|---|
| 1 | `Program.cs` (AddDbContext, both contexts) | `UseSqlServer(conn, sql => sql.UseCompatibilityLevel(100))` | EF Core 8 must not generate SQL 2016+ (OPENJSON for `list.Contains`, …) |
| 2 | `Repositories/SalesDocRepository.cs` `SearchAsync` | `.Take(page * pageSize)` in SQL, then `.Skip((page - 1) * pageSize)` in memory (was `.Skip().Take()` in SQL) | `Skip` becomes `OFFSET … FETCH` (SQL 2012+) |
| 3 | `Repositories/StockLedgerRepository.cs` stock balance page | same as 2; also `.ThenBy(x => x.i.ItemId)` | same; ItemId keeps items with the same name in a fixed order between pages (keep this) |
| 4 | `DBScript/11_Generate_ProdDeploy.ps1` | `-Sql2008 $true` (default): every proc that THROWs or calls another `z_sp` gets its body in `BEGIN TRY … END CATCH`; each `THROW n, 'msg', 1;` becomes `RAISERROR(N'%s', 16, 1, N'msg');`. Refuses to write SQL 2012+ syntax | `THROW` is SQL 2012+ |
| 5 | `fdrelease\easyway_z_Deploy.sql` and `fdrelease\easyway_sp_2008\*.sql` | generated with change 4 | — |

Not changed: the procs in the dev database and in `DBScript/01…07` keep `THROW`. Only the generated production files
are converted.

### Behaviour of the converted procs (change 4)
- Error **number is 50000** for every business error (was 50001…50099). ItemApi only checks `ex.Number >= 50000`,
  so the API answers the same (400 + the same message).
- A SQL system error inside a converted proc (deadlock, FK violation, …) also comes back as **50000**, so the API shows
  it as a 400 message instead of a 500. With THROW it kept its own number.
- The outermost proc rolls the transaction back; a proc called inside another proc's transaction leaves the rollback
  to the caller (same result as THROW + XACT_ABORT).

## 2. Undo — after production runs SQL Server 2016 or newer

1. **Move the database.** Back up `easyway` on 2008 R2, restore it on the new server. Leave the compatibility level at
   100 until the old POS program (the `tb_*` tables) is tested; then `ALTER DATABASE easyway SET COMPATIBILITY_LEVEL = 130;`
   (or higher).
2. **Procs back to THROW.** Generate the files without the conversion and run them on the new server:
   ```
   powershell -File DBScript\11_Generate_ProdDeploy.ps1 -ProcDir C:\fdrelease\easyway_sp -Sql2008 $false
   C:\fdrelease\easyway_sp\run_all.cmd <new-server>
   ```
   Each file drops and re-creates its function / procedure; table data is not touched.
3. **`Program.cs`:** remove `, sql => sql.UseCompatibilityLevel(100)` from both `UseSqlServer` calls, or set it to the
   database's new compatibility level (130 = SQL 2016, 150 = 2019, 160 = 2022). Only do this after step 1's
   `ALTER DATABASE`: EF's `list.Contains` needs level 130+.
4. **Paging (optional).** Changes 2 and 3 also work on new SQL Servers. To page in SQL again, replace
   `.Take(page * pageSize)` … `.ToListAsync()).Skip((page - 1) * pageSize).ToList()` with
   `.Skip((page - 1) * pageSize).Take(pageSize)` … `.ToListAsync()` (search for "SQL Server 2008 R2" in the code).
5. **Generator default.** In `11_Generate_ProdDeploy.ps1` change `[bool]$Sql2008 = $true` to `$false` (or delete
   `Convert-For2008` and the 2012+ syntax check).
6. **Connection string.** `Encrypt=False` was only needed for TLS 1.0; on the new server use
   `Encrypt=True;TrustServerCertificate=True` (or a real certificate).

Find every place: search the code for `SQL Server 2008 R2`.
