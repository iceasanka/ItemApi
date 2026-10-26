/* =============================================================================
   U021_BackOffice_DayReportProfit.sql   (2026-10-26)
   Update for a back office db (easyway) that is ALREADY deployed (U018 run). SQL Server 2008 R2 and newer.
   Safe to run again. No table or data change.

   What changes (back office Day Reports page, Docs/StockSystem.md 6.25): profit on the Items and Bills tabs.
     - z_sp_DayReportItems: new columns Cost, Profit, UncostedQty
     - z_sp_DayReportBills: new columns Cost, Profit, UncostedLines
   Profit = the sales dashboard rule (z_fn_SalesLines): unit cost = TillUnitCost, else CostPrice, else the item's
   cost now (0 = unknown); line amount less its share of the bill discount - Qty x cost; refunds negative.
   Lines without a cost are left out (NULL = no line has a cost). Voided bills: no profit.
   Same change in the full script: 21_BackOffice_DayReports.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U021_BackOffice_DayReportProfit.sql
   Then: the new ItemApi and the back office UI. The old ItemApi keeps working after it (extra columns not read).
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_SalesInvoice', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_ItemDet', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_SalesInvoice / z_tb_ItemDet not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.z_sp_DayReportItems', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportItems;
IF OBJECT_ID(N'dbo.z_sp_DayReportBills', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportBills;
GO
-- Every item sold / refunded that day, voided bills left out. Refunds count negative in Net*.
-- Amount = the line amounts (after the item discount, before the bill discount - that is on the bill only).
-- Other items (ItemId 0, not in the item list) are one row per name the cashier typed.
-- Cost / Profit: the sales dashboard rule (z_fn_SalesLines, 04_BackOffice_SalesDashboard.sql) - unit cost = TillUnitCost,
-- else CostPrice, else the item's cost now (0 = unknown); profit = amount less its share of the bill discount - Qty x cost.
-- Lines without a cost are not in Cost / Profit (NULL = no line of the row has a cost); UncostedQty = their net qty.
CREATE PROCEDURE dbo.z_sp_DayReportItems
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME, @To DATETIME;
    SET @From = @Date;
    SET @To = DATEADD(DAY, 1, @From);

    SELECT x.ItemId, i.RefCode, i.Barcode,
           CASE WHEN x.ItemId = 0 THEN ISNULL(x.LineDescrip, N'Other item') ELSE ISNULL(i.Inv_Descrip, i.Descrip) END AS Name,
           CAST(CASE WHEN x.ItemId = 0 THEN 1 ELSE 0 END AS BIT) AS IsOther,
           x.SoldQty, x.RefundQty, x.SoldQty - x.RefundQty AS NetQty,
           x.SoldAmount, x.RefundAmount, x.SoldAmount - x.RefundAmount AS NetAmount,
           x.Discount, x.Bills, x.MinPrice, x.MaxPrice,
           x.Cost, x.Profit, x.UncostedQty
    FROM (SELECT it.ItemId, CASE WHEN it.ItemId = 0 THEN it.LineDescrip END AS LineDescrip,
                 CAST(SUM(CASE WHEN s.InvType = 1 THEN it.Qty ELSE 0 END) AS DECIMAL(18,3)) AS SoldQty,
                 CAST(SUM(CASE WHEN s.InvType = 2 THEN it.Qty ELSE 0 END) AS DECIMAL(18,3)) AS RefundQty,
                 CAST(SUM(CASE WHEN s.InvType = 1 THEN it.Amount ELSE 0 END) AS DECIMAL(18,2)) AS SoldAmount,
                 CAST(SUM(CASE WHEN s.InvType = 2 THEN it.Amount ELSE 0 END) AS DECIMAL(18,2)) AS RefundAmount,
                 CAST(SUM(CASE WHEN s.InvType = 1 THEN it.Discount ELSE -it.Discount END) AS DECIMAL(18,2)) AS Discount,
                 COUNT(DISTINCT s.InvoiceId) AS Bills,
                 MIN(it.UnitPrice) AS MinPrice, MAX(it.UnitPrice) AS MaxPrice,
                 CAST(SUM(sg.Sign * it.Qty * c.UnitCost) AS DECIMAL(18,2)) AS Cost,
                 CAST(SUM(CASE WHEN c.UnitCost IS NOT NULL
                               THEN sg.Sign * (it.Amount * (1 - f.DiscShare) - it.Qty * c.UnitCost) END) AS DECIMAL(18,2)) AS Profit,
                 CAST(SUM(CASE WHEN c.UnitCost IS NULL THEN sg.Sign * it.Qty ELSE 0 END) AS DECIMAL(18,3)) AS UncostedQty
          FROM dbo.z_tb_SalesInvoice s
          JOIN dbo.z_tb_SalesInvoiceItem it ON it.InvoiceId = s.InvoiceId
          LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = it.ItemId AND d.LocationId = s.LocationId AND it.ItemId <> 0
          CROSS APPLY (SELECT CASE WHEN s.InvType = 2 THEN -1 ELSE 1 END AS Sign) sg
          CROSS APPLY (SELECT CASE WHEN s.NetAmount + s.Discount = 0 THEN CAST(0 AS DECIMAL(18,8))
                                   ELSE CAST(s.Discount AS DECIMAL(18,8)) / (s.NetAmount + s.Discount) END AS DiscShare) f
          CROSS APPLY (SELECT COALESCE(NULLIF(it.TillUnitCost, 0), NULLIF(it.CostPrice, 0), NULLIF(d.CostPrice, 0)) AS UnitCost) c
          WHERE s.InvDate >= @From AND s.InvDate < @To AND s.LocationId = @LocationId AND s.Status <> 9
            AND (@TerminalId IS NULL OR s.TerminalId = @TerminalId)
          GROUP BY it.ItemId, CASE WHEN it.ItemId = 0 THEN it.LineDescrip END) x
    LEFT JOIN dbo.z_tb_Item i ON i.ItemId = x.ItemId AND x.ItemId <> 0
    ORDER BY x.SoldAmount - x.RefundAmount DESC, Name;
END
GO
-- Every bill of the day (voided ones too, Status 9), newest first, with how it was paid.
-- Cost / Profit as z_sp_DayReportItems (refund bills negative, after the bill discount); NULL = no line has a cost,
-- and always NULL on a voided bill. UncostedLines = lines left out of Cost / Profit (other items, items without a cost).
CREATE PROCEDURE dbo.z_sp_DayReportBills
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME, @To DATETIME;
    SET @From = @Date;
    SET @To = DATEADD(DAY, 1, @From);

    SELECT s.InvoiceId, s.InvoiceNo, s.TerminalId, t.TerminalCode, s.ZNo, s.InvType, s.InvDate, s.CashierId,
           u.UserName AS CashierName, s.GrossAmount, s.Discount, s.NetAmount, s.Status, s.PriceType,
           (SELECT COUNT(*) FROM dbo.z_tb_SalesInvoiceItem it WHERE it.InvoiceId = s.InvoiceId) AS Lines,
           ISNULL((SELECT SUM(it.Discount) FROM dbo.z_tb_SalesInvoiceItem it WHERE it.InvoiceId = s.InvoiceId), 0) AS ItemDiscount,
           ISNULL((SELECT SUM(p.Amount) FROM dbo.z_tb_SalesPayment p WHERE p.InvoiceId = s.InvoiceId AND p.PayType = 1), 0) AS Cash,
           ISNULL((SELECT SUM(p.Amount) FROM dbo.z_tb_SalesPayment p WHERE p.InvoiceId = s.InvoiceId AND p.PayType = 2), 0) AS Card,
           ISNULL((SELECT SUM(p.Amount) FROM dbo.z_tb_SalesPayment p WHERE p.InvoiceId = s.InvoiceId AND p.PayType NOT IN (1, 2)), 0) AS OtherPay,
           CASE WHEN s.Status <> 9 THEN CAST(sg.Sign * pr.CostSum AS DECIMAL(18,2)) END AS Cost,
           CASE WHEN s.Status <> 9 THEN CAST(sg.Sign * (pr.CostedAmount * (1 - sg.DiscShare) - pr.CostSum) AS DECIMAL(18,2)) END AS Profit,
           CASE WHEN s.Status <> 9 THEN ISNULL(pr.UncostedLines, 0) ELSE 0 END AS UncostedLines
    FROM dbo.z_tb_SalesInvoice s
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = s.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = s.CashierId
    CROSS APPLY (SELECT CASE WHEN s.InvType = 2 THEN -1 ELSE 1 END AS Sign,
                        CASE WHEN s.NetAmount + s.Discount = 0 THEN CAST(0 AS DECIMAL(18,8))
                             ELSE CAST(s.Discount AS DECIMAL(18,8)) / (s.NetAmount + s.Discount) END AS DiscShare) sg
    -- line totals only (an aggregate cannot mix the bill's columns with the line's); sign and bill discount above
    OUTER APPLY (SELECT SUM(it.Qty * c.UnitCost) AS CostSum,
                        SUM(CASE WHEN c.UnitCost IS NOT NULL THEN it.Amount END) AS CostedAmount,
                        SUM(CASE WHEN c.UnitCost IS NULL THEN 1 ELSE 0 END) AS UncostedLines
                 FROM dbo.z_tb_SalesInvoiceItem it
                 LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = it.ItemId AND d.LocationId = s.LocationId AND it.ItemId <> 0
                 CROSS APPLY (SELECT COALESCE(NULLIF(it.TillUnitCost, 0), NULLIF(it.CostPrice, 0), NULLIF(d.CostPrice, 0)) AS UnitCost) c
                 WHERE it.InvoiceId = s.InvoiceId) pr
    WHERE s.InvDate >= @From AND s.InvDate < @To AND s.LocationId = @LocationId
      AND (@TerminalId IS NULL OR s.TerminalId = @TerminalId)
    ORDER BY s.InvDate DESC, s.InvoiceId DESC;
END
GO
SET NOEXEC OFF;
GO
PRINT 'U021 back office: day report profit (z_sp_DayReportItems, z_sp_DayReportBills).';
GO
