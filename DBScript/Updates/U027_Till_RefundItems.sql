/* =============================================================================
   U027_Till_RefundItems.sql   (2026-10-29)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. No table changes; bills, Z reports and logs are not changed.

   What changes (one simple refund on the billing page):
     - zf_sp_SaveInvoice takes refund lines on a sale: Refund on, the items brought back are scanned (no receipt),
       Refund off, the new items are sold - one bill. Refund lines are minus lines (Qty, Discount, Amount < 0,
       RefLineNum NULL), price-checked like sold lines. The bill can't come to less than 0 and has no bill discount.
       Only refund lines is still a refund bill (InvType 2, plus lines, paid back by cash / card).
     - The back office needs nothing: minus lines already come up with exchanges (stock goes back in).
   Same change in the full script: 02_FrontCashier_zf.sql.

   Order, on each till:
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U027_Till_RefundItems.sql
     2. install the new TillService (asks the supervisor PIN for refund lines) and the new billing page
        (the old ones keep working after the script)
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
IF COL_LENGTH('dbo.zf_tb_InvoiceItem', 'InDiscBase') IS NULL
BEGIN
    RAISERROR('Run U023_Till_Settings.sql first - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
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
-- Refund lines on a sale (U027, Refund on the billing page, no receipt): Qty, Discount and Amount minus, RefLineNum
--   NULL. Price-checked like a sold line (its Qty without the minus picks the quantity price), the item discount
--   (minus) never more than the item allows. No bill discount on such a bill. The bill can't come to less than 0 -
--   only refund lines is a refund bill (InvType 2). InDiscBase NULL (like exchange lines).
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
    -- minus = a refund line, on a sale only (a refund bill's lines are plus)
    IF EXISTS (SELECT 1 FROM @Items WHERE Qty = 0 OR (Qty < 0 AND @InvType <> 1))
        RAISERROR(N'%s', 16, 1, N'Item quantity must be positive (use InvType 2 for refunds).');
    IF @InvType = 1 AND @Discount <> 0 AND EXISTS (SELECT 1 FROM @Items WHERE Qty < 0)
        RAISERROR(N'%s', 16, 1, N'No bill discount on a bill with refund items.');
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
    IF @ExchangeRef IS NULL AND @InvType = 1 AND @Net < 0
        RAISERROR(N'%s', 16, 1, N'The refund items are worth more than the items sold - add items, or refund them on their own.');
    IF @ExchangeRef IS NULL AND ISNULL((SELECT SUM(Amount) FROM @Payments), 0) <> @Net
        RAISERROR(N'%s', 16, 1, N'Payments must add up to the bill net amount.');
    IF EXISTS (SELECT 1 FROM @Payments WHERE Tendered < Amount)
        RAISERROR(N'%s', 16, 1, N'Cash tendered cannot be less than the amount paid.');

    INSERT @Lines (LineNum, UnitCost, Profit, InDiscountBase, Amount, MktPrice, MaxDiscount)
    SELECT LineNum, UnitCost, Profit, InDiscountBase, Amount, MktPrice, MaxDiscount FROM dbo.zf_fn_BillLineCost(@Items);

    -- a refund line's discount is minus like its Qty
    IF EXISTS (SELECT 1 FROM @Items WHERE (Qty > 0 AND Discount < 0) OR (Qty < 0 AND Discount > 0)
                                       OR ABS(Discount) > ABS(ROUND(Qty * UnitPrice, 2)))
        RAISERROR(N'%s', 16, 1, N'Item discount cannot be negative or more than the line.');
    IF @InvType = 1
    BEGIN
        DECLARE @DiscItem NVARCHAR(200);
        SELECT TOP 1 @DiscItem = ISNULL(i.Inv_Descrip, i.Descrip)
        FROM @Items it
        JOIN @Lines c ON c.LineNum = it.LineNum
        LEFT JOIN dbo.zf_tb_Item i ON i.ItemId = it.ItemId
        WHERE ABS(it.Discount) > ABS(c.MaxDiscount);   -- refund lines: both minus
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
            WHERE v.MinQty > 0 AND v.Price > 0 AND ABS(l.Qty) >= v.MinQty
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
               it.PriceLinkId, c.UnitCost, c.MktPrice, CASE WHEN @InvType = 1 AND it.Qty > 0 THEN c.InDiscountBase END
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


PRINT 'U027_Till_RefundItems done.';
GO
