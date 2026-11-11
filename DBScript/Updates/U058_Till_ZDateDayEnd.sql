/* =============================================================================
   U058_Till_ZDateDayEnd.sql   (2026-11-11)
   Update for a TILL db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer. Safe to run again.
   No table or data change. Needs U045 (card settlement).

   zf_sp_CloseZ: the Z is dated the day it is balanced - BusinessDate = the day end date, a day end before 06:00
   counts for the day before. A Z opened at night right after the last day end and balanced the next night was on
   the night it opened (it kept the date of its first bill). The Z slip and the till reports now show the right
   day. The back office does the same when the Z arrives (new ItemApi), so this script only makes the till match.
   Same proc in the full script 02_FrontCashier_zf.sql. Back office: U058_BackOffice_ZDateDayEnd.sql.

   Run on each till any time (no TillService change):
     sqlcmd -S <till server> -d z_pos_fnt_db -E -I -b -i U058_Till_ZDateDayEnd.sql
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_ZReport', 'U') IS NULL OR COL_LENGTH('dbo.zf_tb_ZReport', 'CardSettlement') IS NULL
BEGIN
    RAISERROR('This is not a till database with U045 (zf_tb_ZReport.CardSettlement not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.zf_sp_CloseZ', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_CloseZ;
GO
-- Cashier day end: totals the open Z from the local bills and closes it, dated the day end day (U058). The next bill
-- opens a new Z.
-- @CardSettlement = the card machine settlement total typed by the cashier (U045), NULL = not entered.
CREATE PROCEDURE dbo.zf_sp_CloseZ
    @CashierId      VARCHAR(20) = NULL,
    @CardSettlement DECIMAL(18,2) = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ZNo INT;

    BEGIN TRAN;
        SELECT @ZNo = ZNo FROM dbo.zf_tb_ZReport WITH (UPDLOCK, HOLDLOCK) WHERE Status = 0;
        IF @ZNo IS NULL
            RAISERROR(N'%s', 16, 1, N'There is no open Z to close.');

        DELETE dbo.zf_tb_ZReportItem WHERE ZNo = @ZNo;
        INSERT dbo.zf_tb_ZReportItem (ZNo, ItemId, Qty, Amount)
        SELECT @ZNo, it.ItemId,
               SUM(CASE WHEN i.InvType = 2 THEN -it.Qty ELSE it.Qty END),
               SUM(CASE WHEN i.InvType = 2 THEN -it.Amount ELSE it.Amount END)
        FROM dbo.zf_tb_Invoice i
        JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = i.InvoiceNo
        WHERE i.ZNo = @ZNo AND i.Status <> 9
        GROUP BY it.ItemId;

        -- rules here must match z_sp_ReconcileZReport on the back office
        UPDATE z SET
            ClosedAt     = GETDATE(),
            -- dated by the day end (U058): a Z opened the night before is on the day it is balanced; a day end
            -- before 06:00 counts for the day before, never before the day it opened (same rule as ItemApi ZDay)
            BusinessDate = CASE WHEN CAST(z.OpenedAt AS DATE) > CAST(DATEADD(HOUR, -6, GETDATE()) AS DATE)
                                THEN CAST(z.OpenedAt AS DATE) ELSE CAST(DATEADD(HOUR, -6, GETDATE()) AS DATE) END,
            CashierId    = ISNULL(@CashierId, z.CashierId),
            InvoiceCount = (SELECT COUNT(*) FROM dbo.zf_tb_Invoice WHERE ZNo = @ZNo),
            LineCount    = (SELECT COUNT(*) FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = i.InvoiceNo
                            WHERE i.ZNo = @ZNo AND i.Status <> 9),
            TotalQty     = ISNULL((SELECT SUM(Qty) FROM dbo.zf_tb_ZReportItem WHERE ZNo = @ZNo), 0),
            SalesAmount  = ISNULL((SELECT SUM(NetAmount) FROM dbo.zf_tb_Invoice WHERE ZNo = @ZNo AND Status <> 9 AND InvType = 1), 0),
            RefundAmount = ISNULL((SELECT SUM(NetAmount) FROM dbo.zf_tb_Invoice WHERE ZNo = @ZNo AND Status <> 9 AND InvType = 2), 0),
            CashAmount   = ISNULL((SELECT SUM(CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END)
                                   FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                                   WHERE i.ZNo = @ZNo AND i.Status <> 9 AND p.PayType = 1), 0),
            CardAmount   = ISNULL((SELECT SUM(CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END)
                                   FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                                   WHERE i.ZNo = @ZNo AND i.Status <> 9 AND p.PayType = 2), 0),
            OtherAmount  = ISNULL((SELECT SUM(CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END)
                                   FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                                   WHERE i.ZNo = @ZNo AND i.Status <> 9 AND p.PayType NOT IN (1, 2)), 0),
            -- part of OtherAmount: 5 bank transfer, 6 cheque
            BankAmount   = ISNULL((SELECT SUM(CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END)
                                   FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                                   WHERE i.ZNo = @ZNo AND i.Status <> 9 AND p.PayType = 5), 0),
            ChequeAmount = ISNULL((SELECT SUM(CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END)
                                   FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                                   WHERE i.ZNo = @ZNo AND i.Status <> 9 AND p.PayType = 6), 0),
            -- discounts given on sales (SalesAmount is after them)
            ItemDiscount = ISNULL((SELECT SUM(it.Discount)
                                   FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = i.InvoiceNo
                                   WHERE i.ZNo = @ZNo AND i.Status <> 9 AND i.InvType = 1), 0),
            BillDiscount = ISNULL((SELECT SUM(Discount) FROM dbo.zf_tb_Invoice WHERE ZNo = @ZNo AND Status <> 9 AND InvType = 1), 0),
            CardSettlement = @CardSettlement,
            Status       = 1
        FROM dbo.zf_tb_ZReport z
        WHERE z.ZNo = @ZNo;

        UPDATE dbo.zf_tb_ZReport SET NetSales = SalesAmount - RefundAmount WHERE ZNo = @ZNo;

        -- drawer cash for the cashier's count (zf_sp_GetCashSummary shows the same while the Z is open)
        UPDATE z SET
            OpeningCash = ISNULL((SELECT SUM(Amount) FROM dbo.zf_tb_CashMovement WHERE ZNo = @ZNo AND Status = 1 AND Kind = 1), 0),
            PaidIn      = ISNULL((SELECT SUM(Amount) FROM dbo.zf_tb_CashMovement WHERE ZNo = @ZNo AND Status = 1 AND Kind = 2), 0),
            PaidOut     = ISNULL((SELECT SUM(Amount) FROM dbo.zf_tb_CashMovement WHERE ZNo = @ZNo AND Status = 1 AND Kind = 3), 0)
        FROM dbo.zf_tb_ZReport z WHERE z.ZNo = @ZNo;
        UPDATE dbo.zf_tb_ZReport SET ExpectedCash = OpeningCash + CashAmount + PaidIn - PaidOut WHERE ZNo = @ZNo;
    COMMIT;

    SELECT * FROM dbo.zf_tb_ZReport WHERE ZNo = @ZNo;
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
PRINT 'U058 till: zf_sp_CloseZ dates the Z by its day end.';
GO
