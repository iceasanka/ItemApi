/* =============================================================================
   18_Till_ResetCopiedDb.sql   (2026-10-16)
   Run on: a NEW till PC whose till database (z_pos_fnt_db) was RESTORED from another till's backup.
   As an administrator of that SQL Server (sqlcmd -E). SQL Server 2008 R2 and newer.

   A restored copy still is the OTHER till (e.g. T01): its terminal, bill counter, bills, Z reports, suspended
   bills, drawer log and cash in / out. This makes the copy a new, empty till:
     - deletes that till's own records:  zf_tb_Invoice, zf_tb_InvoiceItem, zf_tb_InvoicePayment,
       zf_tb_SuspendedBill(Item), zf_tb_ZReport(Item), zf_tb_DrawerLog, zf_tb_CashMovement
       (identities start again: first suspended bill #1, first Z = Z 1, first bill <code>-00000001)
     - sets the new terminal (zf_sp_SetupTerminal) - same LocationId and back office ApiBaseUrl as the copy
     - KEEPS the shared data: items, price links, stock, cashiers and the last sync times (the next sync only
       brings what changed since the backup)
   The other till's bills are not lost: that till still has them, and sent them to the back office itself.

   Register the new terminal on the back office first (POST api/Sync/Terminal, e.g. 2 / T02).
   Safety: ThisPc must be THIS computer's name (so it never runs on the till the backup came from); nothing else
   may be connected to the database (stop TillService); without Confirm=YES it only shows what it would do.

   HOW TO RUN (SSMS): connect to the new till's server, open this file, Query menu -> SQLCMD Mode, F5.
     The values are in the :setvar lines just below - set for till 2 (PC SPOS2, terminal 2 / T02).
     First run with Confirm "NO" (only shows what it would do), then change it to "YES" and F5 again.
     For another till change ThisPc / TerminalId / TerminalCode (this PC's name: run  hostname  in cmd).
     From cmd the :setvar lines below win over -v, so edit them there too:
       sqlcmd -S SPOS2 -E -b -i 18_Till_ResetCopiedDb.sql
   Then link the login (ALTER USER [ice] WITH LOGIN = [ice], or 17_Till_SqlLogin.sql) and start TillService.
   ============================================================================= */
