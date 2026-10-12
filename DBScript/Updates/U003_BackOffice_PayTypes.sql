/* =============================================================================
   U003_BackOffice_PayTypes.sql   (2026-10-12)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. No data is changed (two empty columns are added).

   What changes (bank transfer and cheque as their own payment types, Docs/StockSystem.md 6.15):
     - z_tb_ZReport gets BankAmount and ChequeAmount (PayType 5 and 6). Both are PART OF OtherAmount.
       NULL = the till did not send a split (Z from before this update, or a till still on the old TillService).
     - z_sp_SubmitZReport takes @BankAmount / @ChequeAmount (optional - old tills keep working).
     - No change to bills: z_tb_SalesPayment.PayType already takes 5 and 6.
   Same change in the full script: 01_BackOffice_Stock.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U003_BackOffice_PayTypes.sql
   Then: deploy the new ItemApi (it needs these columns - run this script BEFORE the new ItemApi),
         then U003_Till_PayTypes.sql on each till.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_ZReport', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Terminal', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_ZReport / z_tb_Terminal not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. columns
IF COL_LENGTH('dbo.z_tb_ZReport', 'BankAmount') IS NULL
BEGIN
    ALTER TABLE dbo.z_tb_ZReport ADD BankAmount   DECIMAL(18,2) NULL,
                                     ChequeAmount DECIMAL(18,2) NULL;
    PRINT 'z_tb_ZReport.BankAmount / ChequeAmount added.';
END
GO

-- 2. procedure
IF OBJECT_ID(N'dbo.z_sp_SubmitZReport', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_SubmitZReport;
GO
-- Till sends its Z at day end. Stored (or replaced, if not yet reconciled) and reconciled at once.
-- Returns the reconcile result row.
CREATE PROCEDURE dbo.z_sp_SubmitZReport
    @TerminalId    INT,
    @ZNo           INT,
    @BusinessDate  DATE,
    @CashierId     VARCHAR(20) = NULL,
    @OpenedAt      DATETIME = NULL,
    @ClosedAt      DATETIME = NULL,
    @FromSeq       INT = NULL,
    @ToSeq         INT = NULL,
    @InvoiceCount  INT,
    @LineCount     INT,
    @TotalQty      DECIMAL(18,3),
    @SalesAmount   DECIMAL(18,2),
    @RefundAmount  DECIMAL(18,2),
    @NetSales      DECIMAL(18,2),
    @CashAmount    DECIMAL(18,2) = 0,
    @CardAmount    DECIMAL(18,2) = 0,
    @OtherAmount   DECIMAL(18,2) = 0,
    @BankAmount    DECIMAL(18,2) = NULL,   -- part of @OtherAmount; NULL = till without the split
    @ChequeAmount  DECIMAL(18,2) = NULL,
    @Items         dbo.z_tt_ZReportItem READONLY
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LocationId INT, @ZId INT, @Status INT;

    SELECT @LocationId = LocationId FROM dbo.z_tb_Terminal WHERE TerminalId = @TerminalId AND Status = 1;
    IF @LocationId IS NULL
        RAISERROR(N'%s', 16, 1, N'Terminal is not registered or is disabled.');

    BEGIN TRAN;
        SELECT @ZId = ZId, @Status = Status
        FROM dbo.z_tb_ZReport WITH (UPDLOCK, HOLDLOCK)
        WHERE TerminalId = @TerminalId AND ZNo = @ZNo;

        IF @ZId IS NULL
        BEGIN
            INSERT dbo.z_tb_ZReport
                (TerminalId, ZNo, LocationId, BusinessDate, CashierId, OpenedAt, ClosedAt, FromSeq, ToSeq,
                 InvoiceCount, LineCount, TotalQty, SalesAmount, RefundAmount, NetSales,
                 CashAmount, CardAmount, OtherAmount, BankAmount, ChequeAmount, Status)
            VALUES
                (@TerminalId, @ZNo, @LocationId, @BusinessDate, @CashierId, @OpenedAt, @ClosedAt, @FromSeq, @ToSeq,
                 @InvoiceCount, @LineCount, @TotalQty, @SalesAmount, @RefundAmount, @NetSales,
                 @CashAmount, @CardAmount, @OtherAmount, @BankAmount, @ChequeAmount, 2);
            SET @ZId = SCOPE_IDENTITY();
        END
        ELSE IF @Status <> 3   -- a reconciled Z is final; a resend is ignored
        BEGIN
            UPDATE dbo.z_tb_ZReport SET
                BusinessDate = @BusinessDate, CashierId = @CashierId, OpenedAt = @OpenedAt, ClosedAt = @ClosedAt,
                FromSeq = @FromSeq, ToSeq = @ToSeq, InvoiceCount = @InvoiceCount, LineCount = @LineCount,
                TotalQty = @TotalQty, SalesAmount = @SalesAmount, RefundAmount = @RefundAmount, NetSales = @NetSales,
                CashAmount = @CashAmount, CardAmount = @CardAmount, OtherAmount = @OtherAmount,
                BankAmount = @BankAmount, ChequeAmount = @ChequeAmount,
                Status = 2, SubmittedAt = GETDATE()
            WHERE ZId = @ZId;
            DELETE dbo.z_tb_ZReportItem WHERE ZId = @ZId;
        END

        IF @Status IS NULL OR @Status <> 3
            INSERT dbo.z_tb_ZReportItem (ZId, ItemId, Qty, Amount)
            SELECT @ZId, ItemId, Qty, Amount FROM @Items;
    COMMIT;

    IF @Status IS NULL OR @Status <> 3
        EXEC dbo.z_sp_ReconcileZReport @TerminalId = @TerminalId, @ZNo = @ZNo, @Silent = 1;

    SELECT ZId, TerminalId, ZNo, BusinessDate, Status, InvoiceCount, SrvInvoiceCount, LineCount, SrvLineCount,
           TotalQty, SrvTotalQty, NetSales, SrvNetSales, ISNULL(MissingCount, 0) AS MissingCount, MismatchNote
    FROM dbo.z_tb_ZReport WHERE ZId = @ZId;
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

PRINT 'U003 back office: bank transfer / cheque totals on the Z (z_sp_SubmitZReport).';
GO
SET NOEXEC OFF;
GO