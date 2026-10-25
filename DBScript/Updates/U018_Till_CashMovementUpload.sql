/* =============================================================================
   U018_Till_CashMovementUpload.sql   (2026-10-25)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Bills, Z reports and cash movements are not changed (two columns are added).

   What changes (back office day reports - paid in / paid out / opening cash, Docs/StockSystem.md 6.25):
     - zf_tb_CashMovement gets Synced / SyncedAt, like zf_tb_Invoice. Rows already there are Synced = 0, so the
       till sends its whole cash in / out history on the first run.
     - type zf_tt_CashMoveSent (MoveId, Status): what the back office has
     - zf_sp_GetUnsyncedCashMovements: the oldest rows not sent yet (the body of POST api/Sync/CashMovements)
     - zf_sp_MarkCashMovementsSynced: marks only rows still at the Status that was sent
     - zf_sp_AddCashMovement: an opening cash typed again (old row Status 9) is sent again (Synced = 0)
   Same change in the full script: 02_FrontCashier_zf.sql.

   Order: U018_BackOffice_DayReports.sql + the new ItemApi first, then on each till:
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U018_Till_CashMovementUpload.sql
     2. install the new TillService (the old one keeps working after the script - it just sends nothing)
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_CashMovement', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_sp_AddCashMovement', 'P') IS NULL
   OR OBJECT_ID(N'dbo.zf_tb_Config', 'U') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_CashMovement / zf_sp_AddCashMovement / zf_tb_Config not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF COL_LENGTH('dbo.zf_tb_CashMovement', 'Synced') IS NULL
BEGIN
    ALTER TABLE dbo.zf_tb_CashMovement ADD Synced   BIT      NOT NULL CONSTRAINT DF_zf_tb_CashMovement_Synced DEFAULT (0),
                                           SyncedAt DATETIME NULL;
    PRINT 'zf_tb_CashMovement.Synced / SyncedAt added.';
END
GO
IF OBJECT_ID(N'dbo.zf_sp_GetUnsyncedCashMovements', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetUnsyncedCashMovements;
IF OBJECT_ID(N'dbo.zf_sp_MarkCashMovementsSynced', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_MarkCashMovementsSynced;
IF OBJECT_ID(N'dbo.zf_sp_AddCashMovement', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_AddCashMovement;
GO
IF TYPE_ID('dbo.zf_tt_CashMoveSent') IS NOT NULL DROP TYPE dbo.zf_tt_CashMoveSent;
GO
-- cash movements the back office answered for, with the Status that was sent
CREATE TYPE dbo.zf_tt_CashMoveSent AS TABLE (
    MoveId INT NOT NULL PRIMARY KEY,
    Status INT NOT NULL
);
GO
-- Oldest cash movements (opening cash, paid in, paid out) not sent yet - the body of POST api/Sync/CashMovements.
CREATE PROCEDURE dbo.zf_sp_GetUnsyncedCashMovements
    @Top INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@Top) MoveId, ZNo, Kind, Amount, Reason, CashierId, CreatedAt, Status
    FROM dbo.zf_tb_CashMovement WHERE Synced = 0 ORDER BY MoveId;
END
GO
-- A row whose Status changed while it was on its way (opening cash replaced) stays unsent and goes again.
CREATE PROCEDURE dbo.zf_sp_MarkCashMovementsSynced
    @Rows dbo.zf_tt_CashMoveSent READONLY
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE m SET Synced = 1, SyncedAt = GETDATE()
    FROM dbo.zf_tb_CashMovement m JOIN @Rows r ON r.MoveId = m.MoveId AND r.Status = m.Status;
END
GO
-- Opening cash / paid in / paid out (zf_tb_CashMovement) into the open Z - opens a Z when none is open, so the float
-- can be entered before the first bill. Opening cash: one per Z; typed again before the Z's first bill it replaces the
-- old one (Status 9, sent to the back office again), after a bill it is refused (use paid in / paid out).
-- Paid out needs a reason and can't take more cash than the drawer should hold. Returns the new row.
CREATE PROCEDURE dbo.zf_sp_AddCashMovement
    @Kind      INT,
    @Amount    DECIMAL(18,2),
    @Reason    NVARCHAR(100) = NULL,
    @CashierId VARCHAR(20) = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ZNo INT, @MoveId INT, @Msg NVARCHAR(200), @InDrawer DECIMAL(18,2);
    SET @Reason = NULLIF(LTRIM(RTRIM(@Reason)), N'');

    IF @Kind NOT IN (1, 2, 3)
        RAISERROR(N'%s', 16, 1, N'Kind must be 1 (opening cash), 2 (paid in) or 3 (paid out).');
    IF @Amount IS NULL OR @Amount <= 0
        RAISERROR(N'%s', 16, 1, N'Enter an amount above 0.');
    IF @Kind = 3 AND @Reason IS NULL
        RAISERROR(N'%s', 16, 1, N'Enter a reason for the paid out.');

    BEGIN TRAN;
        EXEC dbo.zf_sp_OpenZ @CashierId = @CashierId, @ZNo = @ZNo OUTPUT, @Silent = 1;

        IF @Kind = 1 AND EXISTS (SELECT 1 FROM dbo.zf_tb_CashMovement WITH (UPDLOCK, HOLDLOCK) WHERE ZNo = @ZNo AND Kind = 1 AND Status = 1)
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.zf_tb_Invoice WHERE ZNo = @ZNo)
            BEGIN
                SET @Msg = N'Opening cash for Z ' + CAST(@ZNo AS NVARCHAR(10)) + N' is already entered and bills are made. Use Paid In or Paid Out.';
                RAISERROR(N'%s', 16, 1, @Msg);
            END
            UPDATE dbo.zf_tb_CashMovement SET Status = 9, Synced = 0 WHERE ZNo = @ZNo AND Kind = 1 AND Status = 1;
        END

        IF @Kind = 3
        BEGIN
            SET @InDrawer =
                  ISNULL((SELECT SUM(CASE Kind WHEN 3 THEN -Amount ELSE Amount END) FROM dbo.zf_tb_CashMovement
                          WHERE ZNo = @ZNo AND Status = 1), 0)
                + ISNULL((SELECT SUM(CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END)
                          FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                          WHERE i.ZNo = @ZNo AND i.Status <> 9 AND p.PayType = 1), 0);
            IF @Amount > @InDrawer
            BEGIN
                SET @Msg = N'Paid out is more than the cash in the drawer (Rs ' + CONVERT(NVARCHAR(30), @InDrawer) + N').';
                RAISERROR(N'%s', 16, 1, @Msg);
            END
        END

        INSERT dbo.zf_tb_CashMovement (ZNo, Kind, Amount, Reason, CashierId)
        VALUES (@ZNo, @Kind, @Amount, @Reason, @CashierId);
        SET @MoveId = SCOPE_IDENTITY();
    COMMIT;

    SELECT MoveId, ZNo, Kind, Amount, Reason, CashierId, CreatedAt FROM dbo.zf_tb_CashMovement WHERE MoveId = @MoveId;
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
GO
SET NOEXEC OFF;
GO
PRINT 'U018_Till_CashMovementUpload done.';
GO
