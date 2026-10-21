/* =============================================================================
   U013_Till_ItemDiscount.sql   (2026-10-21)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Tables, items, bills, Z reports and cash data are not touched.

   What changes (item discount at billing - the old Tax2 / Tax3, back office U012):
     - NEW function zf_fn_UnitDiscount: the ONE rule - DiscountPercent first (price x % / 100), else DiscountAmount
       (Rs off each unit); never below cost (cut to price - cost); no cost known -> no discount
     - zf_fn_BillLineCost: new column MaxDiscount (0 for wholesale lines, open price items, other items).
       Profit = Amount - cost, Amount is after the item discount, so profit and the bill discount cap count it.
     - zf_sp_FindItem: UnitDiscount / UnitDiscount2..4 (at RetailPrice / PriceLevel2..4) and each price link's
       UnitDiscount - the page takes round(qty x unit discount, 2) off the line; the cost is not sent
     - zf_sp_SaveInvoice: a line discount < 0 or > the line -> 51016; on a sale more than MaxDiscount -> 51017
   Same change in the full script: 02_FrontCashier_zf.sql.

   No back office script for the till (the discounts come down with the items - run U012 on easyway first).
   On each till (the running TillService keeps working after it - it just gives no item discount):
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U013_Till_ItemDiscount.sql
     2. install the new TillService, then the new billing page (Lovable Prompt 63)
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_Item', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_sp_SaveInvoice', 'P') IS NULL
   OR COL_LENGTH('dbo.zf_tb_Item', 'DiscountPercent') IS NULL OR COL_LENGTH('dbo.zf_tb_ItemPriceLink', 'CostPrice') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_Item.DiscountPercent / zf_tb_ItemPriceLink.CostPrice / zf_sp_SaveInvoice not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.zf_sp_SaveInvoice', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_SaveInvoice;
IF OBJECT_ID(N'dbo.zf_sp_FindItem', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_FindItem;
IF OBJECT_ID(N'dbo.zf_fn_BillLineCost', 'IF') IS NOT NULL DROP FUNCTION dbo.zf_fn_BillLineCost;
IF OBJECT_ID(N'dbo.zf_fn_UnitDiscount', 'FN') IS NOT NULL DROP FUNCTION dbo.zf_fn_UnitDiscount;
GO
-- Item discount per unit - the ONE rule (2026-10-21), used by zf_sp_FindItem (what the billing page takes off)
-- and zf_fn_BillLineCost (what zf_sp_SaveInvoice allows):
--   DiscountPercent > 0 -> ROUND(price * % / 100, 2), else DiscountAmount (Rs off each unit), else 0;
--   never below cost: at most price - cost (cut to cost); no cost known (NULL / 0) -> no discount.
-- The line discount = ROUND(Qty * this, 2). Wholesale lines, open price items and other items get none.
CREATE FUNCTION dbo.zf_fn_UnitDiscount (@Price DECIMAL(18,2), @Percent DECIMAL(18,2), @Amount DECIMAL(18,2), @Cost DECIMAL(18,2))
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @d DECIMAL(18,2);
    IF ISNULL(@Price, 0) <= 0 OR ISNULL(@Cost, 0) <= 0 RETURN 0;
    SET @d = CASE WHEN @Percent > 0 THEN ROUND(@Price * @Percent / 100, 2) ELSE ISNULL(@Amount, 0) END;
    IF @d > @Price - @Cost SET @d = @Price - @Cost;
    IF @d < 0 SET @d = 0;
    RETURN @d;
END
GO
-- Cost and profit of each bill line - the ONE rule used by the profit view (zf_sp_GetBillProfit) and the
-- bill discount cap (zf_sp_SaveInvoice).
--   UnitCost: the picked price link's CostPrice, else the item's CostPrice (0 counts as unknown).
--   Profit = Amount - ROUND(Qty * UnitCost, 2); NULL when the cost is unknown (other items, items without a cost).
--   Amount is after the item discount, so the profit (and the bill discount cap) already counts it.
--   Unknown-cost lines add nothing to the bill profit, so they never allow a bigger discount.
--   InDiscountBase 0 = a NoDiscount item: a bill discount % is not taken off its amount.
--   MaxDiscount: the most item discount the line may have (zf_fn_UnitDiscount; 0 for wholesale / open price /
--   other items). A line without PriceType counts as retail.
CREATE FUNCTION dbo.zf_fn_BillLineCost (@Items dbo.zf_tt_InvoiceItem READONLY)
RETURNS TABLE
AS RETURN
    SELECT l.LineNum, l.ItemId, l.Qty, l.Amount, uc.UnitCost,
           CAST(ROUND(l.Qty * uc.UnitCost, 2) AS DECIMAL(18,2))            AS Cost,
           CAST(l.Amount - ROUND(l.Qty * uc.UnitCost, 2) AS DECIMAL(18,2)) AS Profit,
           CAST(CASE WHEN ISNULL(i.NoDiscount, 0) = 1 THEN 0 ELSE 1 END AS BIT) AS InDiscountBase,
           CASE WHEN i.MaxPrice > 0 THEN i.MaxPrice END                     AS MktPrice,
           CAST(CASE WHEN l.ItemId = 0 OR ISNULL(i.OpenPrice, 0) = 1 OR ISNULL(l.PriceType, 1) = 2 THEN 0
                     ELSE ROUND(l.Qty * dbo.zf_fn_UnitDiscount(l.UnitPrice, i.DiscountPercent, i.DiscountAmount, uc.UnitCost), 2)
                END AS DECIMAL(18,2))                                        AS MaxDiscount
    FROM @Items l
    LEFT JOIN dbo.zf_tb_Item i          ON i.ItemId = l.ItemId AND l.ItemId <> 0
    LEFT JOIN dbo.zf_tb_ItemPriceLink p ON p.PriceLinkId = l.PriceLinkId AND p.ItemId = l.ItemId
    CROSS APPLY (SELECT CAST(COALESCE(NULLIF(p.CostPrice, 0), NULLIF(i.CostPrice, 0)) AS DECIMAL(18,2)) AS UnitCost) uc;
GO
-- Barcode, then RefCode - or one item by @ItemId (picked from zf_sp_SearchItems). Active items only.
-- Scale sticker: when nothing matches and @Code is 10 digits, it is read as 5 digits scale code + 5 digits weight in
-- grams (1000801410 = RefCode 10008, 1.410 kg). Scale items (UnitCode KGS) only; the scale code is the RefCode padded
-- to 5 digits, same rule as the PLU in the scale export (05_BackOffice_Export.sql). Weight 00000 = not found.
-- 2 result sets: the item (with the last known stock, for display; ScaleQty = the sticker weight in kg, else NULL),
-- then its active price links (empty = sell at the normal / quantity price, no price choice).
-- Item discount per unit (zf_fn_UnitDiscount, already cut to cost - the cost itself is not sent to the page):
-- UnitDiscount at RetailPrice, UnitDiscount2/3/4 at PriceLevel2/3/4, and each price link's UnitDiscount at its
-- RetailPrice. Wholesale / open price: the page gives no item discount.
CREATE PROCEDURE dbo.zf_sp_FindItem
    @Code   NVARCHAR(50) = NULL,
    @ItemId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ScaleQty DECIMAL(18,3);

    IF @ItemId IS NOT NULL
        SET @ItemId = (SELECT ItemId FROM dbo.zf_tb_Item WHERE ItemId = @ItemId AND Status = 1);   -- NULL if inactive / missing
    ELSE
    BEGIN
        SELECT TOP 1 @ItemId = i.ItemId
        FROM dbo.zf_tb_Item i
        WHERE (i.Barcode = @Code OR i.RefCode = @Code) AND i.Status = 1
        ORDER BY CASE WHEN i.Barcode = @Code THEN 0 ELSE 1 END;

        IF @ItemId IS NULL AND LEN(@Code) = 10 AND @Code NOT LIKE N'%[^0-9]%' AND RIGHT(@Code, 5) <> N'00000'
        BEGIN
            SELECT TOP 1 @ItemId = i.ItemId
            FROM dbo.zf_tb_Item i
            WHERE i.UnitCode = 'KGS' AND i.Status = 1
              AND i.RefCode NOT LIKE N'%[^0-9]%' AND LEN(i.RefCode) BETWEEN 1 AND 5
              AND RIGHT(N'00000' + i.RefCode, 5) = LEFT(@Code, 5)
            ORDER BY i.ItemId;

            IF @ItemId IS NOT NULL
                SET @ScaleQty = CAST(RIGHT(@Code, 5) AS INT) / 1000.0;
        END
    END

    SELECT i.*, s.Qty AS StockQty, @ScaleQty AS ScaleQty,
           dbo.zf_fn_UnitDiscount(i.RetailPrice, i.DiscountPercent, i.DiscountAmount, i.CostPrice) AS UnitDiscount,
           dbo.zf_fn_UnitDiscount(i.PriceLevel2, i.DiscountPercent, i.DiscountAmount, i.CostPrice) AS UnitDiscount2,
           dbo.zf_fn_UnitDiscount(i.PriceLevel3, i.DiscountPercent, i.DiscountAmount, i.CostPrice) AS UnitDiscount3,
           dbo.zf_fn_UnitDiscount(i.PriceLevel4, i.DiscountPercent, i.DiscountAmount, i.CostPrice) AS UnitDiscount4
    FROM dbo.zf_tb_Item i
    LEFT JOIN dbo.zf_tb_StockBalance s ON s.ItemId = i.ItemId
    WHERE i.ItemId = @ItemId;

    -- link cost: the link's own, else the item's (same as zf_fn_BillLineCost)
    SELECT p.PriceLinkId, p.RetailPrice, p.WholesalePrice, p.Remark,
           dbo.zf_fn_UnitDiscount(p.RetailPrice, i.DiscountPercent, i.DiscountAmount,
                                  COALESCE(NULLIF(p.CostPrice, 0), NULLIF(i.CostPrice, 0))) AS UnitDiscount
    FROM dbo.zf_tb_ItemPriceLink p
    JOIN dbo.zf_tb_Item i ON i.ItemId = p.ItemId
    WHERE p.ItemId = @ItemId AND p.Status = 1
    ORDER BY p.RetailPrice;
END
GO
-- Saves a completed bill. Allocates the next invoice number and puts it in the open Z.
-- Line Amount = Qty * UnitPrice - Discount; NetAmount = SUM(Amount) - bill Discount (checked).
-- Sales (InvType 1): each line's UnitPrice must be one the till offers for that item -
--   open price item: any price;
--   otherwise: the quantity price for that Qty (bulk levels, see below), or an active price link's retail price;
--   wholesale LINE (line PriceType 2) also: the item's WholesalePrice (> 0) or a price link's WholesalePrice.
--   A retail line can never be charged a wholesale price. Each line has its own PriceType, so a retail bill
--   can have wholesale lines and the other way round; a line without one takes @PriceType.
--   The bill is stored as PriceType 2 when any line is wholesale (for reports).
-- Refunds are not price-checked: they give back what was charged, which may be an older price.
-- "Other item" lines (ItemId 0, item not in the list): any price above 0 with a typed LineDescrip.
--   They are not price-checked and the back office does not move stock for them.
-- Item (line) discount: never negative or more than the line (51016); on a sale never more than the item allows -
--   zf_fn_BillLineCost.MaxDiscount (51017). Less is fine (an older page sends 0). Refunds give back what was charged.
-- Bill discount (sales): never more than the bill's profit (zf_fn_BillLineCost) - 51012. Given as a % ->
--   @DiscountPercent is stored for the receipt and @Discount must be ROUND(base * % / 100, 2), base = the lines
--   that are not NoDiscount items. The billing page uses the SAME rule (GET the cap from POST /bill/profit).
CREATE PROCEDURE dbo.zf_sp_SaveInvoice
    @InvType      INT = 1,            -- 1 sale, 2 refund
    @PriceType    INT = 1,            -- default for lines that don't send their own PriceType (1 retail, 2 wholesale)
    @CashierId    VARCHAR(20) = NULL,
    @Discount     DECIMAL(18,2) = 0,  -- bill-level discount
    @Items        dbo.zf_tt_InvoiceItem READONLY,
    @Payments     dbo.zf_tt_InvoicePayment READONLY,
    @InvoiceNo    VARCHAR(30) = NULL OUTPUT,
    @DiscountPercent DECIMAL(5,2) = NULL   -- bill discount given as %; NULL = typed as an amount (or none)
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Seq INT, @TerminalCode VARCHAR(10), @ZNo INT, @Gross DECIMAL(18,2), @Net DECIMAL(18,2), @BillPriceType INT;
    DECLARE @Lines TABLE (LineNum INT PRIMARY KEY, UnitCost DECIMAL(18,2), Profit DECIMAL(18,2), InDiscountBase BIT, Amount DECIMAL(18,2), MktPrice DECIMAL(18,2),
                          MaxDiscount DECIMAL(18,2));

    IF @InvType NOT IN (1, 2)
        RAISERROR(N'%s', 16, 1, N'InvType must be 1 (sale) or 2 (refund).');
    IF @PriceType NOT IN (1, 2)
        RAISERROR(N'%s', 16, 1, N'PriceType must be 1 (retail) or 2 (wholesale).');
    IF EXISTS (SELECT 1 FROM @Items WHERE PriceType NOT IN (1, 2))
        RAISERROR(N'%s', 16, 1, N'Line PriceType must be 1 (retail) or 2 (wholesale).');
    IF NOT EXISTS (SELECT 1 FROM @Items)
        RAISERROR(N'%s', 16, 1, N'Bill has no items.');
    IF EXISTS (SELECT 1 FROM @Items WHERE Qty <= 0)
        RAISERROR(N'%s', 16, 1, N'Item quantity must be positive (use InvType 2 for refunds).');
    IF EXISTS (SELECT 1 FROM @Items WHERE Amount <> ROUND(Qty * UnitPrice, 2) - Discount)
        RAISERROR(N'%s', 16, 1, N'Line Amount must equal Qty * UnitPrice - Discount.');
    IF NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Config)
        RAISERROR(N'%s', 16, 1, N'Till is not set up (run zf_sp_SetupTerminal).');
    -- "other item" = an item that is not in the item list: ItemId 0, the cashier types the name and price
    IF EXISTS (SELECT 1 FROM @Items WHERE ItemId = 0 AND (LTRIM(RTRIM(ISNULL(LineDescrip, N''))) = N'' OR UnitPrice <= 0))
        RAISERROR(N'%s', 16, 1, N'Other item needs a description and a price above 0.');

    SELECT @Gross = SUM(ROUND(Qty * UnitPrice, 2)), @Net = SUM(Amount) - @Discount FROM @Items;
    -- bill type for reports: wholesale when any line is wholesale
    SET @BillPriceType = CASE WHEN EXISTS (SELECT 1 FROM @Items WHERE ISNULL(PriceType, @PriceType) = 2) THEN 2 ELSE 1 END;

    IF ISNULL((SELECT SUM(Amount) FROM @Payments), 0) <> @Net
        RAISERROR(N'%s', 16, 1, N'Payments must add up to the bill net amount.');
    IF EXISTS (SELECT 1 FROM @Payments WHERE Tendered < Amount)
        RAISERROR(N'%s', 16, 1, N'Cash tendered cannot be less than the amount paid.');

    INSERT @Lines (LineNum, UnitCost, Profit, InDiscountBase, Amount, MktPrice, MaxDiscount)
    SELECT LineNum, UnitCost, Profit, InDiscountBase, Amount, MktPrice, MaxDiscount FROM dbo.zf_fn_BillLineCost(@Items);

    IF EXISTS (SELECT 1 FROM @Items WHERE Discount < 0 OR Discount > ROUND(Qty * UnitPrice, 2))
        RAISERROR(N'%s', 16, 1, N'Item discount cannot be negative or more than the line.');
    IF @InvType = 1
    BEGIN
        DECLARE @DiscItem NVARCHAR(200);
        SELECT TOP 1 @DiscItem = ISNULL(i.Inv_Descrip, i.Descrip)
        FROM @Items it
        JOIN @Lines c ON c.LineNum = it.LineNum
        LEFT JOIN dbo.zf_tb_Item i ON i.ItemId = it.ItemId
        WHERE it.Discount > c.MaxDiscount;
        IF @@ROWCOUNT > 0
        BEGIN
            DECLARE @DiscItemMsg NVARCHAR(400) = N'Item discount of ' + ISNULL(@DiscItem, N'an item')
                                               + N' has changed. Remove the line and scan it again.';
            RAISERROR(N'%s', 16, 1, @DiscItemMsg);
        END
    END

    IF @Discount < 0
        RAISERROR(N'%s', 16, 1, N'Bill discount cannot be negative.');
    IF @DiscountPercent IS NOT NULL
    BEGIN
        IF @DiscountPercent <= 0 OR @DiscountPercent > 100
            RAISERROR(N'%s', 16, 1, N'Discount percent must be above 0 and at most 100.');
        IF @Discount <> ROUND(ISNULL((SELECT SUM(Amount) FROM @Lines WHERE InDiscountBase = 1), 0) * @DiscountPercent / 100, 2)
            RAISERROR(N'%s', 16, 1, N'Bill discount does not match the discount percent of the bill. Enter the discount again.');
    END
    IF @InvType = 1 AND @Discount > 0
    BEGIN
        DECLARE @MaxDiscount DECIMAL(18,2) = ISNULL((SELECT SUM(ISNULL(Profit, 0)) FROM @Lines), 0);
        IF @MaxDiscount < 0 SET @MaxDiscount = 0;
        IF @Discount > @MaxDiscount
        BEGIN
            DECLARE @DiscMsg NVARCHAR(200) = N'Discount is more than this bill allows (max Rs ' + CONVERT(NVARCHAR(30), @MaxDiscount) + N').';
            RAISERROR(N'%s', 16, 1, @DiscMsg);
        END
    END

    IF @InvType = 1
    BEGIN
        DECLARE @BadItem NVARCHAR(200), @Msg NVARCHAR(400);

        SELECT TOP 1 @BadItem = CAST(l.ItemId AS NVARCHAR(20))
        FROM @Items l WHERE l.ItemId <> 0 AND NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Item i WHERE i.ItemId = l.ItemId);
        IF @BadItem IS NOT NULL
        BEGIN
            SET @Msg = N'Item ' + @BadItem + N' is not on this till. Scan it again.';
            RAISERROR(N'%s', 16, 1, @Msg);
        END

        -- Quantity price: the level with the highest MinQty that Qty reaches (MinQty and Price both > 0);
        -- none reached -> RetailPrice. The billing page uses the SAME rule - change both together.
        SELECT TOP 1 @BadItem = ISNULL(i.Inv_Descrip, i.Descrip)
        FROM @Items l
        JOIN dbo.zf_tb_Item i ON i.ItemId = l.ItemId
        OUTER APPLY (
            SELECT TOP 1 v.Price
            FROM (VALUES (i.QtyLevel2, i.PriceLevel2), (i.QtyLevel3, i.PriceLevel3), (i.QtyLevel4, i.PriceLevel4)) v (MinQty, Price)
            WHERE v.MinQty > 0 AND v.Price > 0 AND l.Qty >= v.MinQty
            ORDER BY v.MinQty DESC
        ) q
        -- ISNULLs keep every test TRUE/FALSE: a NULL price must never let a line through.
        WHERE i.OpenPrice = 0
          AND l.UnitPrice <> ISNULL(q.Price, ISNULL(i.RetailPrice, -1))
          AND NOT (ISNULL(l.PriceType, @PriceType) = 2 AND ISNULL(i.WholesalePrice, 0) > 0 AND l.UnitPrice = ISNULL(i.WholesalePrice, 0))
          AND NOT EXISTS (SELECT 1 FROM dbo.zf_tb_ItemPriceLink p
                          WHERE p.ItemId = l.ItemId AND p.Status = 1
                            AND (p.RetailPrice = l.UnitPrice OR (ISNULL(l.PriceType, @PriceType) = 2 AND p.WholesalePrice = l.UnitPrice)));
        IF @BadItem IS NOT NULL
        BEGIN
            SET @Msg = N'Price of ' + @BadItem + N' has changed. Remove the line and scan it again.';
            RAISERROR(N'%s', 16, 1, @Msg);
        END
    END

    BEGIN TRAN;
        EXEC dbo.zf_sp_OpenZ @CashierId = @CashierId, @ZNo = @ZNo OUTPUT, @Silent = 1;

        UPDATE dbo.zf_tb_Config
        SET @Seq = LastInvoiceSeq = LastInvoiceSeq + 1, @TerminalCode = TerminalCode
        WHERE Id = 1;

        SET @InvoiceNo = @TerminalCode + '-' + RIGHT('00000000' + CAST(@Seq AS VARCHAR(10)), 8);

        INSERT dbo.zf_tb_Invoice (InvoiceNo, InvoiceSeq, ZNo, InvType, InvDate, CashierId, GrossAmount, Discount, NetAmount, Status, PriceType, DiscountPercent)
        VALUES (@InvoiceNo, @Seq, @ZNo, @InvType, GETDATE(), @CashierId, @Gross, @Discount, @Net, 1, @BillPriceType, @DiscountPercent);

        INSERT dbo.zf_tb_InvoiceItem (InvoiceNo, LineNum, ItemId, Qty, UnitPrice, Discount, Amount, LineDescrip, PriceType,
                                      PriceLinkId, UnitCost, MktPrice)
        SELECT @InvoiceNo, it.LineNum, it.ItemId, it.Qty, it.UnitPrice, it.Discount, it.Amount,
               CASE WHEN it.ItemId = 0 THEN LTRIM(RTRIM(it.LineDescrip)) END,   -- real items keep their name in zf_tb_Item
               ISNULL(it.PriceType, @PriceType),
               it.PriceLinkId, c.UnitCost, c.MktPrice
        FROM @Items it
        JOIN @Lines c ON c.LineNum = it.LineNum;

        INSERT dbo.zf_tb_InvoicePayment (InvoiceNo, LineNum, PayType, Amount, RefNo, Tendered)
        SELECT @InvoiceNo, LineNum, PayType, Amount, RefNo, Tendered FROM @Payments;

        UPDATE dbo.zf_tb_ZReport SET FromSeq = ISNULL(FromSeq, @Seq), ToSeq = @Seq WHERE ZNo = @ZNo;
    COMMIT;
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
PRINT 'U013_Till_ItemDiscount done.';
GO
