/* =============================================================================
   U004_Till_RefundBill.sql   (2026-10-13)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Bills, Z reports and cash data are not touched (two empty columns are added).

   What changes (refund against the original bill, Docs/StockSystem.md 6.16):
     - zf_tb_Invoice gets RefInvoiceNo, zf_tb_InvoiceItem gets RefLineNum: a refund bill points at the sale bill
       and the line it gives back. NULL = a sale, or a refund made without a bill.
     - new type zf_tt_RefundLine, new procedures zf_sp_GetInvoiceForRefund (the bill with what is left to refund)
       and zf_sp_SaveBillRefund (saves the refund; never more than was sold on a line).
     - zf_sp_GetInvoiceForPrint also returns RefInvoiceNo (printed on the refund receipt).
   No back office change: a refund against a bill is uploaded as a normal refund bill.
   Same change in the full script: 02_FrontCashier_zf.sql.

   On each till:
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U004_Till_RefundBill.sql
        (the running TillService can stay up - the old one works with the updated database)
     2. install the new TillService (it prints the bill number barcode and has the refund routes)
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_Invoice', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_tb_Config', 'U') IS NULL
   OR OBJECT_ID(N'dbo.zf_sp_SaveInvoice', 'P') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_Invoice / zf_tb_Config / zf_sp_SaveInvoice not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. columns
IF COL_LENGTH('dbo.zf_tb_Invoice', 'RefInvoiceNo') IS NULL
BEGIN
    ALTER TABLE dbo.zf_tb_Invoice ADD RefInvoiceNo VARCHAR(30) NULL;
    PRINT 'zf_tb_Invoice.RefInvoiceNo added.';
END
GO
IF COL_LENGTH('dbo.zf_tb_InvoiceItem', 'RefLineNum') IS NULL
BEGIN
    ALTER TABLE dbo.zf_tb_InvoiceItem ADD RefLineNum INT NULL;
    PRINT 'zf_tb_InvoiceItem.RefLineNum added.';
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_zf_tb_Invoice_Ref' AND object_id = OBJECT_ID('dbo.zf_tb_Invoice'))
    CREATE INDEX IX_zf_tb_Invoice_Ref ON dbo.zf_tb_Invoice (RefInvoiceNo);
GO

-- 2. type (the procedure that uses it is dropped first, so the script can run again)
IF OBJECT_ID(N'dbo.zf_sp_SaveBillRefund', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_SaveBillRefund;
GO
IF TYPE_ID(N'dbo.zf_tt_RefundLine') IS NOT NULL DROP TYPE dbo.zf_tt_RefundLine;
GO
-- lines picked on the refund screen: the till works out price and amount itself
CREATE TYPE dbo.zf_tt_RefundLine AS TABLE (
    RefLineNum INT           NOT NULL PRIMARY KEY,   -- LineNum on the sale bill
    Qty        DECIMAL(18,3) NOT NULL                -- how much of it comes back now
);
GO

-- 3. procedures
IF OBJECT_ID(N'dbo.zf_sp_GetInvoiceForPrint', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetInvoiceForPrint;
GO
-- One bill with everything the receipt needs. 3 result sets: header (+ till code), lines (with the item's code
-- and name), payments. Error when there is no such bill on this till.
CREATE PROCEDURE dbo.zf_sp_GetInvoiceForPrint
    @InvoiceNo VARCHAR(30)
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Invoice WHERE InvoiceNo = @InvoiceNo)
        RAISERROR(N'%s', 16, 1, N'Bill not found on this till.');

    SELECT i.InvoiceNo, i.InvoiceSeq, i.ZNo, i.InvType, i.InvDate, i.CashierId, i.GrossAmount, i.Discount,
           i.DiscountPercent, i.NetAmount, i.Status, i.PriceType, i.Synced, c.TerminalCode,
           i.RefInvoiceNo   -- refund against a bill: the sale bill (printed on the refund receipt)
    FROM dbo.zf_tb_Invoice i CROSS JOIN dbo.zf_tb_Config c
    WHERE i.InvoiceNo = @InvoiceNo;

    SELECT it.LineNum, it.ItemId, it.Qty, it.UnitPrice, it.Discount, it.Amount, it.PriceType, it.MktPrice,
           COALESCE(it.LineDescrip, m.Inv_Descrip, m.Descrip, N'Item ' + CAST(it.ItemId AS NVARCHAR(20))) AS Name,
           COALESCE(m.Barcode, m.RefCode, CASE WHEN it.ItemId <> 0 THEN CAST(it.ItemId AS NVARCHAR(20)) END) AS Code
    FROM dbo.zf_tb_InvoiceItem it
    LEFT JOIN dbo.zf_tb_Item m ON m.ItemId = it.ItemId AND it.ItemId <> 0
    WHERE it.InvoiceNo = @InvoiceNo
    ORDER BY it.LineNum;

    SELECT LineNum, PayType, Amount, RefNo, Tendered
    FROM dbo.zf_tb_InvoicePayment WHERE InvoiceNo = @InvoiceNo ORDER BY LineNum;
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

IF OBJECT_ID(N'dbo.zf_sp_GetInvoiceForRefund', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetInvoiceForRefund;
GO
-- A sale bill as the refund screen shows it: what was sold, what was already given back, what is left.
-- 3 result sets: header (CanRefund 0 + Reason when nothing on it can be refunded), lines, the bill's payments.
-- Error when there is no such bill on this till - a bill is refunded on the till that made it.
CREATE PROCEDURE dbo.zf_sp_GetInvoiceForRefund
    @InvoiceNo VARCHAR(30)
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Invoice WHERE InvoiceNo = @InvoiceNo)
        RAISERROR(N'%s', 16, 1, N'Bill not found on this till.');

    -- given back so far, per line of the sale bill (refund bills that were voided do not count)
    DECLARE @Done TABLE (LineNum INT PRIMARY KEY, Qty DECIMAL(18,3));
    INSERT @Done (LineNum, Qty)
    SELECT it.RefLineNum, SUM(it.Qty)
    FROM dbo.zf_tb_Invoice r
    JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = r.InvoiceNo
    WHERE r.RefInvoiceNo = @InvoiceNo AND r.InvType = 2 AND r.Status <> 9 AND it.RefLineNum IS NOT NULL
    GROUP BY it.RefLineNum;

    DECLARE @Left DECIMAL(18,3);
    SET @Left = ISNULL((SELECT SUM(it.Qty - ISNULL(d.Qty, 0))
                        FROM dbo.zf_tb_InvoiceItem it LEFT JOIN @Done d ON d.LineNum = it.LineNum
                        WHERE it.InvoiceNo = @InvoiceNo), 0);

    SELECT i.InvoiceNo, i.ZNo, i.InvType, i.InvDate, i.CashierId, i.GrossAmount, i.Discount, i.DiscountPercent,
           i.NetAmount, i.Status, i.PriceType,
           ISNULL((SELECT SUM(r.NetAmount) FROM dbo.zf_tb_Invoice r
                   WHERE r.RefInvoiceNo = i.InvoiceNo AND r.InvType = 2 AND r.Status <> 9), 0) AS RefundedAmount,
           CAST(CASE WHEN i.InvType = 1 AND i.Status = 1 AND @Left > 0 THEN 1 ELSE 0 END AS BIT) AS CanRefund,
           CASE WHEN i.InvType <> 1 THEN N'This is a refund bill - it cannot be refunded.'
                WHEN i.Status <> 1  THEN N'This bill was voided - it cannot be refunded.'
                WHEN @Left <= 0     THEN N'Everything on this bill was already refunded.' END AS Reason
    FROM dbo.zf_tb_Invoice i
    WHERE i.InvoiceNo = @InvoiceNo;

    SELECT it.LineNum, it.ItemId, it.Qty, it.UnitPrice, it.Discount, it.Amount, it.PriceType,
           COALESCE(it.LineDescrip, m.Inv_Descrip, m.Descrip, N'Item ' + CAST(it.ItemId AS NVARCHAR(20))) AS Name,
           COALESCE(m.Barcode, m.RefCode, CASE WHEN it.ItemId <> 0 THEN CAST(it.ItemId AS NVARCHAR(20)) END) AS Code,
           m.UnitCode,
           CAST(ISNULL(d.Qty, 0) AS DECIMAL(18,3))          AS RefundedQty,
           CAST(it.Qty - ISNULL(d.Qty, 0) AS DECIMAL(18,3)) AS LeftQty
    FROM dbo.zf_tb_InvoiceItem it
    LEFT JOIN @Done d ON d.LineNum = it.LineNum
    LEFT JOIN dbo.zf_tb_Item m ON m.ItemId = it.ItemId AND it.ItemId <> 0
    WHERE it.InvoiceNo = @InvoiceNo
    ORDER BY it.LineNum;

    SELECT LineNum, PayType, Amount, RefNo
    FROM dbo.zf_tb_InvoicePayment WHERE InvoiceNo = @InvoiceNo ORDER BY LineNum;
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

-- Refund against the original bill. The page sends only WHICH lines and HOW MUCH of each (@Lines); the price,
-- the discounts and the amount come from the sale bill, never from the page.
--   - Only a completed sale bill of THIS till. A line can never give back more than was sold on it minus what
--     earlier refunds of the same bill already gave back - no PIN lifts that.
--   - Line: the sale's UnitPrice; its line discount in proportion to the quantity (the last part of a line takes
--     what is left of the discount).
--   - Bill discount of the sale: given back in proportion to the refunded line amounts; the refund that brings the
--     last of the bill back takes what is left, so the refunds of a bill add up to what the customer paid.
--   - Saved by zf_sp_SaveInvoice as a normal refund bill (InvType 2: own number, open Z, upload, stock comes back
--     on the back office) with ONE payment of the whole amount (@PayType / @RefNo), then marked with
--     RefInvoiceNo / RefLineNum. UnitCost and MktPrice are the sale's, so the profit taken back is the profit made.
--   - @CheckOnly 1: nothing is saved - the same checks and amounts, for the screen before the cashier confirms.
-- 2 result sets: totals (InvoiceNo NULL when @CheckOnly), refund lines.
CREATE PROCEDURE dbo.zf_sp_SaveBillRefund
    @RefInvoiceNo VARCHAR(30),
    @CashierId    VARCHAR(20) = NULL,
    @PayType      INT = 1,              -- how the money goes back: 1 cash, 2 card, 3 credit, 4 voucher, 5 bank transfer, 6 cheque
    @RefNo        VARCHAR(30) = NULL,
    @Lines        dbo.zf_tt_RefundLine READONLY,
    @CheckOnly    BIT = 0
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @InvoiceNo VARCHAR(30), @InvType INT, @Status INT, @BillDiscount DECIMAL(18,2), @BillLines DECIMAL(18,2),
            @Sub DECIMAL(18,2), @Discount DECIMAL(18,2), @Net DECIMAL(18,2), @GivenBack DECIMAL(18,2), @AllBack BIT,
            @Msg NVARCHAR(400);
    DECLARE @Items dbo.zf_tt_InvoiceItem, @Payments dbo.zf_tt_InvoicePayment;
    DECLARE @Map  TABLE (LineNum INT PRIMARY KEY, RefLineNum INT NOT NULL);
    DECLARE @Done TABLE (LineNum INT PRIMARY KEY, Qty DECIMAL(18,3), Discount DECIMAL(18,2));

    IF NOT EXISTS (SELECT 1 FROM @Lines)
        RAISERROR(N'%s', 16, 1, N'Pick at least one line to refund.');
    IF EXISTS (SELECT 1 FROM @Lines WHERE Qty <= 0)
        RAISERROR(N'%s', 16, 1, N'Refund quantity must be above 0.');
    IF @PayType NOT IN (1, 2, 3, 4, 5, 6)
        RAISERROR(N'%s', 16, 1, N'Payment type must be 1 cash, 2 card, 3 credit, 4 voucher, 5 bank transfer or 6 cheque.');

    BEGIN TRAN;
        -- the sale bill stays locked until the refund is saved: two refunds of one bill can't both pass the check
        SELECT @InvType = InvType, @Status = Status, @BillDiscount = Discount
        FROM dbo.zf_tb_Invoice WITH (UPDLOCK, HOLDLOCK) WHERE InvoiceNo = @RefInvoiceNo;

        IF @InvType IS NULL
            RAISERROR(N'%s', 16, 1, N'Bill not found on this till.');
        IF @InvType <> 1
            RAISERROR(N'%s', 16, 1, N'This is a refund bill - it cannot be refunded.');
        IF @Status <> 1
            RAISERROR(N'%s', 16, 1, N'This bill was voided - it cannot be refunded.');
        IF EXISTS (SELECT 1 FROM @Lines l
                   WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_InvoiceItem it WHERE it.InvoiceNo = @RefInvoiceNo AND it.LineNum = l.RefLineNum))
            RAISERROR(N'%s', 16, 1, N'A picked line is not on this bill. Scan the bill again.');

        INSERT @Done (LineNum, Qty, Discount)
        SELECT it.RefLineNum, SUM(it.Qty), SUM(it.Discount)
        FROM dbo.zf_tb_Invoice r
        JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = r.InvoiceNo
        WHERE r.RefInvoiceNo = @RefInvoiceNo AND r.InvType = 2 AND r.Status <> 9 AND it.RefLineNum IS NOT NULL
        GROUP BY it.RefLineNum;

        -- never more than was sold on the line minus what was already given back
        SELECT TOP 1 @Msg = COALESCE(it.LineDescrip, m.Inv_Descrip, m.Descrip, N'Line ' + CAST(it.LineNum AS NVARCHAR(10)))
               + CASE WHEN it.Qty - ISNULL(d.Qty, 0) <= 0 THEN N' was already refunded in full.'
                      ELSE N': only ' + CONVERT(NVARCHAR(30), CAST(it.Qty - ISNULL(d.Qty, 0) AS DECIMAL(18,3)))
                           + N' left to refund (sold ' + CONVERT(NVARCHAR(30), it.Qty)
                           + N', already refunded ' + CONVERT(NVARCHAR(30), CAST(ISNULL(d.Qty, 0) AS DECIMAL(18,3))) + N').' END
        FROM @Lines l
        JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = @RefInvoiceNo AND it.LineNum = l.RefLineNum
        LEFT JOIN @Done d ON d.LineNum = it.LineNum
        LEFT JOIN dbo.zf_tb_Item m ON m.ItemId = it.ItemId AND it.ItemId <> 0
        WHERE l.Qty > it.Qty - ISNULL(d.Qty, 0)
        ORDER BY l.RefLineNum;
        IF @Msg IS NOT NULL
            RAISERROR(N'%s', 16, 1, @Msg);

        INSERT @Map (LineNum, RefLineNum)
        SELECT ROW_NUMBER() OVER (ORDER BY RefLineNum), RefLineNum FROM @Lines;

        INSERT @Items (LineNum, ItemId, Qty, UnitPrice, Discount, Amount, LineDescrip, PriceType, PriceLinkId)
        SELECT mp.LineNum, it.ItemId, l.Qty, it.UnitPrice, x.Discount, ROUND(l.Qty * it.UnitPrice, 2) - x.Discount,
               CASE WHEN it.ItemId = 0 THEN it.LineDescrip END, it.PriceType, it.PriceLinkId
        FROM @Map mp
        JOIN @Lines l ON l.RefLineNum = mp.RefLineNum
        JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = @RefInvoiceNo AND it.LineNum = l.RefLineNum
        LEFT JOIN @Done d ON d.LineNum = it.LineNum
        CROSS APPLY (SELECT CAST(CASE WHEN l.Qty < it.Qty - ISNULL(d.Qty, 0) THEN ROUND(it.Discount * l.Qty / it.Qty, 2)
                                      WHEN it.Discount > ISNULL(d.Discount, 0) THEN it.Discount - ISNULL(d.Discount, 0)
                                      ELSE 0 END AS DECIMAL(18,2)) AS Discount) x;

        SELECT @Sub = SUM(Amount) FROM @Items;
        SELECT @BillLines = SUM(Amount) FROM dbo.zf_tb_InvoiceItem WHERE InvoiceNo = @RefInvoiceNo;
        SELECT @GivenBack = ISNULL(SUM(Discount), 0) FROM dbo.zf_tb_Invoice
        WHERE RefInvoiceNo = @RefInvoiceNo AND InvType = 2 AND Status <> 9;
        SET @AllBack = CASE WHEN EXISTS (SELECT 1 FROM dbo.zf_tb_InvoiceItem it
                                         LEFT JOIN @Done d ON d.LineNum = it.LineNum
                                         LEFT JOIN @Lines l ON l.RefLineNum = it.LineNum
                                         WHERE it.InvoiceNo = @RefInvoiceNo AND it.Qty - ISNULL(d.Qty, 0) - ISNULL(l.Qty, 0) > 0)
                            THEN 0 ELSE 1 END;

        SET @Discount = CASE WHEN @BillDiscount <= 0 OR @BillLines <= 0 THEN 0
                             WHEN @AllBack = 1 THEN @BillDiscount - @GivenBack
                             ELSE ROUND(@BillDiscount * @Sub / @BillLines, 2) END;
        IF @Discount < 0 SET @Discount = 0;
        IF @Discount > @Sub SET @Discount = @Sub;
        SET @Net = @Sub - @Discount;

        IF @CheckOnly = 0
        BEGIN
            INSERT @Payments (LineNum, PayType, Amount, RefNo, Tendered) VALUES (1, @PayType, @Net, @RefNo, NULL);

            EXEC dbo.zf_sp_SaveInvoice @InvType = 2, @PriceType = 1, @CashierId = @CashierId, @Discount = @Discount,
                                       @Items = @Items, @Payments = @Payments, @InvoiceNo = @InvoiceNo OUTPUT;

            UPDATE dbo.zf_tb_Invoice SET RefInvoiceNo = @RefInvoiceNo WHERE InvoiceNo = @InvoiceNo;

            UPDATE r SET RefLineNum = mp.RefLineNum, UnitCost = o.UnitCost, MktPrice = o.MktPrice
            FROM dbo.zf_tb_InvoiceItem r
            JOIN @Map mp ON mp.LineNum = r.LineNum
            JOIN dbo.zf_tb_InvoiceItem o ON o.InvoiceNo = @RefInvoiceNo AND o.LineNum = mp.RefLineNum
            WHERE r.InvoiceNo = @InvoiceNo;
        END
    COMMIT;

    SELECT @InvoiceNo AS InvoiceNo, @RefInvoiceNo AS RefInvoiceNo, @Sub AS LinesAmount, @Discount AS Discount, @Net AS NetAmount;

    SELECT mp.RefLineNum, i.LineNum, i.ItemId,
           COALESCE(i.LineDescrip, m.Inv_Descrip, m.Descrip, N'Item ' + CAST(i.ItemId AS NVARCHAR(20))) AS Name,
           i.Qty, i.UnitPrice, i.Discount, i.Amount
    FROM @Items i
    JOIN @Map mp ON mp.LineNum = i.LineNum
    LEFT JOIN dbo.zf_tb_Item m ON m.ItemId = i.ItemId AND i.ItemId <> 0
    ORDER BY i.LineNum;
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

PRINT 'U004 till: refund against the original bill (zf_sp_GetInvoiceForRefund, zf_sp_SaveBillRefund, zf_sp_GetInvoiceForPrint).';
GO
SET NOEXEC OFF;
GO
