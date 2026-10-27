/* =============================================================================
   U023_Till_Settings.sql   (2026-10-27)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Bills, Z reports and logs are not changed (two new, empty tables and one new column).

   What changes (settings from the back office, bill discount rule, Docs/StockSystem.md 6.28):
     - tables zf_tb_Setting (general values) and zf_tb_UserSetting (a user's own values): a copy of the back office
       Settings page, downloaded by TillService (api/Sync/Settings) and replaced as a whole each time
     - type zf_tt_Setting, procedures zf_sp_SaveSettings (download) and zf_sp_GetSettings (GET /settings)
     - setting Till.BillDiscSkipItemDisc = 1: the bill discount is not taken off lines that already have an item
       discount (like NoDiscount items) - zf_fn_BillLineCost.InDiscountBase, so the billing page (POST /bill/profit)
       and the check in zf_sp_SaveInvoice use the same base. Off (or not downloaded yet) = as before.
     - zf_tb_InvoiceItem.InDiscBase: each sale line keeps whether the bill discount was taken off it.
       zf_sp_SaveBillRefund and an exchange (zf_sp_SaveInvoice) give back the bill discount of those lines only
       (before: of every line, NoDiscount items too). Bills saved before this have NULL = every line, as before.
     - zf_sp_GetBillProfit also returns LeftOutLines (lines the bill discount is not taken off)
   Same change in the full script: 02_FrontCashier_zf.sql.

   Order: U023_BackOffice_Settings.sql + the new ItemApi first, then on each till:
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U023_Till_Settings.sql
     2. install the new TillService and the new billing page (the old ones keep working after the script; the
        settings come down only with the new TillService)
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
IF COL_LENGTH('dbo.zf_tb_InvoiceItem', 'RefBillDiscount') IS NULL
BEGIN
    RAISERROR('Run U020_Till_Exchange.sql first - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. tables
-- A copy of the back office z_tb_Setting / z_tb_UserSetting, the whole list replaced on every download
-- (zf_sp_SaveSettings). zf_tb_Setting.Value = the general value (its default when none is set); zf_tb_UserSetting =
-- a user's own value, used instead of the general one (zf_sp_GetSettings).
IF OBJECT_ID(N'dbo.zf_tb_Setting', 'U') IS NULL
CREATE TABLE dbo.zf_tb_Setting (
    SettingKey VARCHAR(50)   NOT NULL CONSTRAINT PK_zf_tb_Setting PRIMARY KEY,
    Value      NVARCHAR(200) NULL,
    SyncedAt   DATETIME      NOT NULL CONSTRAINT DF_zf_tb_Setting_SyncedAt DEFAULT (GETDATE())
);
GO
IF OBJECT_ID(N'dbo.zf_tb_UserSetting', 'U') IS NULL
CREATE TABLE dbo.zf_tb_UserSetting (
    LoginName  VARCHAR(50)   NOT NULL,
    SettingKey VARCHAR(50)   NOT NULL,
    Value      NVARCHAR(200) NOT NULL,
    CONSTRAINT PK_zf_tb_UserSetting PRIMARY KEY (LoginName, SettingKey)
);
GO
-- Sale lines: 1 = the bill discount was taken off this line, 0 = it was not (NoDiscount item, or an item discount
-- while Till.BillDiscSkipItemDisc is on). NULL = saved before this change (counts as 1) or a minus line.
IF COL_LENGTH('dbo.zf_tb_InvoiceItem', 'InDiscBase') IS NULL
    ALTER TABLE dbo.zf_tb_InvoiceItem ADD InDiscBase BIT NULL;
GO

-- 2. type (dropped with its procs)
IF OBJECT_ID(N'dbo.zf_sp_SaveSettings', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_SaveSettings;
GO
IF TYPE_ID(N'dbo.zf_tt_Setting') IS NOT NULL DROP TYPE dbo.zf_tt_Setting;
GO
-- LoginName NULL = the general value, else that user's own value
CREATE TYPE dbo.zf_tt_Setting AS TABLE (
    LoginName  VARCHAR(50)   NULL,
    SettingKey VARCHAR(50)   NOT NULL,
    Value      NVARCHAR(200) NULL
);
GO

-- 3. function and procedures (same as 02_FrontCashier_zf.sql)
IF OBJECT_ID(N'dbo.zf_fn_BillLineCost', 'IF') IS NOT NULL DROP FUNCTION dbo.zf_fn_BillLineCost;
GO
-- Cost and profit of each bill line - the ONE rule used by the profit view (zf_sp_GetBillProfit) and the
-- bill discount cap (zf_sp_SaveInvoice).
--   UnitCost: the picked price link's CostPrice, else the item's CostPrice (0 counts as unknown).
--   Profit = Amount - ROUND(Qty * UnitCost, 2); NULL when the cost is unknown (other items, items without a cost).
--   Amount is after the item discount, so the profit (and the bill discount cap) already counts it.
--   Unknown-cost lines add nothing to the bill profit, so they never allow a bigger discount.
--   InDiscountBase 0 = the bill discount is not taken off this line: a NoDiscount item, or (setting
--   Till.BillDiscSkipItemDisc = 1) a line that already has an item discount.
--   MaxDiscount: the most item discount the line may have (zf_fn_UnitDiscount; 0 for wholesale / open price /
--   other items). A line without PriceType counts as retail.
CREATE FUNCTION dbo.zf_fn_BillLineCost (@Items dbo.zf_tt_InvoiceItem READONLY)
RETURNS TABLE
AS RETURN
    SELECT l.LineNum, l.ItemId, l.Qty, l.Amount, uc.UnitCost,
           CAST(ROUND(l.Qty * uc.UnitCost, 2) AS DECIMAL(18,2))            AS Cost,
           CAST(l.Amount - ROUND(l.Qty * uc.UnitCost, 2) AS DECIMAL(18,2)) AS Profit,
           CAST(CASE WHEN ISNULL(i.NoDiscount, 0) = 1 THEN 0
                     WHEN l.Discount > 0 AND EXISTS (SELECT 1 FROM dbo.zf_tb_Setting s
                                                     WHERE s.SettingKey = 'Till.BillDiscSkipItemDisc' AND s.Value = N'1') THEN 0
                     ELSE 1 END AS BIT)                                     AS InDiscountBase,
           CASE WHEN i.MaxPrice > 0 THEN i.MaxPrice END                     AS MktPrice,
           CAST(CASE WHEN l.ItemId = 0 OR ISNULL(i.OpenPrice, 0) = 1 OR ISNULL(l.PriceType, 1) = 2 THEN 0
                     ELSE ROUND(l.Qty * dbo.zf_fn_UnitDiscount(l.UnitPrice, i.DiscountPercent, i.DiscountAmount, uc.UnitCost), 2)
                END AS DECIMAL(18,2))                                        AS MaxDiscount
    FROM @Items l
    LEFT JOIN dbo.zf_tb_Item i          ON i.ItemId = l.ItemId AND l.ItemId <> 0
    LEFT JOIN dbo.zf_tb_ItemPriceLink p ON p.PriceLinkId = l.PriceLinkId AND p.ItemId = l.ItemId
    CROSS APPLY (SELECT CAST(COALESCE(NULLIF(p.CostPrice, 0), NULLIF(i.CostPrice, 0)) AS DECIMAL(18,2)) AS UnitCost) uc;
GO

IF OBJECT_ID(N'dbo.zf_sp_SaveInvoice', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_SaveInvoice;
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
--   with InDiscountBase 1 (not NoDiscount items; with Till.BillDiscSkipItemDisc on, no item discount either).
--   The billing page uses the SAME rule (GET the cap from POST /bill/profit). Each sale line keeps it (InDiscBase),
--   so a later refund / exchange gives back the bill discount of those lines only.
CREATE PROCEDURE dbo.zf_sp_SaveInvoice
    @InvType      INT = 1,            -- 1 sale, 2 refund
    @PriceType    INT = 1,            -- default for lines that don't send their own PriceType (1 retail, 2 wholesale)
    @CashierId    VARCHAR(20) = NULL,
    @Discount     DECIMAL(18,2) = 0,  -- bill-level discount
    @Items        dbo.zf_tt_InvoiceItem READONLY,
    @Payments     dbo.zf_tt_InvoicePayment READONLY,
    @InvoiceNo    VARCHAR(30) = NULL OUTPUT,
    @DiscountPercent DECIMAL(5,2) = NULL,  -- bill discount given as %; NULL = typed as an amount (or none)
    -- Exchange (2026-10-26, sale only): items brought back from an earlier bill of this till go on THIS bill as
    -- minus lines - one bill, one number. Only which lines and how much come in; price and discounts are taken
    -- from that bill exactly like zf_sp_SaveBillRefund (never more than is left on a line, its share of that
    -- bill's discount). The payments pay the new items less the items brought back.
    @ExchangeRef  VARCHAR(30) = NULL,
    @Exchange     dbo.zf_tt_RefundLine READONLY
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Seq INT, @TerminalCode VARCHAR(10), @ZNo INT, @Gross DECIMAL(18,2), @Net DECIMAL(18,2), @BillPriceType INT;
    DECLARE @Lines TABLE (LineNum INT PRIMARY KEY, UnitCost DECIMAL(18,2), Profit DECIMAL(18,2), InDiscountBase BIT, Amount DECIMAL(18,2), MktPrice DECIMAL(18,2),
                          MaxDiscount DECIMAL(18,2));
    -- exchange lines (positive here, saved as minus lines)
    DECLARE @X TABLE (Seq INT PRIMARY KEY, RefLineNum INT NOT NULL, ItemId INT, Qty DECIMAL(18,3), UnitPrice DECIMAL(18,2),
                      LineDisc DECIMAL(18,2), Amount DECIMAL(18,2), BillShare DECIMAL(18,2) NOT NULL DEFAULT (0),
                      LineDescrip NVARCHAR(50), PriceType INT, PriceLinkId INT, UnitCost DECIMAL(18,2), MktPrice DECIMAL(18,2),
                      InBase BIT NOT NULL DEFAULT (1));
    DECLARE @RefType INT, @RefStatus INT, @RefDiscount DECIMAL(18,2), @RefLines DECIMAL(18,2), @RefBack DECIMAL(18,2),
            @XSub DECIMAL(18,2), @XBase DECIMAL(18,2), @XBill DECIMAL(18,2), @XAllBack BIT, @XMsg NVARCHAR(400), @LastLine INT;

    IF @InvType NOT IN (1, 2)
        RAISERROR(N'%s', 16, 1, N'InvType must be 1 (sale) or 2 (refund).');
    IF @ExchangeRef IS NULL AND EXISTS (SELECT 1 FROM @Exchange)
        RAISERROR(N'%s', 16, 1, N'Exchange lines need the bill they come from.');
    IF @ExchangeRef IS NOT NULL AND (@InvType <> 1 OR NOT EXISTS (SELECT 1 FROM @Exchange))
        RAISERROR(N'%s', 16, 1, N'An exchange is a sale with at least one line brought back.');
    IF EXISTS (SELECT 1 FROM @Exchange WHERE Qty <= 0)
        RAISERROR(N'%s', 16, 1, N'Refund quantity must be above 0.');
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

    -- an exchange is checked after the lines brought back are worked out (in the transaction below)
    IF @ExchangeRef IS NULL AND ISNULL((SELECT SUM(Amount) FROM @Payments), 0) <> @Net
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
        IF @ExchangeRef IS NOT NULL
        BEGIN
            -- the old bill stays locked until this bill is saved (same rules as zf_sp_SaveBillRefund)
            SELECT @RefType = InvType, @RefStatus = Status, @RefDiscount = Discount
            FROM dbo.zf_tb_Invoice WITH (UPDLOCK, HOLDLOCK) WHERE InvoiceNo = @ExchangeRef;

            IF @RefType IS NULL
                RAISERROR(N'%s', 16, 1, N'Bill not found on this till.');
            IF @RefType <> 1
                RAISERROR(N'%s', 16, 1, N'This is a refund bill - it cannot be refunded.');
            IF @RefStatus <> 1
                RAISERROR(N'%s', 16, 1, N'This bill was voided - it cannot be refunded.');
            IF EXISTS (SELECT 1 FROM @Exchange l
                       WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_InvoiceItem it
                                         WHERE it.InvoiceNo = @ExchangeRef AND it.LineNum = l.RefLineNum AND it.Qty > 0))
                RAISERROR(N'%s', 16, 1, N'A picked line is not on this bill. Scan the bill again.');

            SELECT TOP 1 @XMsg = COALESCE(it.LineDescrip, m.Inv_Descrip, m.Descrip, N'Line ' + CAST(it.LineNum AS NVARCHAR(10)))
                   + CASE WHEN it.Qty - ISNULL(d.Qty, 0) <= 0 THEN N' was already refunded in full.'
                          ELSE N': only ' + CONVERT(NVARCHAR(30), CAST(it.Qty - ISNULL(d.Qty, 0) AS DECIMAL(18,3)))
                               + N' left to refund (sold ' + CONVERT(NVARCHAR(30), it.Qty)
                               + N', already refunded ' + CONVERT(NVARCHAR(30), CAST(ISNULL(d.Qty, 0) AS DECIMAL(18,3))) + N').' END
            FROM @Exchange l
            JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = @ExchangeRef AND it.LineNum = l.RefLineNum
            LEFT JOIN dbo.zf_fn_RefundDone(@ExchangeRef) d ON d.LineNum = it.LineNum
            LEFT JOIN dbo.zf_tb_Item m ON m.ItemId = it.ItemId AND it.ItemId <> 0
            WHERE l.Qty > it.Qty - ISNULL(d.Qty, 0)
            ORDER BY l.RefLineNum;
            IF @XMsg IS NOT NULL
                RAISERROR(N'%s', 16, 1, @XMsg);

            -- line discount in proportion to the qty (the last part of a line takes what is left of it)
            INSERT @X (Seq, RefLineNum, ItemId, Qty, UnitPrice, LineDisc, Amount, LineDescrip, PriceType, PriceLinkId, UnitCost, MktPrice, InBase)
            SELECT ROW_NUMBER() OVER (ORDER BY l.RefLineNum), l.RefLineNum, it.ItemId, l.Qty, it.UnitPrice, x.Discount,
                   ROUND(l.Qty * it.UnitPrice, 2) - x.Discount, CASE WHEN it.ItemId = 0 THEN it.LineDescrip END,
                   it.PriceType, it.PriceLinkId, it.UnitCost, it.MktPrice, ISNULL(it.InDiscBase, 1)
            FROM @Exchange l
            JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = @ExchangeRef AND it.LineNum = l.RefLineNum
            LEFT JOIN dbo.zf_fn_RefundDone(@ExchangeRef) d ON d.LineNum = it.LineNum
            CROSS APPLY (SELECT CAST(CASE WHEN l.Qty < it.Qty - ISNULL(d.Qty, 0) THEN ROUND(it.Discount * l.Qty / it.Qty, 2)
                                          WHEN it.Discount > ISNULL(d.Discount, 0) THEN it.Discount - ISNULL(d.Discount, 0)
                                          ELSE 0 END AS DECIMAL(18,2)) AS Discount) x;

            -- the old bill's discount: in proportion to the lines brought back that it was taken off (InDiscBase);
            -- the last of the bill takes what is left
            SELECT @XSub = SUM(Amount), @XBase = SUM(CASE WHEN InBase = 1 THEN Amount ELSE 0 END) FROM @X;
            SELECT @RefLines = SUM(Amount) FROM dbo.zf_tb_InvoiceItem
            WHERE InvoiceNo = @ExchangeRef AND Qty > 0 AND ISNULL(InDiscBase, 1) = 1;
            IF ISNULL(@RefLines, 0) <= 0   -- no line in the base (a discount typed as an amount): all lines share it
            BEGIN
                SELECT @RefLines = SUM(Amount) FROM dbo.zf_tb_InvoiceItem WHERE InvoiceNo = @ExchangeRef AND Qty > 0;
                UPDATE @X SET InBase = 1;
                SET @XBase = @XSub;
            END
            SELECT @RefBack = Amount FROM dbo.zf_fn_RefundBillDiscountBack(@ExchangeRef);
            SET @XAllBack = CASE WHEN EXISTS (SELECT 1 FROM dbo.zf_tb_InvoiceItem it
                                              LEFT JOIN dbo.zf_fn_RefundDone(@ExchangeRef) d ON d.LineNum = it.LineNum
                                              LEFT JOIN @Exchange l ON l.RefLineNum = it.LineNum
                                              WHERE it.InvoiceNo = @ExchangeRef AND it.Qty > 0
                                                AND it.Qty - ISNULL(d.Qty, 0) - ISNULL(l.Qty, 0) > 0)
                                 THEN 0 ELSE 1 END;
            SET @XBill = CASE WHEN @RefDiscount <= 0 OR @RefLines <= 0 THEN 0
                              WHEN @XAllBack = 1 THEN @RefDiscount - @RefBack
                              ELSE ROUND(@RefDiscount * @XBase / @RefLines, 2) END;
            IF @XBill < 0 SET @XBill = 0;
            IF @XBill > @XBase SET @XBill = @XBase;
            -- spread over those lines (it goes into each minus line's Discount; the last one takes the rounding)
            IF @XBill > 0 AND @XBase > 0
            BEGIN
                UPDATE @X SET BillShare = ROUND(@XBill * Amount / @XBase, 2) WHERE InBase = 1;
                UPDATE @X SET BillShare = @XBill - ISNULL((SELECT SUM(BillShare) FROM @X
                                                           WHERE InBase = 1 AND Seq < (SELECT MAX(Seq) FROM @X WHERE InBase = 1)), 0)
                WHERE Seq = (SELECT MAX(Seq) FROM @X WHERE InBase = 1);
            END

            SET @Gross = @Gross - ISNULL((SELECT SUM(ROUND(Qty * UnitPrice, 2)) FROM @X), 0);
            SET @Net = @Net - (@XSub - @XBill);
            IF @Net < 0
                RAISERROR(N'%s', 16, 1, N'The items brought back are worth more than the new items - add items, or refund them by cash / card.');
            IF ISNULL((SELECT SUM(Amount) FROM @Payments), 0) <> @Net
                RAISERROR(N'%s', 16, 1, N'Payments must add up to the bill net amount.');
        END

        EXEC dbo.zf_sp_OpenZ @CashierId = @CashierId, @ZNo = @ZNo OUTPUT, @Silent = 1;

        UPDATE dbo.zf_tb_Config
        SET @Seq = LastInvoiceSeq = LastInvoiceSeq + 1, @TerminalCode = TerminalCode
        WHERE Id = 1;

        SET @InvoiceNo = @TerminalCode + '-' + RIGHT('00000000' + CAST(@Seq AS VARCHAR(10)), 8);

        INSERT dbo.zf_tb_Invoice (InvoiceNo, InvoiceSeq, ZNo, InvType, InvDate, CashierId, GrossAmount, Discount, NetAmount, Status, PriceType, DiscountPercent, RefInvoiceNo)
        VALUES (@InvoiceNo, @Seq, @ZNo, @InvType, GETDATE(), @CashierId, @Gross, @Discount, @Net, 1, @BillPriceType, @DiscountPercent, @ExchangeRef);

        INSERT dbo.zf_tb_InvoiceItem (InvoiceNo, LineNum, ItemId, Qty, UnitPrice, Discount, Amount, LineDescrip, PriceType,
                                      PriceLinkId, UnitCost, MktPrice, InDiscBase)
        SELECT @InvoiceNo, it.LineNum, it.ItemId, it.Qty, it.UnitPrice, it.Discount, it.Amount,
               CASE WHEN it.ItemId = 0 THEN LTRIM(RTRIM(it.LineDescrip)) END,   -- real items keep their name in zf_tb_Item
               ISNULL(it.PriceType, @PriceType),
               it.PriceLinkId, c.UnitCost, c.MktPrice, CASE WHEN @InvType = 1 THEN c.InDiscountBase END
        FROM @Items it
        JOIN @Lines c ON c.LineNum = it.LineNum;

        -- exchange: the items brought back, as minus lines after the new items (cost / MRP of the old bill)
        SELECT @LastLine = ISNULL(MAX(LineNum), 0) FROM @Items;
        INSERT dbo.zf_tb_InvoiceItem (InvoiceNo, LineNum, ItemId, Qty, UnitPrice, Discount, Amount, LineDescrip, PriceType,
                                      PriceLinkId, UnitCost, MktPrice, RefLineNum, RefBillDiscount)
        SELECT @InvoiceNo, @LastLine + x.Seq, x.ItemId, -x.Qty, x.UnitPrice, -(x.LineDisc + x.BillShare), -(x.Amount - x.BillShare),
               x.LineDescrip, x.PriceType, x.PriceLinkId, x.UnitCost, x.MktPrice, x.RefLineNum, x.BillShare
        FROM @X x;

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

IF OBJECT_ID(N'dbo.zf_sp_GetBillProfit', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetBillProfit;
GO
-- Profit view and discount cap for the bill on the screen (TillService POST /bill/profit, supervisor PIN only).
-- Same rule as zf_sp_SaveInvoice (zf_fn_BillLineCost). 2 result sets:
--   lines:  LineNum, UnitCost, Cost, Profit (NULL = cost unknown)
--   totals: Amount, Cost, Profit (known lines only), UnknownCostLines, DiscountBase,
--           LeftOutLines (lines the bill discount is not taken off: NoDiscount items, item discount lines when
--           Till.BillDiscSkipItemDisc is on), MaxDiscount (= profit, never below 0),
--           MaxDiscountPercent (of DiscountBase, rounded DOWN to 2 decimals)
CREATE PROCEDURE dbo.zf_sp_GetBillProfit
    @Items dbo.zf_tt_InvoiceItem READONLY
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @c TABLE (LineNum INT PRIMARY KEY, Amount DECIMAL(18,2), UnitCost DECIMAL(18,2), Cost DECIMAL(18,2),
                      Profit DECIMAL(18,2), InDiscountBase BIT);
    INSERT @c SELECT LineNum, Amount, UnitCost, Cost, Profit, InDiscountBase FROM dbo.zf_fn_BillLineCost(@Items);

    SELECT LineNum, UnitCost, Cost, Profit FROM @c ORDER BY LineNum;

    DECLARE @Profit DECIMAL(18,2) = ISNULL((SELECT SUM(ISNULL(Profit, 0)) FROM @c), 0),
            @Base   DECIMAL(18,2) = ISNULL((SELECT SUM(Amount) FROM @c WHERE InDiscountBase = 1), 0);
    DECLARE @Max DECIMAL(18,2) = CASE WHEN @Profit > 0 THEN @Profit ELSE 0 END;

    SELECT ISNULL((SELECT SUM(Amount) FROM @c), 0)                    AS Amount,
           ISNULL((SELECT SUM(Cost) FROM @c WHERE Cost IS NOT NULL), 0) AS Cost,
           @Profit                                                     AS Profit,
           (SELECT COUNT(*) FROM @c WHERE UnitCost IS NULL)            AS UnknownCostLines,
           @Base                                                       AS DiscountBase,
           (SELECT COUNT(*) FROM @c WHERE InDiscountBase = 0)          AS LeftOutLines,
           @Max                                                        AS MaxDiscount,
           CAST(CASE WHEN @Base > 0 AND @Max < @Base THEN FLOOR(@Max * 10000 / @Base) / 100
                     WHEN @Base > 0 THEN 100 ELSE 0 END AS DECIMAL(5,2)) AS MaxDiscountPercent;
END
GO

IF OBJECT_ID(N'dbo.zf_sp_SaveBillRefund', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_SaveBillRefund;
GO
-- Refund against the original bill. The page sends only WHICH lines and HOW MUCH of each (@Lines); the price,
-- the discounts and the amount come from the sale bill, never from the page.
--   - Only a completed sale bill of THIS till. A line can never give back more than was sold on it minus what
--     earlier refunds of the same bill already gave back (51066) - no PIN lifts that.
--   - Line: the sale's UnitPrice; its line discount in proportion to the quantity (the last part of a line takes
--     what is left of the discount).
--   - Bill discount of the sale: given back in proportion to the refunded line amounts, of the lines it was taken
--     off only (InDiscBase - not NoDiscount items or, with Till.BillDiscSkipItemDisc, item discount lines); the
--     refund that brings the last of the bill back takes what is left, so the refunds of a bill add up to what the
--     customer paid.
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
            @Sub DECIMAL(18,2), @SubBase DECIMAL(18,2), @Discount DECIMAL(18,2), @Net DECIMAL(18,2), @GivenBack DECIMAL(18,2), @AllBack BIT,
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
                   WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_InvoiceItem it
                                     WHERE it.InvoiceNo = @RefInvoiceNo AND it.LineNum = l.RefLineNum AND it.Qty > 0))
            RAISERROR(N'%s', 16, 1, N'A picked line is not on this bill. Scan the bill again.');

        -- refund bills AND exchanges (items brought back on a later sale) count as given back
        INSERT @Done (LineNum, Qty, Discount)
        SELECT LineNum, Qty, Discount FROM dbo.zf_fn_RefundDone(@RefInvoiceNo);

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

        -- the bill discount comes back only with the lines it was taken off (InDiscBase; NULL = older bill, all lines)
        SELECT @Sub = SUM(i.Amount), @SubBase = SUM(CASE WHEN ISNULL(it.InDiscBase, 1) = 1 THEN i.Amount ELSE 0 END)
        FROM @Items i
        JOIN @Map mp ON mp.LineNum = i.LineNum
        JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = @RefInvoiceNo AND it.LineNum = mp.RefLineNum;
        SELECT @BillLines = SUM(Amount) FROM dbo.zf_tb_InvoiceItem
        WHERE InvoiceNo = @RefInvoiceNo AND Qty > 0 AND ISNULL(InDiscBase, 1) = 1;
        IF ISNULL(@BillLines, 0) <= 0   -- no line in the base (a discount typed as an amount): all lines share it
        BEGIN
            SELECT @BillLines = SUM(Amount) FROM dbo.zf_tb_InvoiceItem WHERE InvoiceNo = @RefInvoiceNo AND Qty > 0;
            SET @SubBase = @Sub;
        END
        SELECT @GivenBack = Amount FROM dbo.zf_fn_RefundBillDiscountBack(@RefInvoiceNo);
        SET @AllBack = CASE WHEN EXISTS (SELECT 1 FROM dbo.zf_tb_InvoiceItem it
                                         LEFT JOIN @Done d ON d.LineNum = it.LineNum
                                         LEFT JOIN @Lines l ON l.RefLineNum = it.LineNum
                                         WHERE it.InvoiceNo = @RefInvoiceNo AND it.Qty > 0
                                           AND it.Qty - ISNULL(d.Qty, 0) - ISNULL(l.Qty, 0) > 0)
                            THEN 0 ELSE 1 END;

        SET @Discount = CASE WHEN @BillDiscount <= 0 OR @BillLines <= 0 THEN 0
                             WHEN @AllBack = 1 THEN @BillDiscount - @GivenBack
                             ELSE ROUND(@BillDiscount * @SubBase / @BillLines, 2) END;
        IF @Discount < 0 SET @Discount = 0;
        IF @Discount > @SubBase SET @Discount = @SubBase;
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

IF OBJECT_ID(N'dbo.zf_sp_SaveSettings', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_SaveSettings;
GO
-- Replaces the till's copy with the downloaded list (general values and every user's own values).
CREATE PROCEDURE dbo.zf_sp_SaveSettings
    @Rows dbo.zf_tt_Setting READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRAN;
        DELETE dbo.zf_tb_Setting;
        DELETE dbo.zf_tb_UserSetting;

        INSERT dbo.zf_tb_Setting (SettingKey, Value)
        SELECT SettingKey, MAX(Value) FROM @Rows WHERE LoginName IS NULL GROUP BY SettingKey;

        INSERT dbo.zf_tb_UserSetting (LoginName, SettingKey, Value)
        SELECT LoginName, SettingKey, MAX(Value) FROM @Rows
        WHERE LoginName IS NOT NULL AND Value IS NOT NULL
        GROUP BY LoginName, SettingKey;
    COMMIT;
END
GO

IF OBJECT_ID(N'dbo.zf_sp_GetSettings', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetSettings;
GO
-- The settings for one user (@LoginName NULL = the general values): the user's own value, else the general one.
-- Columns: SettingKey, Value, Own (1 = the user's own value).
CREATE PROCEDURE dbo.zf_sp_GetSettings
    @LoginName VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.SettingKey, COALESCE(u.Value, s.Value) AS Value,
           CAST(CASE WHEN u.Value IS NULL THEN 0 ELSE 1 END AS BIT) AS Own
    FROM dbo.zf_tb_Setting s
    LEFT JOIN dbo.zf_tb_UserSetting u ON u.SettingKey = s.SettingKey AND u.LoginName = LTRIM(RTRIM(@LoginName))
    ORDER BY s.SettingKey;
END
GO

PRINT 'U023_Till_Settings done.';
GO
