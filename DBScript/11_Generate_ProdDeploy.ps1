# -Out <file>      one script: tables + data + types + functions + procs (empty production easyway)
# -ProcDir <dir>   one file per function / procedure (DROP + CREATE), to run one by one on an existing easyway
# -Sql2008 $false  keep THROW as written (after production moves to SQL Server 2012+; see Docs/SQL2008R2_Changes.md)
param([string]$Out, [string]$ProcDir, [bool]$Sql2008 = $true)
if (-not $Out -and -not $ProcDir) { throw "Give -Out <file> and/or -ProcDir <folder>." }
$ErrorActionPreference = "Stop"
Add-Type -Path "C:\Program Files\Microsoft SQL Server\110\SDK\Assemblies\Microsoft.SqlServer.Smo.dll"

$keepData = @("z_tb_Location","z_tb_Role","z_tb_StockAdjReason","z_tb_SubCategory","z_tb_Supplier","z_tb_System",
              "z_tb_Terminal","z_tb_Unit","z_tb_User","z_tb_Customer","z_tb_Category",
              "z_tb_ExportSetting","z_tb_SalesDocCounter","z_tb_SalesDocSetting")
$empty    = @("z_tb_ExportLog","z_tb_Item","z_tb_ItemDet","z_tb_ItemPriceLink","z_tb_SalesInvoice",
              "z_tb_SalesInvoiceItem","z_tb_SalesPayment","z_tb_ScaleExportItem","z_tb_StockAdjustment",
              "z_tb_StockAdjustmentItem","z_tb_StockBalance","z_tb_StockLedger","z_tb_SupplierLedger","z_tb_TempPurchase",
              "z_tb_TempPurchaseSummary","z_tb_ZReport","z_tb_ZReportItem","z_tb_ItemOldCode","z_tb_SalesDoc","z_tb_SalesDocItem")
$all = $keepData + $empty

$srv = New-Object Microsoft.SqlServer.Management.Smo.Server "PRASADA1"
$db = $srv.Databases["easyway"]
$sb = New-Object System.Text.StringBuilder
function W($s) { [void]$sb.AppendLine($s) }

W "/* ============================================================================="
W "   easyway_z_Deploy.sql  - generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') from PRASADA1.easyway"
W "   Production deployment of the new back office: z_ tables, z_ functions and z_ procedures."
W "   Tables WITH data: $($keepData -join ', ')"
W "   Tables EMPTY:     $($empty -join ', ')"
W "   Run on the production easyway db:  sqlcmd -S <server> -d easyway -E -I -b -i easyway_z_Deploy.sql"
W "   Stops without changing anything if any of these tables already exists. Old tb_* tables are not touched."
W "   ============================================================================= */"
W "SET NOCOUNT ON;"
W "GO"
W ("IF EXISTS (SELECT 1 FROM sys.tables WHERE name IN ('" + ($all -join "','") + "'))")
W "   OR EXISTS (SELECT 1 FROM sys.types WHERE is_user_defined = 1 AND name LIKE 'z[_]tt[_]%')"
W "   OR EXISTS (SELECT 1 FROM sys.objects WHERE name LIKE 'z[_]%' AND type IN ('P','FN','IF','TF'))"
W "BEGIN"
W "    RAISERROR('z_ objects already exist in this database - nothing was changed.', 16, 1);"
W "    SET NOEXEC ON;"
W "END"
W "GO"
W "BEGIN TRAN;"
W "GO"

# 1. tables (no foreign keys yet)
$o = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
$o.DriPrimaryKey = $true; $o.DriUniqueKeys = $true; $o.DriChecks = $true; $o.DriDefaults = $true; $o.DriIndexes = $true; $o.DriClustered = $true; $o.DriNonClustered = $true; $o.Indexes = $true; $o.Default = $true; $o.Triggers = $true
$o.AnsiPadding = $true; $o.NoCollation = $true; $o.SchemaQualify = $true; $o.IncludeHeaders = $false
foreach ($n in $all) {
    $t = $db.Tables[$n, "dbo"]; if (-not $t) { throw "Table $n not found" }
    W "-- ---- $n"
    foreach ($line in $t.Script($o)) { W $line; W "GO" }
}

# 2. data
$d = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
$d.ScriptData = $true; $d.ScriptSchema = $false; $d.SchemaQualify = $true
$scr = New-Object Microsoft.SqlServer.Management.Smo.Scripter $srv
$scr.Options = $d
foreach ($n in $keepData) {
    W "-- ---- data: $n"
    foreach ($line in $scr.EnumScript([Microsoft.SqlServer.Management.Smo.SqlSmoObject[]]@($db.Tables[$n, "dbo"]))) { W $line }
    W "GO"
}

