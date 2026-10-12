# SQL Server 2008 R2 conversion, shared by 11_Generate_ProdDeploy.ps1 (back office) and 13_Generate_TillDbFiles.ps1
# (till). Production easyway AND the tills run SQL Server 2008 R2: no THROW (SQL 2012+).
# Undo after the upgrade: Docs/SQL2008R2_Changes.md.
#
# Convert-For2008: a proc that THROWs or calls another z_sp_ / zf_sp_ gets its body in BEGIN TRY ... END CATCH and each
#   THROW n, 'msg', 1;   /   THROW n, @Msg, 1;
# becomes RAISERROR(N'%s', 16, 1, <msg>), which jumps to the CATCH like THROW does. The CATCH rolls the transaction back
# only in the outermost proc and raises the message again as error 50000 (ItemApi: Number >= 50000; TillService: 50000
# or 51000-51999 → 400 { message }).

$Sql2008TryStart = @"
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
"@
$Sql2008TryEnd = @"
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

function Convert-For2008([string]$def) {
    $needs = $def -match '\bTHROW\b' -or $def -match '\bEXEC\s+dbo\.zf?_sp_'
    if (-not $needs -or $def -notmatch '(?im)^\s*AS\s*\r?\n\s*BEGIN\b') { return $def }
    $def = [regex]::Replace($def, "THROW\s+\d+\s*,\s*('(?:[^']|'')*'|@\w+)\s*,\s*\d+\s*;", {
        param($m)
        $msg = $m.Groups[1].Value
        if ($msg.StartsWith("'")) { $msg = "N" + $msg }
        "RAISERROR(N'%s', 16, 1, $msg);"
    })
    $def = ([regex]'(?im)^\s*AS\s*\r?\n\s*BEGIN\b').Replace($def, $Sql2008TryStart.TrimEnd(), 1)
    $def = [regex]::Replace($def, '(?s)\bEND\s*;?\s*$', $Sql2008TryEnd.TrimEnd())
    return $def
}

# Throws when a definition still uses syntax SQL Server 2008 R2 can't run (comment lines are ignored).
function Assert-Sql2008([string]$name, [string]$def) {
    $code = ($def -split "`n" | Where-Object { $_ -notmatch '^\s*--' }) -join "`n"
    if ($code -match '(?i)\bTHROW\b|OFFSET\s+\S+\s+ROWS|\bIIF\s*\(|\bCHOOSE\s*\(|\bCONCAT\s*\(|\bFORMAT\s*\(|\bTRY_(CONVERT|CAST|PARSE)\b|\bEOMONTH\b|FROMPARTS\b|\bSTRING_(AGG|SPLIT)\b|\bOPENJSON\b|\bJSON_|NEXT VALUE FOR|\bLAG\s*\(|\bLEAD\s*\(|_VALUE\s*\(|CREATE OR ALTER|DROP\s+\w+\s+IF EXISTS|ALTER DATABASE CURRENT') {
        throw "${name}: uses SQL Server 2012+ syntax ($($Matches[0])) - production and tills are SQL Server 2008 R2"
    }
}