:setvar ThisPc "SPOS2"
:setvar TerminalId 2
:setvar TerminalCode "T02"
:setvar Confirm "NO"
:setvar DbName "z_pos_fnt_db"
USE [$(DbName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_Config', 'U') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_Config not found) - use -d z_pos_fnt_db. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF UPPER(CAST(SERVERPROPERTY('MachineName') AS NVARCHAR(128))) <> UPPER(N'$(ThisPc)')
BEGIN
    DECLARE @msg NVARCHAR(400);
    SET @msg = N'This computer is ' + CAST(SERVERPROPERTY('MachineName') AS NVARCHAR(128)) + N', not $(ThisPc). '
             + N'Run it on the NEW till PC and give its name as ThisPc. Nothing was changed.';
    RAISERROR(@msg, 16, 1);
    SET NOEXEC ON;
END
GO
-- user connections only (SQL Server's own background sessions do not count)
IF EXISTS (SELECT 1 FROM sys.dm_tran_locks l
           JOIN sys.dm_exec_sessions s ON s.session_id = l.request_session_id AND s.is_user_process = 1
           WHERE l.resource_database_id = DB_ID() AND l.request_session_id <> @@SPID)
BEGIN
    RAISERROR('Something else is connected to this database (TillService? SSMS?) - stop TillService and close other windows. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Config WHERE Id = 1)
BEGIN
    RAISERROR('zf_tb_Config is empty - this database was never set up as a till. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- What is there now
SELECT 'now' AS [Till], TerminalId, TerminalCode, LocationId, ApiBaseUrl, LastInvoiceSeq FROM dbo.zf_tb_Config;
SELECT 'Bills' AS [Records of the copied till], COUNT(*) AS [Rows] FROM dbo.zf_tb_Invoice
UNION ALL SELECT 'Bill lines', COUNT(*) FROM dbo.zf_tb_InvoiceItem
UNION ALL SELECT 'Bill payments', COUNT(*) FROM dbo.zf_tb_InvoicePayment
UNION ALL SELECT 'Suspended bills', COUNT(*) FROM dbo.zf_tb_SuspendedBill
UNION ALL SELECT 'Suspended bill lines', COUNT(*) FROM dbo.zf_tb_SuspendedBillItem
UNION ALL SELECT 'Z reports', COUNT(*) FROM dbo.zf_tb_ZReport
UNION ALL SELECT 'Z report lines', COUNT(*) FROM dbo.zf_tb_ZReportItem
UNION ALL SELECT 'Drawer log', COUNT(*) FROM dbo.zf_tb_DrawerLog
UNION ALL SELECT 'Cash in / out', COUNT(*) FROM dbo.zf_tb_CashMovement;
SELECT 'Kept' AS [Shared data], (SELECT COUNT(*) FROM dbo.zf_tb_Item) AS Items,
       (SELECT COUNT(*) FROM dbo.zf_tb_ItemPriceLink) AS PriceLinks,
       (SELECT COUNT(*) FROM dbo.zf_tb_StockBalance) AS StockRows,
       (SELECT COUNT(*) FROM dbo.zf_tb_Cashier) AS Cashiers;
GO

IF EXISTS (SELECT 1 FROM dbo.zf_tb_Config WHERE TerminalId = $(TerminalId) AND TerminalCode = N'$(TerminalCode)')
   AND EXISTS (SELECT 1 FROM dbo.zf_tb_Invoice WHERE InvoiceNo LIKE N'$(TerminalCode)-%')
BEGIN
    RAISERROR('This database is already $(TerminalCode) and has $(TerminalCode) bills - it is a working till, not a fresh copy. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF UPPER(N'$(Confirm)') <> N'YES'
BEGIN
    PRINT '';
    PRINT 'Nothing was changed. The rows above would be DELETED and the till set to $(TerminalId) / $(TerminalCode).';
    PRINT 'Run again with Confirm="YES" to do it.';
    SET NOEXEC ON;
END
GO

DECLARE @LocationId INT, @ApiBaseUrl VARCHAR(200), @Old VARCHAR(10);
SELECT @LocationId = LocationId, @ApiBaseUrl = ApiBaseUrl, @Old = TerminalCode FROM dbo.zf_tb_Config WHERE Id = 1;
BEGIN TRY
    BEGIN TRANSACTION;
    TRUNCATE TABLE dbo.zf_tb_InvoicePayment;
    TRUNCATE TABLE dbo.zf_tb_InvoiceItem;
    TRUNCATE TABLE dbo.zf_tb_Invoice;
    TRUNCATE TABLE dbo.zf_tb_SuspendedBillItem;
    TRUNCATE TABLE dbo.zf_tb_SuspendedBill;
    TRUNCATE TABLE dbo.zf_tb_ZReportItem;
    TRUNCATE TABLE dbo.zf_tb_ZReport;
    TRUNCATE TABLE dbo.zf_tb_DrawerLog;
    TRUNCATE TABLE dbo.zf_tb_CashMovement;
    UPDATE dbo.zf_tb_Config SET LastInvoiceSeq = 0 WHERE Id = 1;
    EXEC dbo.zf_sp_SetupTerminal $(TerminalId), '$(TerminalCode)', @LocationId, @ApiBaseUrl;
    COMMIT TRANSACTION;
    PRINT 'Done: the copy of ' + @Old + ' is now an empty till $(TerminalCode) (terminal $(TerminalId)).';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @err NVARCHAR(2048);
    SET @err = N'Nothing was changed: ' + ERROR_MESSAGE();
    RAISERROR(@err, 16, 1);
END CATCH
GO
SELECT 'after' AS [Till], TerminalId, TerminalCode, LocationId, ApiBaseUrl, LastInvoiceSeq FROM dbo.zf_tb_Config;
GO
SET NOEXEC OFF;
GO