# 3. foreign keys between the deployed tables
foreach ($n in $all) {
    foreach ($fk in $db.Tables[$n, "dbo"].ForeignKeys) {
        if ($all -notcontains $fk.ReferencedTable) { throw "$n FK $($fk.Name) points at $($fk.ReferencedTable) (not deployed)" }
        foreach ($line in $fk.Script()) { W $line; W "GO" }
    }
}

# 4. table types the procedures take as parameters
foreach ($tt in $db.UserDefinedTableTypes) {
    if ($tt.Name -notlike "z_tt_*") { continue }
    W "-- ---- type $($tt.Name)"
    foreach ($line in $tt.Script()) { W $line; W "GO" }
}

# 5. functions first, then procedures (definition as stored)
$mods = $db.ExecuteWithResults(@"
SELECT o.name, o.type, m.definition, m.uses_ansi_nulls, m.uses_quoted_identifier
FROM sys.objects o JOIN sys.sql_modules m ON m.object_id = o.object_id
WHERE o.name LIKE 'z[_]%' AND o.type IN ('FN','IF','TF','P','V')
ORDER BY CASE WHEN o.type = 'P' THEN 2 ELSE 1 END, o.name
"@)
# Production easyway is SQL Server 2008 R2: no THROW. Procs that THROW or call another z_sp get their body in
# TRY/CATCH and each "THROW n, 'msg', 1;" becomes RAISERROR (jumps to CATCH like THROW). The CATCH rolls back the
# transaction only in the outermost proc and raises the message again (error 50000; ItemApi checks Number >= 50000).
$tryStart = @"
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
"@
$tryEnd = @"
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0
        BEGIN
            IF XACT_STATE() <> 0 ROLLBACK;
        END
        ELSE
        BEGIN
            -- called inside the caller's transaction: give its level back, the caller's CATCH rolls back
            WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT;
        END
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
"@
function Convert-For2008([string]$name, [string]$def) {
    $needs = $def -match '\bTHROW\b' -or $def -match '\bEXEC\s+dbo\.z_sp_'
    if (-not $needs -or $def -notmatch '(?im)^\s*AS\s*\r?\n\s*BEGIN\b') { return $def }
    $def = [regex]::Replace($def, "THROW\s+\d+\s*,\s*('(?:[^']|'')*')\s*,\s*\d+\s*;", 'RAISERROR(N''%s'', 16, 1, N$1);')
    $def = ([regex]'(?im)^\s*AS\s*\r?\n\s*BEGIN\b').Replace($def, $tryStart.TrimEnd(), 1)
    $def = [regex]::Replace($def, '(?s)\bEND\s*;?\s*$', $tryEnd.TrimEnd())
    return $def
}

$modFiles = @()
foreach ($r in $mods.Tables[0].Rows) {
    $def = $r.definition.Trim()
    if ($Sql2008) { $def = Convert-For2008 $r.name $def }
    # anything SQL Server 2008 R2 can't run must not reach the production script (comment lines are ignored)
    $code = ($def -split "`n" | Where-Object { $_ -notmatch '^\s*--' }) -join "`n"
    if ($Sql2008 -and $code -match '(?i)\bTHROW\b|OFFSET\s+\S+\s+ROWS|\bIIF\s*\(|\bCONCAT\s*\(|\bFORMAT\s*\(|\bTRY_(CONVERT|CAST|PARSE)\b|\bEOMONTH\b|FROMPARTS\b|\bSTRING_(AGG|SPLIT)\b|\bOPENJSON\b|\bJSON_|NEXT VALUE FOR|\bLAG\s*\(|\bLEAD\s*\(|_VALUE\s*\(|CREATE OR ALTER|DROP\s+\w+\s+IF EXISTS') {
        throw "$($r.name): uses SQL Server 2012+ syntax ($($Matches[0])) - production is SQL Server 2008 R2"
    }
    W "-- ---- $($r.name)"
    W ("SET ANSI_NULLS " + ($(if ($r.uses_ansi_nulls) { "ON" } else { "OFF" })))
    W ("SET QUOTED_IDENTIFIER " + ($(if ($r.uses_quoted_identifier) { "ON" } else { "OFF" })))
    W "GO"
    W $def
    W "GO"
    $modFiles += [pscustomobject]@{ Name = $r.name; Type = $r.type.Trim(); Def = $def;
                                    AnsiNulls = $r.uses_ansi_nulls; QuotedId = $r.uses_quoted_identifier }
}

W "COMMIT;"
W "GO"
W "SET NOEXEC OFF;"
W "GO"
W "PRINT 'easyway z_ deployment done.';"
if ($Out) {
    [IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object Text.UTF8Encoding $true))
    "script: $Out  modules: $($mods.Tables[0].Rows.Count)"
}

