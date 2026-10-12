# Writes the till database (z_pos_fnt_db) as ONE FILE PER OBJECT, to run one by one on a till's empty z_pos_fnt_db:
#   00_check_server.sql   right database, SQL Server 2008 or newer
#   1xx_<table>.sql       tables with keys, indexes, defaults - created only when missing
#   2xx_<type>.sql        zf_tt_ table types                  - created only when missing
#   3xx_<function>.sql    functions                           - drop + create
#   4xx_<procedure>.sql   procedures                          - drop + create
#   900_setup_terminal.sql  THIS till's number / code / back office address (edit before running)
#   run_all.cmd <server>  runs 00 .. 4xx in order, stops at the first error
# No data: items, prices, stock and cashiers come down from the back office on the first sync.
#   powershell -File 13_Generate_TillDbFiles.ps1 -Dir C:\Users\prasada\Desktop\fdrelease\z_pos_fnt_db_files
# -Sql2008 $false  keep THROW as written (once the tills run SQL Server 2012+; see Docs/SQL2008R2_Changes.md)
param([Parameter(Mandatory)][string]$Dir, [string]$Server = "PRASADA1", [string]$Database = "z_pos_fnt_db",
      [bool]$Sql2008 = $true)
$ErrorActionPreference = "Stop"
Add-Type -Path "C:\Program Files\Microsoft SQL Server\110\SDK\Assemblies\Microsoft.SqlServer.Smo.dll"
. (Join-Path $PSScriptRoot "Sql2008.ps1")   # Convert-For2008, Assert-Sql2008

$srv = New-Object Microsoft.SqlServer.Management.Smo.Server $Server
$db = $srv.Databases[$Database]
if (-not $db) { throw "Database $Database not found on $Server" }
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
$utf8 = New-Object Text.UTF8Encoding $true

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Get-ChildItem $Dir -Include *.sql, *.cmd -File -Recurse | Remove-Item

