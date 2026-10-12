/* =============================================================================
   U003_Till_PayTypes.sql   (2026-10-12)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Bills, Z reports and cash data are not touched (two empty columns are added).

   What changes (bank transfer and cheque as their own payment types, Docs/StockSystem.md 6.15):
     - zf_tb_ZReport gets BankAmount and ChequeAmount (PayType 5 and 6). Both are PART OF OtherAmount,
       which keeps its meaning (everything that is not cash or card). NULL = Z closed before this update.
     - zf_sp_CloseZ fills them, zf_sp_GetXReport returns them (this replaces the U002 version - run U002 first
       or skip it, both work), zf_sp_GetZForSubmit sends them to the back office.
     - No change to bills: zf_tb_InvoicePayment.PayType already takes 5 and 6.
   Same change in the full script: 02_FrontCashier_zf.sql.

   Order: U003_BackOffice_PayTypes.sql + new ItemApi first is best (else the back office only keeps "Other"),
   then on each till:
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U003_Till_PayTypes.sql
        (the running TillService can stay up - the old one works with the updated database)
     2. install the new TillService
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_ZReport', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_tb_Config', 'U') IS NULL
   OR OBJECT_ID(N'dbo.zf_tb_CashMovement', 'U') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_ZReport / zf_tb_Config / zf_tb_CashMovement not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. columns
IF COL_LENGTH('dbo.zf_tb_ZReport', 'BankAmount') IS NULL
BEGIN
    ALTER TABLE dbo.zf_tb_ZReport ADD BankAmount   DECIMAL(18,2) NULL,
                                      ChequeAmount DECIMAL(18,2) NULL;
    PRINT 'zf_tb_ZReport.BankAmount / ChequeAmount added.';
END
GO

-- 2. procedures
IF OBJECT_ID(N'dbo.zf_sp_CloseZ', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_CloseZ;
GO
-- Cashier day end: totals the open Z from the local bills and closes it. The next bill opens a new Z.
CREATE PROCEDURE dbo.zf_sp_CloseZ
    @CashierId VARCHAR(20) = NULL
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

IF OBJECT_ID(N'dbo.zf_sp_GetZForSubmit', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetZForSubmit;
GO
-- Header + items of a closed Z = the body of POST api/Sync/ZReport.
-- @ZNo NULL = oldest closed Z not yet reconciled.
CREATE PROCEDURE dbo.zf_sp_GetZForSubmit
    @ZNo INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @ZNo IS NULL
        SELECT TOP 1 @ZNo = ZNo FROM dbo.zf_tb_ZReport WHERE Status IN (1, 2, 4) ORDER BY ZNo;

    SELECT c.TerminalId, z.ZNo, z.BusinessDate, z.CashierId, z.OpenedAt, z.ClosedAt, z.FromSeq, z.ToSeq,
           z.InvoiceCount, z.LineCount, z.TotalQty, z.SalesAmount, z.RefundAmount, z.NetSales,
           z.CashAmount, z.CardAmount, z.OtherAmount, z.BankAmount, z.ChequeAmount, z.Status
    FROM dbo.zf_tb_ZReport z CROSS JOIN dbo.zf_tb_Config c
    WHERE z.ZNo = @ZNo AND z.Status <> 0;

    SELECT ItemId, Qty, Amount FROM dbo.zf_tb_ZReportItem WHERE ZNo = @ZNo;
END
GO

IF OBJECT_ID(N'dbo.zf_sp_GetXReport', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetXReport;
GO
-- X report: the totals of the OPEN Z as zf_sp_CloseZ would store them right now - read only, nothing is closed or
-- changed. Same columns as the zf_sp_CloseZ answer (ClosedAt NULL, Status 0); no rows when no Z is open.
-- The rules here must match zf_sp_CloseZ.
CREATE PROCEDURE dbo.zf_sp_GetXReport
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ZNo INT = (SELECT MAX(ZNo) FROM dbo.zf_tb_ZReport WHERE Status = 0);

    SELECT z.ZNo, z.BusinessDate, z.CashierId, z.OpenedAt, CAST(NULL AS DATETIME) AS ClosedAt, z.FromSeq, z.ToSeq,
           b.InvoiceCount, l.LineCount, l.TotalQty, b.SalesAmount, b.RefundAmount,
           b.SalesAmount - b.RefundAmount AS NetSales,
           p.CashAmount, p.CardAmount, p.OtherAmount, p.BankAmount, p.ChequeAmount, m.OpeningCash, m.PaidIn, m.PaidOut,
           m.OpeningCash + p.CashAmount + m.PaidIn - m.PaidOut AS ExpectedCash, z.Status
    FROM dbo.zf_tb_ZReport z
    CROSS APPLY (SELECT COUNT(*) AS InvoiceCount,
                        ISNULL(SUM(CASE WHEN Status <> 9 AND InvType = 1 THEN NetAmount END), 0) AS SalesAmount,
                        ISNULL(SUM(CASE WHEN Status <> 9 AND InvType = 2 THEN NetAmount END), 0) AS RefundAmount
                 FROM dbo.zf_tb_Invoice WHERE ZNo = z.ZNo) b
    CROSS APPLY (SELECT COUNT(*) AS LineCount,
                        ISNULL(SUM(CASE WHEN i.InvType = 2 THEN -it.Qty ELSE it.Qty END), 0) AS TotalQty
                 FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = i.InvoiceNo
                 WHERE i.ZNo = z.ZNo AND i.Status <> 9) l
    CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN x.PayType = 1 THEN x.Amount END), 0) AS CashAmount,
                        ISNULL(SUM(CASE WHEN x.PayType = 2 THEN x.Amount END), 0) AS CardAmount,
                        ISNULL(SUM(CASE WHEN x.PayType NOT IN (1, 2) THEN x.Amount END), 0) AS OtherAmount,
                        ISNULL(SUM(CASE WHEN x.PayType = 5 THEN x.Amount END), 0) AS BankAmount,
                        ISNULL(SUM(CASE WHEN x.PayType = 6 THEN x.Amount END), 0) AS ChequeAmount
                 FROM (SELECT p.PayType, CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END AS Amount
                       FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                       WHERE i.ZNo = z.ZNo AND i.Status <> 9) x) p
    CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN Kind = 1 THEN Amount END), 0) AS OpeningCash,
                        ISNULL(SUM(CASE WHEN Kind = 2 THEN Amount END), 0) AS PaidIn,
                        ISNULL(SUM(CASE WHEN Kind = 3 THEN Amount END), 0) AS PaidOut
                 FROM dbo.zf_tb_CashMovement WHERE ZNo = z.ZNo AND Status = 1) m
    WHERE z.ZNo = @ZNo;
END
GO

PRINT 'U003 till: bank transfer / cheque totals on the Z (zf_sp_CloseZ, zf_sp_GetZForSubmit, zf_sp_GetXReport).';
GO
SET NOEXEC OFF;
GO