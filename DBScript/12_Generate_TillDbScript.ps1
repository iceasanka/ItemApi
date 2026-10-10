# Writes an EMPTY till database as a .sql script (works on SQL Server 2016 or newer, unlike a .bak from SQL 2022):
#   all tables (no data), zf_ table types, functions and procedures of PRASADA1.z_pos_fnt_db.
#   powershell -File 12_Generate_TillDbScript.ps1 -Out C:\Users\prasada\Desktop\fdrelease\z_pos_fnt_db_Create.sql
param([Parameter(Mandatory)][string]$Out, [string]$Server = "PRASADA1", [string]$Database = "z_pos_fnt_db")
$ErrorActionPreference = "Stop"
Add-Type -Path "C:\Program Files\Microsoft SQL Server\110\SDK\Assemblies\Microsoft.SqlServer.Smo.dll"

$srv = New-Object Microsoft.SqlServer.Management.Smo.Server $Server
$db = $srv.Databases[$Database]
if (-not $db) { throw "Database $Database not found on $Server" }
$sb = New-Object System.Text.StringBuilder
function W($s) { [void]$sb.AppendLine($s) }

W "/* ============================================================================="
W "   z_pos_fnt_db_Create.sql - generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') from $Server.$Database"
W "   EMPTY till database: tables, table types, functions, procedures. No data."
W "   On the till (SQL Server 2016 or newer, Express is fine), as admin:"
W "     sqlcmd -S .\SQLEXPRESS -E -C -Q ""CREATE DATABASE z_pos_fnt_db"""
W "     sqlcmd -S .\SQLEXPRESS -E -C -d z_pos_fnt_db -I -b -i z_pos_fnt_db_Create.sql"
W "   then EXEC dbo.zf_sp_SetupTerminal ... (see TillService README)."
W "   Stops without changing anything if the database already has tables."
W "   ============================================================================= */"
W "SET NOCOUNT ON;"
W "GO"
W "IF DB_NAME() IN ('master','model','msdb','tempdb') OR EXISTS (SELECT 1 FROM sys.tables)"
W "BEGIN"
W "    RAISERROR('Run this in an EMPTY z_pos_fnt_db (sqlcmd -d z_pos_fnt_db). Nothing was changed.', 16, 1);"
W "    SET NOEXEC ON;"
W "END"
W "GO"
W "BEGIN TRAN;"
W "GO"

# 1. tables with keys, defaults and indexes (foreign keys after all tables)
$o = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
$o.DriPrimaryKey = $true; $o.DriUniqueKeys = $true; $o.DriChecks = $true; $o.DriDefaults = $true; $o.DriIndexes = $true
$o.DriClustered = $true; $o.DriNonClustered = $true; $o.Indexes = $true; $o.Default = $true; $o.Triggers = $true
$o.AnsiPadding = $true; $o.NoCollation = $true; $o.SchemaQualify = $true; $o.IncludeHeaders = $false
$tables = @($db.Tables | Where-Object { -not $_.IsSystemObject } | Sort-Object Name)
foreach ($t in $tables) {
    W "-- ---- $($t.Name)"
    foreach ($line in $t.Script($o)) { W $line; W "GO" }
}
foreach ($t in $tables) {
    foreach ($fk in $t.ForeignKeys) { foreach ($line in $fk.Script()) { W $line; W "GO" } }
}

# 2. table types, then functions, then procedures
# no COLLATE: the types take the till db's collation, same as its tables (else "collation conflict" in the procs)
$to = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
$to.NoCollation = $true; $to.SchemaQualify = $true; $to.IncludeHeaders = $false
foreach ($tt in $db.UserDefinedTableTypes) {
    W "-- ---- type $($tt.Name)"
    foreach ($line in $tt.Script($to)) { W $line; W "GO" }
}
$mods = $db.ExecuteWithResults(@"
SELECT o.name, m.definition, m.uses_ansi_nulls, m.uses_quoted_identifier
FROM sys.objects o JOIN sys.sql_modules m ON m.object_id = o.object_id
WHERE o.is_ms_shipped = 0 AND o.type IN ('FN','IF','TF','V','P')
ORDER BY CASE o.type WHEN 'P' THEN 3 WHEN 'V' THEN 2 ELSE 1 END, o.name
"@)
foreach ($r in $mods.Tables[0].Rows) {
    W "-- ---- $($r.name)"
    W ("SET ANSI_NULLS " + $(if ($r.uses_ansi_nulls) { "ON" } else { "OFF" }))
    W ("SET QUOTED_IDENTIFIER " + $(if ($r.uses_quoted_identifier) { "ON" } else { "OFF" }))
    W "GO"
    W $r.definition.Trim()
    W "GO"
}

W "COMMIT;"
W "GO"
W "SET NOEXEC OFF;"
W "GO"
W "PRINT 'z_pos_fnt_db created (empty). Next: EXEC dbo.zf_sp_SetupTerminal ...';"
[IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object Text.UTF8Encoding $true))
"tables: $($tables.Count)  modules: $($mods.Tables[0].Rows.Count)"