$runAll = New-Object System.Text.StringBuilder
[void]$runAll.AppendLine("@echo off")
[void]$runAll.AppendLine("rem Creates the till database objects in z_pos_fnt_db, in order; stops at the first error.")
[void]$runAll.AppendLine("rem   run_all.cmd <server>     e.g. run_all.cmd .\SQLEXPRESS   (Windows login; add -C to sqlcmd if it asks)")
[void]$runAll.AppendLine("rem Then edit and run 900_setup_terminal.sql.")
[void]$runAll.AppendLine("if ""%~1""=="""" (echo Usage: run_all.cmd ^<server^> & exit /b 1)")

function Save([string]$file, [string]$text, [bool]$inRunAll = $true) {
    [IO.File]::WriteAllText((Join-Path $Dir $file), $text, $utf8)
    if ($inRunAll) {
        [void]$runAll.AppendLine("sqlcmd -S %1 -d z_pos_fnt_db -E -I -b -i ""%~dp0$file"" || (echo FAILED: $file & exit /b 1)")
    }
}
function Header([string]$what, [string]$file, [string]$note) {
    "-- $what - generated $stamp from $Server.$Database`r`n" +
    "-- Run on the till's z_pos_fnt_db ($note):`r`n" +
    "--   sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i $file`r`n"
}

# ---- 00: server check ----
Save "00_check_server.sql" ((Header "server check" "00_check_server.sql" "first") + @"
-- These files are written for SQL Server 2008 R2 and newer (no THROW / STRING_SPLIT), compatibility level 100+.
DECLARE @db SYSNAME; SET @db = DB_NAME();
IF @db <> N'z_pos_fnt_db'
    RAISERROR('Select the z_pos_fnt_db database first (now: %s).', 16, 1, @db);
GO
DECLARE @major INT, @level INT;
SET @major = CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 4) AS INT);
SELECT @level = compatibility_level FROM sys.databases WHERE name = DB_NAME();
PRINT 'SQL Server major version ' + CAST(@major AS VARCHAR(5)) + ', compatibility level ' + CAST(@level AS VARCHAR(5));
IF @major < 10
    RAISERROR('This SQL Server is older than 2008 - the till needs SQL Server 2008 or newer.', 16, 1);
ELSE IF @level < 100
BEGIN
    EXEC (N'ALTER DATABASE [' + DB_NAME() + N'] SET COMPATIBILITY_LEVEL = 100');
    PRINT 'Compatibility level raised to 100.';
END
ELSE
    PRINT 'OK.';
GO
"@)

# ---- 1xx: tables ----
$o = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
$o.DriPrimaryKey = $true; $o.DriUniqueKeys = $true; $o.DriChecks = $true; $o.DriDefaults = $true; $o.DriIndexes = $true
$o.DriClustered = $true; $o.DriNonClustered = $true; $o.Indexes = $true; $o.Default = $true; $o.Triggers = $true
$o.AnsiPadding = $true; $o.NoCollation = $true; $o.SchemaQualify = $true; $o.IncludeHeaders = $false
$n = 100
foreach ($t in ($db.Tables | Where-Object { -not $_.IsSystemObject } | Sort-Object Name)) {
    $n++
    $file = "{0}_{1}.sql" -f $n, $t.Name
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append((Header "table $($t.Name)" $file "safe to run again: skipped when the table exists"))
    [void]$sb.AppendLine("IF OBJECT_ID(N'dbo.$($t.Name)', N'U') IS NOT NULL")
    [void]$sb.AppendLine("BEGIN")
    [void]$sb.AppendLine("    PRINT '$($t.Name) already exists - not changed.';")
    [void]$sb.AppendLine("    SET NOEXEC ON;")
    [void]$sb.AppendLine("END")
    [void]$sb.AppendLine("GO")
    foreach ($line in $t.Script($o)) { [void]$sb.AppendLine($line); [void]$sb.AppendLine("GO") }
    foreach ($fk in $t.ForeignKeys) { foreach ($line in $fk.Script()) { [void]$sb.AppendLine($line); [void]$sb.AppendLine("GO") } }
    [void]$sb.AppendLine("PRINT '$($t.Name) created.';")
    [void]$sb.AppendLine("GO")
    [void]$sb.AppendLine("SET NOEXEC OFF;")
    [void]$sb.AppendLine("GO")
    Save $file $sb.ToString()
}

# ---- 2xx: table types (no COLLATE: they take the till db's collation, same as its tables) ----
$to = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
$to.NoCollation = $true; $to.SchemaQualify = $true; $to.IncludeHeaders = $false
$n = 200
foreach ($tt in ($db.UserDefinedTableTypes | Sort-Object Name)) {
    $n++
    $file = "{0}_{1}.sql" -f $n, $tt.Name
    $create = (($tt.Script($to) | ForEach-Object { $_ }) -join "`r`n").Trim()
    Save $file ((Header "table type $($tt.Name)" $file "before the functions and procedures; skipped when it exists") +
        "IF TYPE_ID(N'dbo.$($tt.Name)') IS NULL`r`nBEGIN`r`n    EXEC (N'" + $create.Replace("'", "''") + "');`r`n" +
        "    PRINT '$($tt.Name) created.';`r`nEND`r`nELSE`r`n    PRINT '$($tt.Name) already exists - not changed.';`r`nGO`r`n")
}

# ---- 3xx functions, 4xx procedures: drop + create ----
$mods = $db.ExecuteWithResults(@"
SELECT o.name, o.type, m.definition, m.uses_ansi_nulls, m.uses_quoted_identifier
FROM sys.objects o JOIN sys.sql_modules m ON m.object_id = o.object_id
WHERE o.is_ms_shipped = 0 AND o.type IN ('FN','IF','TF','P','V')
ORDER BY o.name
"@).Tables[0].Rows
$fn = 300; $pn = 400
foreach ($r in $mods) {
    $isProc = $r.type.Trim() -eq "P"
    if ($isProc) { $pn++; $num = $pn; $kind = "PROCEDURE" } else { $fn++; $num = $fn; $kind = if ($r.type.Trim() -eq "V") { "VIEW" } else { "FUNCTION" } }
    $file = "{0}_{1}.sql" -f $num, $r.name
    $def = $r.definition.Trim()
    if ($Sql2008) { $def = Convert-For2008 $def; Assert-Sql2008 $r.name $def }
    Save $file ((Header "$($kind.ToLower()) $($r.name)" $file "safe to run again: drops and creates") +
        "SET ANSI_NULLS " + $(if ($r.uses_ansi_nulls) { "ON" } else { "OFF" }) + "`r`n" +
        "SET QUOTED_IDENTIFIER " + $(if ($r.uses_quoted_identifier) { "ON" } else { "OFF" }) + "`r`nGO`r`n" +
        "IF OBJECT_ID(N'dbo.$($r.name)') IS NOT NULL DROP $kind dbo.$($r.name);`r`nGO`r`n" +
        $def + "`r`nGO`r`nPRINT '$($r.name) created.';`r`nGO`r`n")
}

# ---- 900: this till's setup row (the only data a till needs) - not in run_all ----
Save "900_setup_terminal.sql" ((Header "this till's setup" "900_setup_terminal.sql" "LAST, after editing the values") + @"
-- Each till needs its OWN TerminalId and TerminalCode. Register the same ones on the back office first
-- (POST api/Sync/Terminal). ApiBaseUrl = the back office ItemApi address as seen from this till (IP, not localhost).
EXEC dbo.zf_sp_SetupTerminal
    @TerminalId   = 2,                              -- <-- change: this till's number
    @TerminalCode = 'T02',                          -- <-- change: this till's code (max 10 characters)
    @LocationId   = 1,                              -- <-- change if the shop is another location
    @ApiBaseUrl   = 'http://192.168.1.5:5000/api/'; -- <-- change: back office address
SELECT TerminalId, TerminalCode, LocationId, ApiBaseUrl FROM dbo.zf_tb_Config;
GO
"@) $false

[void]$runAll.AppendLine("echo All objects created. Now edit and run 900_setup_terminal.sql.")
[IO.File]::WriteAllText((Join-Path $Dir "run_all.cmd"), $runAll.ToString(), (New-Object Text.ASCIIEncoding))
"files written to $Dir"
Get-ChildItem $Dir | Measure-Object | ForEach-Object { "count: $($_.Count)" }
