/* =============================================================================
   U032_Till_PayRequests.sql   (2026-10-29)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Bills, Z reports and logs are not changed (one new, empty table). Needs U018 (cash movement
   upload).

   What changes (supplier bills paid in cash from a till, Docs/StockSystem.md 6.32):
     - table zf_tb_PayRequest: the supplier payments the back office asked this till to pay (downloaded, replaced
       every time); paid = a Paid Out made for it, sent up so the back office books the PAYMENT on the supplier ledger
     - types zf_tt_PayRequest, zf_tt_PayRequestId
     - procedures zf_sp_SavePayRequests (download), zf_sp_GetPayRequests (billing page), zf_sp_PayPayRequest (the
       Paid Out + the request paid, one transaction), zf_sp_GetUnsyncedPayRequests / zf_sp_MarkPayRequestsSynced
   Same change in the full script: 02_FrontCashier_zf.sql.

   Order: U032_BackOffice_TillPayments.sql + the new ItemApi first, then on each till:
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U032_Till_PayRequests.sql
     2. install the new TillService and the new billing page (the old ones keep working after the script)
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_InvoiceItem', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_tb_ZReport', 'U') IS NULL
   OR OBJECT_ID(N'dbo.zf_tb_Config', 'U') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_InvoiceItem / zf_tb_ZReport / zf_tb_Config not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF COL_LENGTH('dbo.zf_tb_CashMovement', 'Synced') IS NULL OR OBJECT_ID(N'dbo.zf_sp_AddCashMovement', 'P') IS NULL
BEGIN
    RAISERROR('Run U018_Till_CashMovementUpload.sql first - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. table
-- The till's copy of the supplier payments the back office asked it to pay (z_tb_TillPayRequest, waiting, for this
-- till or any till), replaced on every download. Paid = a Paid Out (zf_tb_CashMovement Kind 3) was made for it;
-- sent up (POST api/Sync/TillPayRequests), the back office books the PAYMENT on the supplier's ledger.
IF OBJECT_ID(N'dbo.zf_tb_PayRequest', 'U') IS NULL
CREATE TABLE dbo.zf_tb_PayRequest (
    RequestId    INT            NOT NULL CONSTRAINT PK_zf_tb_PayRequest PRIMARY KEY,   -- z_tb_TillPayRequest.RequestId
    SuppName     NVARCHAR(200)  NULL,
    Amount       DECIMAL(18,2)  NOT NULL,
    Remark       NVARCHAR(100)  NOT NULL,      -- the paid out reason
    CreatedAt    DATETIME       NULL,          -- back office time it was made
    Status       INT            NOT NULL CONSTRAINT DF_zf_tb_PayRequest_Status DEFAULT (0),   -- 0 waiting, 1 paid here
    MoveId       INT            NULL,          -- the paid out
    PaidAt       DATETIME       NULL,
    CashierId    VARCHAR(20)    NULL,
    Synced       BIT            NOT NULL CONSTRAINT DF_zf_tb_PayRequest_Synced DEFAULT (0),
    DownloadedAt DATETIME       NOT NULL CONSTRAINT DF_zf_tb_PayRequest_DownloadedAt DEFAULT (GETDATE())
);
GO

-- 2. types (dropped with their procs)
IF OBJECT_ID(N'dbo.zf_sp_SavePayRequests', 'P')        IS NOT NULL DROP PROCEDURE dbo.zf_sp_SavePayRequests;
IF OBJECT_ID(N'dbo.zf_sp_GetPayRequests', 'P')         IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetPayRequests;
IF OBJECT_ID(N'dbo.zf_sp_PayPayRequest', 'P')          IS NOT NULL DROP PROCEDURE dbo.zf_sp_PayPayRequest;
IF OBJECT_ID(N'dbo.zf_sp_GetUnsyncedPayRequests', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetUnsyncedPayRequests;
IF OBJECT_ID(N'dbo.zf_sp_MarkPayRequestsSynced', 'P')  IS NOT NULL DROP PROCEDURE dbo.zf_sp_MarkPayRequestsSynced;
GO
IF TYPE_ID(N'dbo.zf_tt_PayRequest') IS NOT NULL DROP TYPE dbo.zf_tt_PayRequest;
IF TYPE_ID(N'dbo.zf_tt_PayRequestId') IS NOT NULL DROP TYPE dbo.zf_tt_PayRequestId;
GO
CREATE TYPE dbo.zf_tt_PayRequest AS TABLE (
    RequestId INT           NOT NULL PRIMARY KEY,
    SuppName  NVARCHAR(200) NULL,
    Amount    DECIMAL(18,2) NOT NULL,
    Remark    NVARCHAR(100) NOT NULL,
    CreatedAt DATETIME      NULL
);
GO
CREATE TYPE dbo.zf_tt_PayRequestId AS TABLE (
    RequestId INT NOT NULL PRIMARY KEY
);
GO

-- 3. procedures
-- The downloaded list (the waiting ones of the back office): new ones come in, a waiting one no longer in the list
-- (taken back, or paid at another till) goes. One paid here stays until it is sent up.
CREATE PROCEDURE dbo.zf_sp_SavePayRequests
    @Rows dbo.zf_tt_PayRequest READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRAN;
        DELETE p FROM dbo.zf_tb_PayRequest p
        WHERE p.Status = 0 AND NOT EXISTS (SELECT 1 FROM @Rows r WHERE r.RequestId = p.RequestId);
        UPDATE p SET SuppName = r.SuppName, Amount = r.Amount, Remark = r.Remark, CreatedAt = r.CreatedAt
        FROM dbo.zf_tb_PayRequest p JOIN @Rows r ON r.RequestId = p.RequestId
        WHERE p.Status = 0;
        INSERT dbo.zf_tb_PayRequest (RequestId, SuppName, Amount, Remark, CreatedAt)
        SELECT r.RequestId, r.SuppName, r.Amount, r.Remark, r.CreatedAt FROM @Rows r
        WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_PayRequest p WHERE p.RequestId = r.RequestId);
    COMMIT;
END
GO

-- To pay now (the billing page's "Supplier payments").
CREATE PROCEDURE dbo.zf_sp_GetPayRequests
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RequestId, SuppName, Amount, Remark, CreatedAt FROM dbo.zf_tb_PayRequest WHERE Status = 0 ORDER BY RequestId;
END
GO

-- Pays a request: a Paid Out of its amount and reason (zf_sp_AddCashMovement - the drawer check, the open Z) and the
-- request marked paid, in one transaction. Returns the paid out like zf_sp_AddCashMovement.
CREATE PROCEDURE dbo.zf_sp_PayPayRequest
    @RequestId INT,
    @CashierId VARCHAR(20) = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Amount DECIMAL(18,2), @Remark NVARCHAR(100);
    DECLARE @m TABLE (MoveId INT, ZNo INT, Kind INT, Amount DECIMAL(18,2), Reason NVARCHAR(100), CashierId VARCHAR(20), CreatedAt DATETIME);

    BEGIN TRAN;
        SELECT @Amount = Amount, @Remark = Remark FROM dbo.zf_tb_PayRequest WITH (UPDLOCK, HOLDLOCK)
        WHERE RequestId = @RequestId AND Status = 0;
        IF @Amount IS NULL RAISERROR(N'%s', 16, 1, N'This supplier payment is already paid, or the back office took it back.');

        INSERT @m EXEC dbo.zf_sp_AddCashMovement @Kind = 3, @Amount = @Amount, @Reason = @Remark, @CashierId = @CashierId;

        UPDATE p SET Status = 1, MoveId = m.MoveId, PaidAt = m.CreatedAt, CashierId = @CashierId, Synced = 0
        FROM dbo.zf_tb_PayRequest p CROSS JOIN @m m
        WHERE p.RequestId = @RequestId;
    COMMIT;
    SELECT MoveId, ZNo, Kind, Amount, Reason, CashierId, CreatedAt FROM @m;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0 BEGIN IF XACT_STATE() <> 0 ROLLBACK; END
        ELSE BEGIN WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT; END
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

-- Paid here, not sent up yet - the body of POST api/Sync/TillPayRequests.
CREATE PROCEDURE dbo.zf_sp_GetUnsyncedPayRequests
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.RequestId, p.MoveId, m.ZNo, m.Amount, p.CashierId, p.PaidAt
    FROM dbo.zf_tb_PayRequest p
    JOIN dbo.zf_tb_CashMovement m ON m.MoveId = p.MoveId
    WHERE p.Status = 1 AND p.Synced = 0
    ORDER BY p.PaidAt;
END
GO

-- Sent up: the back office booked them. They are dropped at the next download (no longer waiting there).
CREATE PROCEDURE dbo.zf_sp_MarkPayRequestsSynced
    @Ids dbo.zf_tt_PayRequestId READONLY
AS
BEGIN
    SET NOCOUNT ON;
    DELETE p FROM dbo.zf_tb_PayRequest p JOIN @Ids i ON i.RequestId = p.RequestId WHERE p.Status = 1;
END
GO

PRINT 'U032_Till_PayRequests done.';
GO