if ($ProcDir) {
    # order: functions, then the procs other procs call, then the rest - each file can also be run on its own
    $called = @("z_sp_PostStockMovements", "z_sp_PostPurchaseDoc", "z_sp_ReconcileZReport")
    $ordered = @($modFiles | Where-Object { $_.Type -ne "P" }) +
               @($called | ForEach-Object { $n = $_; $modFiles | Where-Object { $_.Name -eq $n } }) +
               @($modFiles | Where-Object { $_.Type -eq "P" -and $called -notcontains $_.Name })
    New-Item -ItemType Directory -Force -Path $ProcDir | Out-Null
    Get-ChildItem $ProcDir -Filter "*.sql" | Remove-Item
    $target = if ($Sql2008) { "SQL Server 2008 R2 version" } else { "SQL Server 2012+ version (THROW)" }
    $i = 0
    $runAll = New-Object System.Text.StringBuilder
    [void]$runAll.AppendLine("@echo off")
    [void]$runAll.AppendLine("rem Creates the z_tt_ table types, then every z_ function and procedure on easyway, in order;")
    [void]$runAll.AppendLine("rem stops at the first error.   run_all.cmd <server>   e.g. run_all.cmd .\SQLEXPRESS (Windows login)")
    [void]$runAll.AppendLine("if ""%~1""=="""" (echo Usage: run_all.cmd ^<server^> & exit /b 1)")

    # table types first (00_1_...): the procs take them as parameters. Created only when missing - a type in use by a
    # proc can't be dropped, and its shape only changes together with its procs.
    $o2 = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
    $o2.NoCollation = $true; $o2.SchemaQualify = $true; $o2.IncludeHeaders = $false
    $tn = 0
    foreach ($tt in ($db.UserDefinedTableTypes | Where-Object { $_.Name -like "z_tt_*" } | Sort-Object Name)) {
        $tn++
        $file = "00_{0}_{1}.sql" -f $tn, $tt.Name
        $create = (($tt.Script($o2) | ForEach-Object { $_ }) -join "`r`n").Trim()
        $t = New-Object System.Text.StringBuilder
        [void]$t.AppendLine("-- table type $($tt.Name) - generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') from PRASADA1.easyway")
        [void]$t.AppendLine("-- Run on easyway BEFORE the procedures (safe to run again: only creates it when missing):")
        [void]$t.AppendLine("--   sqlcmd -S <server> -d easyway -E -I -b -i $file")
        [void]$t.AppendLine("IF TYPE_ID(N'dbo.$($tt.Name)') IS NULL")
        [void]$t.AppendLine("BEGIN")
        [void]$t.AppendLine("    EXEC (N'" + $create.Replace("'", "''") + "');")
        [void]$t.AppendLine("    PRINT '$($tt.Name) created.';")
        [void]$t.AppendLine("END")
        [void]$t.AppendLine("ELSE")
        [void]$t.AppendLine("    PRINT '$($tt.Name) already exists - not changed.';")
        [void]$t.AppendLine("GO")
        [IO.File]::WriteAllText((Join-Path $ProcDir $file), $t.ToString(), (New-Object Text.UTF8Encoding $true))
        [void]$runAll.AppendLine("sqlcmd -S %1 -d easyway -E -I -b -i ""%~dp0$file"" || (echo FAILED: $file & exit /b 1)")
    }
    foreach ($m in $ordered) {
        $i++
        $file = "{0:D2}_{1}.sql" -f $i, $m.Name
        $kind = if ($m.Type -eq "P") { "PROCEDURE" } else { "FUNCTION" }
        $t = New-Object System.Text.StringBuilder
        [void]$t.AppendLine("-- $($m.Name) - $target, generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') from PRASADA1.easyway")
        [void]$t.AppendLine("-- Run on easyway (safe to run again: drops and creates):")
        [void]$t.AppendLine("--   sqlcmd -S <server> -d easyway -E -I -b -i $file")
        [void]$t.AppendLine("SET ANSI_NULLS " + $(if ($m.AnsiNulls) { "ON" } else { "OFF" }))
        [void]$t.AppendLine("SET QUOTED_IDENTIFIER " + $(if ($m.QuotedId) { "ON" } else { "OFF" }))
        [void]$t.AppendLine("GO")
        [void]$t.AppendLine("IF OBJECT_ID(N'dbo.$($m.Name)') IS NOT NULL DROP $kind dbo.$($m.Name);")
        [void]$t.AppendLine("GO")
        [void]$t.AppendLine($m.Def)
        [void]$t.AppendLine("GO")
        [void]$t.AppendLine("PRINT '$($m.Name) created.';")
        [IO.File]::WriteAllText((Join-Path $ProcDir $file), $t.ToString(), (New-Object Text.UTF8Encoding $true))
        [void]$runAll.AppendLine("sqlcmd -S %1 -d easyway -E -I -b -i ""%~dp0$file"" || (echo FAILED: $file & exit /b 1)")
    }
    [void]$runAll.AppendLine("echo All $i functions and procedures created.")
    [IO.File]::WriteAllText((Join-Path $ProcDir "run_all.cmd"), $runAll.ToString(), (New-Object Text.ASCIIEncoding))
    "files: $i in $ProcDir"
}




