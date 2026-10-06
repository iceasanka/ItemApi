/* =============================================================================
   04_BackOffice_SalesDashboard.sql
   Run on: back office db (easyway), AFTER 01_BackOffice_Stock.sql. Prefix z_. Re-runnable.
   Sales + profit for the home page (today, live) and the sales analysis screen (date range, charts).
   API: api/Dashboard/Today, api/Dashboard/Sales (DashboardController). Docs/StockSystem.md §6.9.

   Numbers come from the bills the tills uploaded (z_tb_SalesInvoice*). Rules — one place, z_fn_SalesLines:
     - voided bills (Status 9) are left out; refunds (InvType 2) count negative
     - line net = line Amount less its share of the bill discount (bill discount spread by line amount)
     - unit cost = the till's cost (TillUnitCost), else AvgCost at upload (CostPrice), else the item's cost now
       (z_tb_ItemDet.CostPrice); 0 counts as unknown
     - profit = net − Qty × cost, only for lines with a known cost. Sales of lines without a cost (other items,
       items with no cost) are shown apart as UncostedSales and are NOT in Profit or Margin.
   easyway is at compatibility level 100 (SQL 2008): no IIF / FORMAT / CONCAT.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.z_sp_DashTotals', 'P')     IS NOT NULL DROP PROCEDURE dbo.z_sp_DashTotals;
IF OBJECT_ID('dbo.z_sp_DashDaily', 'P')      IS NOT NULL DROP PROCEDURE dbo.z_sp_DashDaily;
IF OBJECT_ID('dbo.z_sp_DashTerminals', 'P')  IS NOT NULL DROP PROCEDURE dbo.z_sp_DashTerminals;
IF OBJECT_ID('dbo.z_sp_DashHourly', 'P')     IS NOT NULL DROP PROCEDURE dbo.z_sp_DashHourly;
IF OBJECT_ID('dbo.z_sp_DashTopItems', 'P')   IS NOT NULL DROP PROCEDURE dbo.z_sp_DashTopItems;
IF OBJECT_ID('dbo.z_sp_DashCategories', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DashCategories;
IF OBJECT_ID('dbo.z_fn_SalesLines', 'IF')    IS NOT NULL DROP FUNCTION dbo.z_fn_SalesLines;
GO

-- Every sold / refunded line between @From (incl.) and @To (excl.), signed, with net, cost and profit.
CREATE FUNCTION dbo.z_fn_SalesLines (@From DATETIME, @To DATETIME, @LocationId INT, @TerminalId INT)
RETURNS TABLE
AS RETURN
    SELECT s.InvoiceId, s.TerminalId, CAST(s.InvDate AS DATE) AS SaleDate, DATEPART(HOUR, s.InvDate) AS SaleHour,
           it.ItemId, i.CatId,
           sg.Sign * it.Qty                                                       AS Qty,
           CAST(sg.Sign * it.Amount * (1 - f.DiscShare) AS DECIMAL(18,4))         AS NetAmount,
           c.UnitCost,
           CAST(sg.Sign * it.Qty * c.UnitCost AS DECIMAL(18,4))                   AS Cost,     -- NULL = unknown
           CAST(sg.Sign * (it.Amount * (1 - f.DiscShare) - it.Qty * c.UnitCost) AS DECIMAL(18,4)) AS Profit
    FROM dbo.z_tb_SalesInvoice s
    JOIN dbo.z_tb_SalesInvoiceItem it ON it.InvoiceId = s.InvoiceId
    LEFT JOIN dbo.z_tb_Item i    ON i.ItemId = it.ItemId AND it.ItemId <> 0
    LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = it.ItemId AND d.LocationId = s.LocationId AND it.ItemId <> 0
    CROSS APPLY (SELECT CASE WHEN s.InvType = 2 THEN -1 ELSE 1 END AS Sign) sg
    CROSS APPLY (SELECT CASE WHEN s.NetAmount + s.Discount = 0 THEN CAST(0 AS DECIMAL(18,8))
                             ELSE CAST(s.Discount AS DECIMAL(18,8)) / (s.NetAmount + s.Discount) END AS DiscShare) f
    CROSS APPLY (SELECT COALESCE(NULLIF(it.TillUnitCost, 0), NULLIF(it.CostPrice, 0), NULLIF(d.CostPrice, 0)) AS UnitCost) c
    WHERE s.InvDate >= @From AND s.InvDate < @To
      AND s.Status <> 9
      AND s.LocationId = @LocationId
      AND (@TerminalId IS NULL OR s.TerminalId = @TerminalId);
GO

-- Totals for @FromDate..@ToDate (both days included). One row.
CREATE PROCEDURE dbo.z_sp_DashTotals
    @FromDate DATE, @ToDate DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME = @FromDate, @To DATETIME = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME));

    DECLARE @l TABLE (Qty DECIMAL(18,3), NetAmount DECIMAL(18,4), Cost DECIMAL(18,4), Profit DECIMAL(18,4));
    INSERT @l SELECT Qty, NetAmount, Cost, Profit FROM dbo.z_fn_SalesLines(@From, @To, @LocationId, @TerminalId);

    DECLARE @b TABLE (InvoiceId INT PRIMARY KEY, InvType INT, InvDate DATETIME, Discount DECIMAL(18,2), NetAmount DECIMAL(18,2));
    INSERT @b SELECT InvoiceId, InvType, InvDate, Discount, NetAmount FROM dbo.z_tb_SalesInvoice
    WHERE InvDate >= @From AND InvDate < @To AND Status <> 9 AND LocationId = @LocationId
      AND (@TerminalId IS NULL OR TerminalId = @TerminalId);

    DECLARE @Costed DECIMAL(18,2) = ISNULL((SELECT SUM(NetAmount) FROM @l WHERE Cost IS NOT NULL), 0),
            @Profit DECIMAL(18,2) = ISNULL((SELECT SUM(Profit) FROM @l WHERE Profit IS NOT NULL), 0),
            @Bills  INT           = (SELECT COUNT(*) FROM @b WHERE InvType = 1),
            @Sales  DECIMAL(18,2) = ISNULL((SELECT SUM(NetAmount) FROM @b WHERE InvType = 1), 0);

    SELECT @Bills                                                                   AS Bills,
           (SELECT COUNT(*) FROM @b WHERE InvType = 2)                              AS Refunds,
           @Sales                                                                   AS SalesAmount,
           ISNULL((SELECT SUM(NetAmount) FROM @b WHERE InvType = 2), 0)             AS RefundAmount,
           @Sales - ISNULL((SELECT SUM(NetAmount) FROM @b WHERE InvType = 2), 0)    AS NetSales,
           ISNULL((SELECT SUM(CASE WHEN InvType = 2 THEN -Discount ELSE Discount END) FROM @b), 0) AS Discount,
           CAST(ISNULL((SELECT SUM(Qty) FROM @l), 0) AS DECIMAL(18,3))              AS ItemQty,
           CAST(ISNULL((SELECT SUM(Cost) FROM @l WHERE Cost IS NOT NULL), 0) AS DECIMAL(18,2)) AS Cost,
           @Profit                                                                  AS Profit,
           @Costed                                                                  AS CostedSales,
           CAST(ISNULL((SELECT SUM(NetAmount) FROM @l WHERE Cost IS NULL), 0) AS DECIMAL(18,2)) AS UncostedSales,
           CAST(CASE WHEN @Costed <> 0 THEN @Profit * 100 / @Costed ELSE 0 END AS DECIMAL(9,2)) AS MarginPct,
           CAST(CASE WHEN @Bills > 0 THEN @Sales / @Bills ELSE 0 END AS DECIMAL(18,2))  AS AvgBill,
           ISNULL((SELECT SUM(CASE WHEN b.InvType = 2 THEN -p.Amount ELSE p.Amount END) FROM @b b
                   JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = b.InvoiceId WHERE p.PayType = 1), 0) AS Cash,
           ISNULL((SELECT SUM(CASE WHEN b.InvType = 2 THEN -p.Amount ELSE p.Amount END) FROM @b b
                   JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = b.InvoiceId WHERE p.PayType = 2), 0) AS Card,
           ISNULL((SELECT SUM(CASE WHEN b.InvType = 2 THEN -p.Amount ELSE p.Amount END) FROM @b b
                   JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = b.InvoiceId WHERE p.PayType NOT IN (1, 2)), 0) AS Other,
           (SELECT MIN(InvDate) FROM @b)                                            AS FirstBillAt,
           (SELECT MAX(InvDate) FROM @b)                                            AS LastBillAt;
END
GO

-- One row per day from @FromDate to @ToDate — days without sales included (0), so the chart has no gaps.
CREATE PROCEDURE dbo.z_sp_DashDaily
    @FromDate DATE, @ToDate DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME = @FromDate, @To DATETIME = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME));

    DECLARE @days TABLE (SaleDate DATE PRIMARY KEY);
    DECLARE @d DATE = @FromDate;
    WHILE @d <= @ToDate
    BEGIN
        INSERT @days VALUES (@d);
        SET @d = DATEADD(DAY, 1, @d);
    END

    DECLARE @l TABLE (SaleDate DATE, NetAmount DECIMAL(18,4), Cost DECIMAL(18,4), Profit DECIMAL(18,4));
    INSERT @l SELECT SaleDate, NetAmount, Cost, Profit FROM dbo.z_fn_SalesLines(@From, @To, @LocationId, @TerminalId);

    DECLARE @b TABLE (InvoiceId INT PRIMARY KEY, SaleDate DATE, InvType INT, Discount DECIMAL(18,2), NetAmount DECIMAL(18,2));
    INSERT @b SELECT InvoiceId, CAST(InvDate AS DATE), InvType, Discount, NetAmount FROM dbo.z_tb_SalesInvoice
    WHERE InvDate >= @From AND InvDate < @To AND Status <> 9 AND LocationId = @LocationId
      AND (@TerminalId IS NULL OR TerminalId = @TerminalId);

    SELECT d.SaleDate,
           ISNULL(b.Bills, 0)     AS Bills,
           ISNULL(b.Refunds, 0)   AS Refunds,
           ISNULL(b.NetSales, 0)  AS NetSales,
           ISNULL(b.Discount, 0)  AS Discount,
           CAST(ISNULL(l.Cost, 0) AS DECIMAL(18,2))        AS Cost,
           CAST(ISNULL(l.Profit, 0) AS DECIMAL(18,2))      AS Profit,
           CAST(ISNULL(l.CostedSales, 0) AS DECIMAL(18,2)) AS CostedSales,
           CAST(CASE WHEN ISNULL(l.CostedSales, 0) <> 0 THEN l.Profit * 100 / l.CostedSales ELSE 0 END AS DECIMAL(9,2)) AS MarginPct,
           ISNULL(p.Cash, 0) AS Cash, ISNULL(p.Card, 0) AS Card, ISNULL(p.Other, 0) AS Other
    FROM @days d
    LEFT JOIN (SELECT SaleDate, SUM(CASE WHEN InvType = 1 THEN 1 ELSE 0 END) AS Bills,
                      SUM(CASE WHEN InvType = 2 THEN 1 ELSE 0 END) AS Refunds,
                      SUM(CASE WHEN InvType = 2 THEN -NetAmount ELSE NetAmount END) AS NetSales,
                      SUM(CASE WHEN InvType = 2 THEN -Discount ELSE Discount END) AS Discount
               FROM @b GROUP BY SaleDate) b ON b.SaleDate = d.SaleDate
    LEFT JOIN (SELECT SaleDate, SUM(Cost) AS Cost, SUM(Profit) AS Profit,
                      SUM(CASE WHEN Cost IS NOT NULL THEN NetAmount END) AS CostedSales
               FROM @l GROUP BY SaleDate) l ON l.SaleDate = d.SaleDate
    LEFT JOIN (SELECT b.SaleDate,
                      SUM(CASE WHEN p.PayType = 1 THEN CASE WHEN b.InvType = 2 THEN -p.Amount ELSE p.Amount END END) AS Cash,
                      SUM(CASE WHEN p.PayType = 2 THEN CASE WHEN b.InvType = 2 THEN -p.Amount ELSE p.Amount END END) AS Card,
                      SUM(CASE WHEN p.PayType NOT IN (1, 2) THEN CASE WHEN b.InvType = 2 THEN -p.Amount ELSE p.Amount END END) AS Other
               FROM @b b JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = b.InvoiceId GROUP BY b.SaleDate) p ON p.SaleDate = d.SaleDate
    ORDER BY d.SaleDate;
END
GO

-- Per till (every registered till of the location, also those without sales) + when it last sent anything.
-- IsOnline = the till uploaded or sent its heartbeat (every 30 s) within @OnlineSeconds.
CREATE PROCEDURE dbo.z_sp_DashTerminals
    @FromDate DATE, @ToDate DATE, @LocationId INT = 1, @OnlineSeconds INT = 120
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME = @FromDate, @To DATETIME = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME));

    SELECT t.TerminalId, t.TerminalCode, t.TerminalName, t.Status, t.LastSyncAt,
           CAST(CASE WHEN t.Status = 1 AND t.LastSyncAt >= DATEADD(SECOND, -@OnlineSeconds, GETDATE()) THEN 1 ELSE 0 END AS BIT) AS IsOnline,
           ISNULL(b.Bills, 0) AS Bills, ISNULL(b.NetSales, 0) AS NetSales, b.LastBillAt,
           CAST(ISNULL(l.Profit, 0) AS DECIMAL(18,2)) AS Profit
    FROM dbo.z_tb_Terminal t
    LEFT JOIN (SELECT TerminalId, SUM(CASE WHEN InvType = 1 THEN 1 ELSE 0 END) AS Bills,
                      SUM(CASE WHEN InvType = 2 THEN -NetAmount ELSE NetAmount END) AS NetSales, MAX(InvDate) AS LastBillAt
               FROM dbo.z_tb_SalesInvoice
               WHERE InvDate >= @From AND InvDate < @To AND Status <> 9 AND LocationId = @LocationId
               GROUP BY TerminalId) b ON b.TerminalId = t.TerminalId
    LEFT JOIN (SELECT TerminalId, SUM(Profit) AS Profit
               FROM dbo.z_fn_SalesLines(@From, @To, @LocationId, NULL) GROUP BY TerminalId) l ON l.TerminalId = t.TerminalId
    WHERE t.LocationId = @LocationId
    ORDER BY t.TerminalId;
END
GO

-- Sales by hour of the day (0–23, all 24 rows) over the range — busy hours.
CREATE PROCEDURE dbo.z_sp_DashHourly
    @FromDate DATE, @ToDate DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME = @FromDate, @To DATETIME = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME));

    DECLARE @h TABLE (SaleHour INT PRIMARY KEY);
    DECLARE @i INT = 0;
    WHILE @i < 24 BEGIN INSERT @h VALUES (@i); SET @i = @i + 1; END

    SELECT h.SaleHour,
           ISNULL(b.Bills, 0) AS Bills, ISNULL(b.NetSales, 0) AS NetSales,
           CAST(ISNULL(l.Profit, 0) AS DECIMAL(18,2)) AS Profit
    FROM @h h
    LEFT JOIN (SELECT DATEPART(HOUR, InvDate) AS SaleHour, SUM(CASE WHEN InvType = 1 THEN 1 ELSE 0 END) AS Bills,
                      SUM(CASE WHEN InvType = 2 THEN -NetAmount ELSE NetAmount END) AS NetSales
               FROM dbo.z_tb_SalesInvoice
               WHERE InvDate >= @From AND InvDate < @To AND Status <> 9 AND LocationId = @LocationId
                 AND (@TerminalId IS NULL OR TerminalId = @TerminalId)
               GROUP BY DATEPART(HOUR, InvDate)) b ON b.SaleHour = h.SaleHour
    LEFT JOIN (SELECT SaleHour, SUM(Profit) AS Profit
               FROM dbo.z_fn_SalesLines(@From, @To, @LocationId, @TerminalId) GROUP BY SaleHour) l ON l.SaleHour = h.SaleHour
    ORDER BY h.SaleHour;
END
GO

-- Best items over the range. @OrderBy 1 = by sales, 2 = by profit. Other items (ItemId 0) are one row.
CREATE PROCEDURE dbo.z_sp_DashTopItems
    @FromDate DATE, @ToDate DATE, @LocationId INT = 1, @TerminalId INT = NULL, @Top INT = 20, @OrderBy INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME = @FromDate, @To DATETIME = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME));

    SELECT TOP (@Top) x.ItemId,
           CASE WHEN x.ItemId = 0 THEN N'Other items (not in item list)' ELSE ISNULL(i.Inv_Descrip, i.Descrip) END AS Name,
           x.Qty, x.NetSales, x.Cost, x.Profit,
           CAST(CASE WHEN x.CostedSales <> 0 THEN x.Profit * 100 / x.CostedSales ELSE 0 END AS DECIMAL(9,2)) AS MarginPct,
           CAST(CASE WHEN x.UncostedLines > 0 THEN 1 ELSE 0 END AS BIT) AS HasUncosted
    FROM (SELECT ItemId,
                 CAST(SUM(Qty) AS DECIMAL(18,3)) AS Qty,
                 CAST(SUM(NetAmount) AS DECIMAL(18,2)) AS NetSales,
                 CAST(ISNULL(SUM(Cost), 0) AS DECIMAL(18,2)) AS Cost,
                 CAST(ISNULL(SUM(Profit), 0) AS DECIMAL(18,2)) AS Profit,
                 ISNULL(SUM(CASE WHEN Cost IS NOT NULL THEN NetAmount END), 0) AS CostedSales,
                 SUM(CASE WHEN Cost IS NULL THEN 1 ELSE 0 END) AS UncostedLines
          FROM dbo.z_fn_SalesLines(@From, @To, @LocationId, @TerminalId)
          GROUP BY ItemId) x
    LEFT JOIN dbo.z_tb_Item i ON i.ItemId = x.ItemId
    ORDER BY CASE WHEN @OrderBy = 2 THEN x.Profit ELSE x.NetSales END DESC;
END
GO

-- Sales and profit by item category over the range.
CREATE PROCEDURE dbo.z_sp_DashCategories
    @FromDate DATE, @ToDate DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME = @FromDate, @To DATETIME = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME));

    SELECT x.CatId,
           CASE WHEN x.CatId IS NULL THEN 'No category' ELSE ISNULL(c.CatName, 'Category ' + CAST(x.CatId AS VARCHAR(10))) END AS CatName,
           x.Qty, x.NetSales, x.Profit,
           CAST(CASE WHEN x.CostedSales <> 0 THEN x.Profit * 100 / x.CostedSales ELSE 0 END AS DECIMAL(9,2)) AS MarginPct
    FROM (SELECT CatId,
                 CAST(SUM(Qty) AS DECIMAL(18,3)) AS Qty,
                 CAST(SUM(NetAmount) AS DECIMAL(18,2)) AS NetSales,
                 CAST(ISNULL(SUM(Profit), 0) AS DECIMAL(18,2)) AS Profit,
                 ISNULL(SUM(CASE WHEN Cost IS NOT NULL THEN NetAmount END), 0) AS CostedSales
          FROM dbo.z_fn_SalesLines(@From, @To, @LocationId, @TerminalId)
          GROUP BY CatId) x
    LEFT JOIN dbo.z_tb_Category c ON c.CatId = x.CatId
    ORDER BY x.NetSales DESC;
END
GO
