/* =============================================================================
   U014_Till_ZDiscounts_FullReload.sql   (2026-10-21)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Bills, Z reports already closed, items and cash data are not changed by the script itself.

   What changes:
     1. Discounts on the Z / X report: zf_tb_ZReport gets ItemDiscount and BillDiscount (sales bills, not voided).
        zf_sp_CloseZ fills them, zf_sp_GetXReport works them out the same way. SalesAmount stays AFTER the discounts;
        the slip prints "Sales before discounts", "- Item discounts", "- Bill discounts", then Sales. NULL on a Z
        closed before this update. Not sent to the back office.
     2. Full reload: zf_sp_UpsertItems / zf_sp_UpsertPriceLinks get @Full BIT = 0. With @Full = 1 (a download
        without "since" - the first one of a till, or Menu > Full item reload, POST /sync/full) a till item / price
        link the back office no longer has is set to Status 0. An empty full download changes nothing.
   Same change in the full script: 02_FrontCashier_zf.sql.

   On each till (the running TillService keeps working after it):
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U014_Till_ZDiscounts_FullReload.sql
     2. install the new TillService, then the billing page (Lovable Prompt 65)
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_ZReport', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_sp_CloseZ', 'P') IS NULL
   OR OBJECT_ID(N'dbo.zf_sp_UpsertItems', 'P') IS NULL OR COL_LENGTH('dbo.zf_tb_ZReport', 'BankAmount') IS NULL
BEGIN
    RAISERROR('This is not a till database with U003 (zf_tb_ZReport.BankAmount / zf_sp_CloseZ / zf_sp_UpsertItems not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF COL_LENGTH('dbo.zf_tb_ZReport', 'ItemDiscount') IS NULL
    ALTER TABLE dbo.zf_tb_ZReport ADD ItemDiscount DECIMAL(18,2) NULL,
                                      BillDiscount DECIMAL(18,2) NULL;
GO
IF OBJECT_ID(N'dbo.zf_sp_CloseZ', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_CloseZ;
IF OBJECT_ID(N'dbo.zf_sp_GetXReport', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetXReport;
IF OBJECT_ID(N'dbo.zf_sp_UpsertItems', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_UpsertItems;
IF OBJECT_ID(N'dbo.zf_sp_UpsertPriceLinks', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_UpsertPriceLinks;
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
            -- discounts given on sales (SalesAmount is after them)
            ItemDiscount = ISNULL((SELECT SUM(it.Discount)
                                   FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = i.InvoiceNo
                                   WHERE i.ZNo = @ZNo AND i.Status <> 9 AND i.InvType = 1), 0),
            BillDiscount = ISNULL((SELECT SUM(Discount) FROM dbo.zf_tb_Invoice WHERE ZNo = @ZNo AND Status <> 9 AND InvType = 1), 0),
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
           m.OpeningCash + p.CashAmount + m.PaidIn - m.PaidOut AS ExpectedCash, z.Status,
           l.ItemDiscount, b.BillDiscount
    FROM dbo.zf_tb_ZReport z
    CROSS APPLY (SELECT COUNT(*) AS InvoiceCount,
                        ISNULL(SUM(CASE WHEN Status <> 9 AND InvType = 1 THEN NetAmount END), 0) AS SalesAmount,
                        ISNULL(SUM(CASE WHEN Status <> 9 AND InvType = 2 THEN NetAmount END), 0) AS RefundAmount,
                        ISNULL(SUM(CASE WHEN Status <> 9 AND InvType = 1 THEN Discount END), 0) AS BillDiscount
                 FROM dbo.zf_tb_Invoice WHERE ZNo = z.ZNo) b
    CROSS APPLY (SELECT COUNT(*) AS LineCount,
                        ISNULL(SUM(CASE WHEN i.InvType = 2 THEN -it.Qty ELSE it.Qty END), 0) AS TotalQty,
                        ISNULL(SUM(CASE WHEN i.InvType = 1 THEN it.Discount END), 0) AS ItemDiscount
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
-- Applies an item/price download. @ServerTime = serverTime from GET api/Sync/Items (next "since").
-- @Full = 1: a full download (no "since" - every item of the back office, active or not). An active till item
-- that is NOT in it was removed from the back office: it is set to Status 0 (kept for old bills, not sold again).
-- An empty full download changes nothing (a back office answering with no items must not switch the till off).
CREATE PROCEDURE dbo.zf_sp_UpsertItems
    @Items       dbo.zf_tt_Item READONLY,
    @ServerTime  DATETIME,
    @Full        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRAN;
        UPDATE t SET
            RefCode = s.RefCode, Barcode = s.Barcode, Descrip = s.Descrip, Inv_Descrip = s.Inv_Descrip,
            SinhalaDescrip = s.SinhalaDescrip, OpenPrice = s.OpenPrice, MaxPrice = s.MaxPrice,
            RetailPrice = s.RetailPrice, WholesalePrice = s.WholesalePrice, SpecialPrice = s.SpecialPrice,
            IsSaleLocked = s.IsSaleLocked, NoDiscount = s.NoDiscount,
            DiscountAmount = s.DiscountAmount, DiscountPercent = s.DiscountPercent,
            QtyLevel2 = s.QtyLevel2, PriceLevel2 = s.PriceLevel2, QtyLevel3 = s.QtyLevel3, PriceLevel3 = s.PriceLevel3,
            QtyLevel4 = s.QtyLevel4, PriceLevel4 = s.PriceLevel4, Status = s.Status, UDate = s.UDate,
            CostPrice = s.CostPrice, UnitCode = s.UnitCode
        FROM dbo.zf_tb_Item t JOIN @Items s ON s.ItemId = t.ItemId;

        INSERT dbo.zf_tb_Item (ItemId, RefCode, Barcode, Descrip, Inv_Descrip, SinhalaDescrip, OpenPrice, MaxPrice,
                               RetailPrice, WholesalePrice, SpecialPrice, IsSaleLocked, NoDiscount, DiscountAmount, DiscountPercent,
                               QtyLevel2, PriceLevel2, QtyLevel3, PriceLevel3, QtyLevel4, PriceLevel4, Status, UDate, CostPrice,
                               UnitCode)
        SELECT s.ItemId, s.RefCode, s.Barcode, s.Descrip, s.Inv_Descrip, s.SinhalaDescrip, s.OpenPrice, s.MaxPrice,
               s.RetailPrice, s.WholesalePrice, s.SpecialPrice, s.IsSaleLocked, s.NoDiscount, s.DiscountAmount, s.DiscountPercent,
               s.QtyLevel2, s.PriceLevel2, s.QtyLevel3, s.PriceLevel3, s.QtyLevel4, s.PriceLevel4, s.Status, s.UDate, s.CostPrice,
               s.UnitCode
        FROM @Items s WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Item t WHERE t.ItemId = s.ItemId);

        IF @Full = 1 AND EXISTS (SELECT 1 FROM @Items)
            UPDATE t SET Status = 0, UDate = @ServerTime
            FROM dbo.zf_tb_Item t
            WHERE t.Status <> 0 AND NOT EXISTS (SELECT 1 FROM @Items s WHERE s.ItemId = t.ItemId);

        UPDATE dbo.zf_tb_Config SET LastItemSyncAt = @ServerTime WHERE Id = 1;
    COMMIT;
END
GO
-- Applies a price link download. @ServerTime = serverTime from GET api/Sync/PriceLinks.
-- Deleted links arrive with Status 0 and stay as Status 0 (zf_sp_FindItem ignores them).
-- @Full = 1: a full download (no "since" - every ACTIVE link of this location). An active till link that is NOT in it
-- was deleted or removed in the back office: Status 0. An empty full download changes nothing.
CREATE PROCEDURE dbo.zf_sp_UpsertPriceLinks
    @Rows        dbo.zf_tt_PriceLink READONLY,
    @ServerTime  DATETIME,
    @Full        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRAN;
        UPDATE t SET ItemId = s.ItemId, RetailPrice = s.RetailPrice, WholesalePrice = s.WholesalePrice,
                     Remark = s.Remark, Status = s.Status, UDate = s.UDate, CostPrice = s.CostPrice
        FROM dbo.zf_tb_ItemPriceLink t JOIN @Rows s ON s.PriceLinkId = t.PriceLinkId;

        INSERT dbo.zf_tb_ItemPriceLink (PriceLinkId, ItemId, RetailPrice, WholesalePrice, Remark, Status, UDate, CostPrice)
        SELECT s.PriceLinkId, s.ItemId, s.RetailPrice, s.WholesalePrice, s.Remark, s.Status, s.UDate, s.CostPrice FROM @Rows s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_ItemPriceLink t WHERE t.PriceLinkId = s.PriceLinkId);

        IF @Full = 1 AND EXISTS (SELECT 1 FROM @Rows)
            UPDATE t SET Status = 0, UDate = @ServerTime
            FROM dbo.zf_tb_ItemPriceLink t
            WHERE t.Status <> 0 AND NOT EXISTS (SELECT 1 FROM @Rows s WHERE s.PriceLinkId = t.PriceLinkId);

        UPDATE dbo.zf_tb_Config SET LastPriceLinkSyncAt = @ServerTime WHERE Id = 1;
    COMMIT;
END
GO
SET NOEXEC OFF;
GO
PRINT 'U014_Till_ZDiscounts_FullReload done.';
GO
