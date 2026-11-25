/* =============================================================================
   U075_BackOffice_DiscountReport.sql   (2026-11-25)
   Update for a back office db (easyway) that is ALREADY deployed; the same as the full script 46_BackOffice_DiscountReport.sql - change both together.
   SQL Server 2008 R2 and newer. Safe to run again. No table or column change; data changes only when a user presses
   Clear discount (z_tb_ItemDet.DiscountPercent / DiscountAmount of the ticked items).
     sqlcmd -S <server> -d easyway -E -I -b -i U075_BackOffice_DiscountReport.sql
   Then: the new ItemApi (api/Report/Discount...) and the back office UI of 2026-11-25. The old ItemApi keeps working.

   Back office > Reports > Discount items:
     z_sp_RptDiscountItems   one row per item sold with a discount from @FromDate to @ToDate (both included):
                             item discount (line Discount) and its share of the bill discount (bill Discount spread
                             over the lines by amount, as z_fn_SalesLines), gross, net, cost, profit, bills; + the
                             discount set on the item now. Only the discounted lines are added up; AllQty = every
                             line of the item in the range (to see how much of it went with a discount).
                             Refund bills negative, voided bills left out. ItemId 0 = "other items" (typed on the till).
     z_sp_RptDiscountLines   the discounted lines of one item in the range (bill, date, till, cashier, qty, price,
                             item / bill discount, net), newest first.
     z_sp_RptDiscountSetup   active items with a discount set (DiscountPercent / DiscountAmount) or marked "no
                             discount": price, cost, the discount the till gives per unit (% first, else Rs; never
                             more than price - cost, 0 when the cost is not known - as zf_fn_UnitDiscount), stock.
     z_sp_RptDiscountClear   Clear discount: DiscountPercent / DiscountAmount of the ticked items to NULL, UDate = now
                             (tills take it at the next item sync); returns the old values.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_SalesInvoice', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_SalesInvoiceItem', 'U') IS NULL
   OR COL_LENGTH('dbo.z_tb_SalesInvoiceItem', 'TillUnitCost') IS NULL OR COL_LENGTH('dbo.z_tb_ItemDet', 'DiscountPercent') IS NULL
   OR TYPE_ID(N'dbo.z_tt_IdList') IS NULL
BEGIN
    RAISERROR('Sales (with the till cost) / item discounts are not in this database (run U003 / the sales dashboard update first) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF OBJECT_ID('dbo.z_sp_RptDiscountItems', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_RptDiscountItems;
IF OBJECT_ID('dbo.z_sp_RptDiscountLines', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_RptDiscountLines;
IF OBJECT_ID('dbo.z_sp_RptDiscountSetup', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_RptDiscountSetup;
IF OBJECT_ID('dbo.z_sp_RptDiscountClear', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_RptDiscountClear;
GO

-- Items sold with a discount (item discount or a share of a bill discount), one row per item, biggest discount first.
CREATE PROCEDURE dbo.z_sp_RptDiscountItems
    @FromDate DATE, @ToDate DATE, @LocationId INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME, @To DATETIME;
    SET @From = @FromDate;
    SET @To = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME));

    SELECT g.ItemId, i.RefCode, i.Barcode,
           CAST(CASE WHEN g.ItemId = 0 THEN N'(other items typed on the till)' ELSE i.Descrip END AS NVARCHAR(200)) AS Descrip,
           c.CatName, su.SuppName,
           g.Bills, CAST(g.Qty AS DECIMAL(18,3)) AS Qty, CAST(g.AllQty AS DECIMAL(18,3)) AS AllQty,
           CAST(g.Gross AS DECIMAL(18,2)) AS Gross,
           CAST(g.ItemDisc AS DECIMAL(18,2)) AS ItemDisc, CAST(g.BillDisc AS DECIMAL(18,2)) AS BillDisc,
           CAST(g.ItemDisc + g.BillDisc AS DECIMAL(18,2)) AS TotalDisc,
           CAST(g.Gross - g.ItemDisc - g.BillDisc AS DECIMAL(18,2)) AS Net,
           CAST(g.Cost AS DECIMAL(18,2)) AS Cost,
           CAST(CASE WHEN g.Cost IS NULL THEN NULL ELSE g.Gross - g.ItemDisc - g.BillDisc - g.Cost END AS DECIMAL(18,2)) AS Profit,
           CAST(CASE WHEN g.Gross <> 0 THEN (g.ItemDisc + g.BillDisc) * 100 / g.Gross ELSE 0 END AS DECIMAL(9,2)) AS DiscPct,
           CAST(d.RetailPrice AS DECIMAL(18,2)) AS RetailPrice,
           CAST(NULLIF(d.DiscountPercent, 0) AS DECIMAL(18,2)) AS SetPercent,
           CAST(NULLIF(d.DiscountAmount, 0) AS DECIMAL(18,2)) AS SetAmount,
           CAST(ISNULL(d.NoDiscount, 0) AS BIT) AS NoDiscount
    FROM (
        -- one pass over the lines; only the discounted lines (Disc 1) are added up, AllQty = every line
        SELECT it.ItemId,
               COUNT(DISTINCT CASE WHEN x.Disc = 1 AND s.InvType <> 2 THEN s.InvoiceId END) AS Bills,
               SUM(x.Disc * sg.Sign * it.Qty) AS Qty,
               SUM(sg.Sign * it.Qty) AS AllQty,
               SUM(x.Disc * sg.Sign * (it.Amount + it.Discount)) AS Gross,
               SUM(x.Disc * sg.Sign * it.Discount) AS ItemDisc,
               SUM(x.Disc * sg.Sign * it.Amount * f.DiscShare) AS BillDisc,
               -- NULL when the cost of a discounted line is not known (profit not shown)
               CASE WHEN SUM(CASE WHEN x.Disc = 1 AND c.UnitCost IS NULL THEN 1 ELSE 0 END) = 0
                    THEN SUM(x.Disc * sg.Sign * it.Qty * ISNULL(c.UnitCost, 0)) END AS Cost
        FROM dbo.z_tb_SalesInvoice s
        JOIN dbo.z_tb_SalesInvoiceItem it ON it.InvoiceId = s.InvoiceId
        LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = it.ItemId AND d.LocationId = s.LocationId AND it.ItemId <> 0
        CROSS APPLY (SELECT CASE WHEN s.InvType = 2 THEN -1 ELSE 1 END AS Sign) sg
        CROSS APPLY (SELECT CASE WHEN it.Discount <> 0 OR (s.Discount <> 0 AND it.Amount <> 0) THEN 1 ELSE 0 END AS Disc) x
        CROSS APPLY (SELECT CASE WHEN s.NetAmount + s.Discount = 0 THEN CAST(0 AS DECIMAL(18,8))
                                 ELSE CAST(s.Discount AS DECIMAL(18,8)) / (s.NetAmount + s.Discount) END AS DiscShare) f
        CROSS APPLY (SELECT COALESCE(NULLIF(it.TillUnitCost, 0), NULLIF(it.CostPrice, 0), NULLIF(d.CostPrice, 0)) AS UnitCost) c
        WHERE s.InvDate >= @From AND s.InvDate < @To AND s.Status <> 9 AND s.LocationId = @LocationId
        GROUP BY it.ItemId
    ) g
    LEFT JOIN dbo.z_tb_Item i      ON i.ItemId = g.ItemId AND g.ItemId <> 0
    LEFT JOIN dbo.z_tb_ItemDet d   ON d.ItemId = g.ItemId AND d.LocationId = @LocationId AND g.ItemId <> 0
    LEFT JOIN dbo.z_tb_Category c  ON c.CatId = i.CatId
    LEFT JOIN dbo.z_tb_Supplier su ON su.SuppId = i.SupId
    WHERE g.ItemDisc <> 0 OR g.BillDisc <> 0
    ORDER BY g.ItemDisc + g.BillDisc DESC, i.Descrip;
END
GO

-- The discounted lines of one item (@ItemId 0 = other items) from @FromDate to @ToDate, newest first.
CREATE PROCEDURE dbo.z_sp_RptDiscountLines
    @FromDate DATE, @ToDate DATE, @ItemId INT, @LocationId INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME, @To DATETIME;
    SET @From = @FromDate;
    SET @To = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME));

    SELECT s.InvoiceId, s.InvoiceNo, s.InvType, s.InvDate, t.TerminalCode, s.CashierId,
           CAST(ISNULL(u.UserName, s.CashierId) AS NVARCHAR(100)) AS CashierName, it.LineNum, it.LineDescrip,
           CAST(sg.Sign * it.Qty AS DECIMAL(18,3)) AS Qty, it.UnitPrice,
           CAST(sg.Sign * (it.Amount + it.Discount) AS DECIMAL(18,2)) AS Gross,
           CAST(sg.Sign * it.Discount AS DECIMAL(18,2)) AS ItemDisc,
           CAST(sg.Sign * it.Amount * f.DiscShare AS DECIMAL(18,2)) AS BillDisc,
           CAST(sg.Sign * it.Amount * (1 - f.DiscShare) AS DECIMAL(18,2)) AS Net,
           s.Discount AS BillDiscount, s.NetAmount AS BillNet
    FROM dbo.z_tb_SalesInvoice s
    JOIN dbo.z_tb_SalesInvoiceItem it ON it.InvoiceId = s.InvoiceId
    LEFT JOIN dbo.z_tb_Terminal t ON t.TerminalId = s.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = s.CashierId
    CROSS APPLY (SELECT CASE WHEN s.InvType = 2 THEN -1 ELSE 1 END AS Sign) sg
    CROSS APPLY (SELECT CASE WHEN s.NetAmount + s.Discount = 0 THEN CAST(0 AS DECIMAL(18,8))
                             ELSE CAST(s.Discount AS DECIMAL(18,8)) / (s.NetAmount + s.Discount) END AS DiscShare) f
    WHERE s.InvDate >= @From AND s.InvDate < @To AND s.Status <> 9 AND s.LocationId = @LocationId
      AND it.ItemId = @ItemId
      AND (it.Discount <> 0 OR (s.Discount <> 0 AND it.Amount <> 0))
    ORDER BY s.InvDate DESC, s.InvoiceId DESC, it.LineNum;
END
GO

-- Active items with a discount set now (or marked no discount), with what the till gives per unit.
CREATE PROCEDURE dbo.z_sp_RptDiscountSetup
    @LocationId INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SELECT i.ItemId, i.RefCode, i.Barcode, i.Descrip, c.CatName, su.SuppName,
           CAST(ISNULL(d.RetailPrice, 0) AS DECIMAL(18,2)) AS RetailPrice,
           CAST(NULLIF(d.CostPrice, 0) AS DECIMAL(18,2)) AS CostPrice,
           CAST(NULLIF(d.DiscountPercent, 0) AS DECIMAL(18,2)) AS SetPercent,
           CAST(NULLIF(d.DiscountAmount, 0) AS DECIMAL(18,2)) AS SetAmount,
           CAST(ISNULL(d.NoDiscount, 0) AS BIT) AS NoDiscount,
           CAST(x.UnitDisc AS DECIMAL(18,2)) AS UnitDisc,
           CAST(ISNULL(d.RetailPrice, 0) - x.UnitDisc AS DECIMAL(18,2)) AS PriceAfter,
           CAST(CASE WHEN w.Want > x.UnitDisc THEN 1 ELSE 0 END AS BIT) AS Capped,
           CAST(ISNULL(b.Qty, 0) AS DECIMAL(18,3)) AS StockQty,
           CAST(CASE WHEN CASE WHEN d.UDate > i.UDate THEN d.UDate ELSE i.UDate END < '19000101' THEN NULL
                     WHEN d.UDate > i.UDate THEN d.UDate ELSE i.UDate END AS DATETIME) AS Edited
    FROM dbo.z_tb_Item i
    JOIN dbo.z_tb_ItemDet d ON d.ItemId = i.ItemId AND d.LocationId = @LocationId
    LEFT JOIN dbo.z_tb_StockBalance b ON b.ItemId = i.ItemId AND b.LocationId = @LocationId
    LEFT JOIN dbo.z_tb_Category c ON c.CatId = i.CatId
    LEFT JOIN dbo.z_tb_Supplier su ON su.SuppId = i.SupId
    -- as zf_fn_UnitDiscount on the till: % first, else Rs; not more than price - cost; 0 without a price / cost
    CROSS APPLY (SELECT CAST(CASE WHEN ISNULL(d.RetailPrice, 0) <= 0 OR ISNULL(d.CostPrice, 0) <= 0 OR ISNULL(d.NoDiscount, 0) = 1 THEN 0
                                  WHEN d.DiscountPercent > 0 THEN ROUND(d.RetailPrice * d.DiscountPercent / 100, 2)
                                  ELSE ISNULL(d.DiscountAmount, 0) END AS DECIMAL(18,2)) AS Want) w
    CROSS APPLY (SELECT CASE WHEN w.Want > d.RetailPrice - d.CostPrice
                             THEN CASE WHEN d.RetailPrice - d.CostPrice < 0 THEN 0 ELSE d.RetailPrice - d.CostPrice END
                             ELSE w.Want END AS UnitDisc) x
    WHERE i.Status = 1
      AND (d.DiscountPercent > 0 OR d.DiscountAmount > 0 OR d.NoDiscount = 1)
    ORDER BY i.Descrip;
END
GO

-- Clear the discount (DiscountPercent and DiscountAmount to NULL) of the ticked items. UDate = now, so the tills take
-- the change at the next item sync. "No discount" is not touched. Returns the items changed with their old values
-- (ItemApi writes them to its log, to put back by hand if needed).
CREATE PROCEDURE dbo.z_sp_RptDiscountClear
    @Ids dbo.z_tt_IdList READONLY, @LocationId INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @old TABLE (ItemId INT, OldPercent DECIMAL(18,2), OldAmount DECIMAL(18,2));

    UPDATE d SET DiscountPercent = NULL, DiscountAmount = NULL, UDate = SYSDATETIME()
    OUTPUT deleted.ItemId, deleted.DiscountPercent, deleted.DiscountAmount INTO @old
    FROM dbo.z_tb_ItemDet d JOIN @Ids x ON x.Id = d.ItemId
    WHERE d.LocationId = @LocationId AND (d.DiscountPercent IS NOT NULL OR d.DiscountAmount IS NOT NULL);

    SELECT ItemId, OldPercent, OldAmount FROM @old ORDER BY ItemId;
END
GO

SET NOEXEC OFF;
GO
PRINT 'U075 done: z_sp_RptDiscountItems, z_sp_RptDiscountLines, z_sp_RptDiscountSetup, z_sp_RptDiscountClear.';
GO
