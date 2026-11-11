/* =============================================================================
   U056_BackOffice_DayReportBusinessDate.sql   (2026-11-11)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer. Safe to run again.
   No table or data change.

   What was wrong: a till balanced the next day (opened today, day end tomorrow after midnight) - its Z is on today
   (business date) but Day Reports took the bills, items, cash in / out, voids ... by the clock (00:00 - 24:00), so
   the Summary, Bills, Items and the other tabs showed that Z half on today and half on tomorrow.

   What changes: every Day Reports tab takes the Zs of the day - new function z_fn_DayZs: closed Zs by their
   BusinessDate, a Z not balanced yet by the day of its first bill / cash movement - and the rows of those Zs
   (bills, cash movements, voids, abandoned bills by their Z no; No Sale by the Z's time on the till).
   Procs re-created (same parameters and columns): z_sp_DayReportTills / Cash / Items / Bills / Voids / NoSales /
   Abandoned / LossCashiers. z_sp_DayReportZ (Day end tab) already went by BusinessDate - not changed.
   Sales dashboard, Sales Analysis and the bank / cheque report stay by the clock (sales trends, not balancing).
   Same change in the full script: 35_BackOffice_DayReportBusinessDate.sql.

   Run any time (no ItemApi / UI change needed):
     sqlcmd -S <server> -d easyway -E -I -b -i U056_BackOffice_DayReportBusinessDate.sql
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_ZReport', 'U') IS NULL OR OBJECT_ID(N'dbo.z_sp_DayReportTills', 'P') IS NULL
   OR OBJECT_ID(N'dbo.z_tb_TillVoidLog', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_TillAbandonedBill', 'U') IS NULL
BEGIN
    RAISERROR('Day Reports / void report / abandoned bills are not in this database (run U018, U022, U023 first) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF OBJECT_ID('dbo.z_fn_DayZs', 'IF') IS NOT NULL DROP FUNCTION dbo.z_fn_DayZs;
GO
-- The Zs of a business day: the till's day end balance, whenever it was done.
--   Closed Z (in z_tb_ZReport): its BusinessDate (the till: the day of its first bill / cash, U044).
--   Z still open (no day end yet): the day of its first bill or cash movement - the same rule, so a Z started
--   yesterday stays on yesterday before and after its day end.
-- FromAt / ToAt: the Z's time on the till (from the till's previous day end to this one; open Z: no end) - for rows
-- that carry no Z no (No Sale drawer log; old void / abandoned rows).
CREATE FUNCTION dbo.z_fn_DayZs (@Date DATE, @LocationId INT, @TerminalId INT)
RETURNS TABLE
AS
RETURN
    SELECT z.TerminalId, z.ZNo,
           COALESCE((SELECT MAX(p.ClosedAt) FROM dbo.z_tb_ZReport p WHERE p.TerminalId = z.TerminalId AND p.ZNo < z.ZNo),
                    z.OpenedAt) AS FromAt,
           z.ClosedAt AS ToAt
    FROM dbo.z_tb_ZReport z
    WHERE z.BusinessDate = @Date AND z.LocationId = @LocationId
      AND (@TerminalId IS NULL OR z.TerminalId = @TerminalId)
    UNION ALL
    SELECT o.TerminalId, o.ZNo,
           (SELECT MAX(p.ClosedAt) FROM dbo.z_tb_ZReport p WHERE p.TerminalId = o.TerminalId AND p.ZNo < o.ZNo) AS FromAt,
           CAST(NULL AS DATETIME) AS ToAt
    FROM (SELECT s.TerminalId, s.ZNo FROM dbo.z_tb_SalesInvoice s
          WHERE s.LocationId = @LocationId AND s.ZNo IS NOT NULL
            AND s.InvDate >= CAST(@Date AS DATETIME) AND s.InvDate < DATEADD(DAY, 1, CAST(@Date AS DATETIME))
            AND (@TerminalId IS NULL OR s.TerminalId = @TerminalId)
          UNION
          SELECT m.TerminalId, m.ZNo FROM dbo.z_tb_CashMovement m
          WHERE m.LocationId = @LocationId AND m.ZNo IS NOT NULL
            AND m.CreatedAt >= CAST(@Date AS DATETIME) AND m.CreatedAt < DATEADD(DAY, 1, CAST(@Date AS DATETIME))
            AND (@TerminalId IS NULL OR m.TerminalId = @TerminalId)) o
    WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_ZReport z WHERE z.TerminalId = o.TerminalId AND z.ZNo = o.ZNo)
      AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_SalesInvoice s
                      WHERE s.TerminalId = o.TerminalId AND s.ZNo = o.ZNo AND s.InvDate < CAST(@Date AS DATETIME))
      AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_CashMovement m
                      WHERE m.TerminalId = o.TerminalId AND m.ZNo = o.ZNo AND m.CreatedAt < CAST(@Date AS DATETIME));
GO

IF OBJECT_ID('dbo.z_sp_DayReportTills', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportTills;
GO
-- One row per till of the location (also tills without bills that day): the day's bills, discounts, sales and
-- payments, and the cash in / out of the drawer. Refunds count negative in the payment totals, like the till Z.
-- ExpectedCash = opening cash + cash (sales - refunds) + paid in - paid out.
-- CashBack (U041): cash paid back on sale bills under 0 (till U039 - the items back worth more than the items sold),
-- plus, with CashBackBills; already inside Cash (not a paid out) - shown on its own line.
CREATE PROCEDURE dbo.z_sp_DayReportTills
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- the day = the Zs whose business date is @Date (U056) - a Z balanced after midnight stays on its start day
    DECLARE @Z TABLE (TerminalId INT NOT NULL, ZNo INT NOT NULL, FromAt DATETIME NULL, ToAt DATETIME NULL,
                      PRIMARY KEY (TerminalId, ZNo));
    INSERT @Z (TerminalId, ZNo, FromAt, ToAt) SELECT TerminalId, ZNo, FromAt, ToAt FROM dbo.z_fn_DayZs(@Date, @LocationId, @TerminalId);

    SELECT t.TerminalId, t.TerminalCode, t.TerminalName, t.LastSyncAt,
           ISNULL(b.Bills, 0) AS Bills, ISNULL(b.Refunds, 0) AS Refunds, ISNULL(b.Voided, 0) AS Voided,
           ISNULL(b.SalesAmount, 0) + ISNULL(l.ItemDiscount, 0) + ISNULL(b.BillDiscount, 0) AS SalesBeforeDiscount,
           ISNULL(l.ItemDiscount, 0) AS ItemDiscount, ISNULL(b.BillDiscount, 0) AS BillDiscount,
           ISNULL(b.SalesAmount, 0) AS SalesAmount, ISNULL(b.RefundAmount, 0) AS RefundAmount,
           ISNULL(b.SalesAmount, 0) - ISNULL(b.RefundAmount, 0) AS NetSales,
           ISNULL(p.Cash, 0) AS Cash, ISNULL(p.Card, 0) AS Card, ISNULL(p.Bank, 0) AS Bank,
           ISNULL(p.Cheque, 0) AS Cheque, ISNULL(p.OtherPay, 0) AS OtherPay,
           ISNULL(m.OpeningCash, 0) AS OpeningCash, ISNULL(m.PaidIn, 0) AS PaidIn, ISNULL(m.PaidOut, 0) AS PaidOut,
           ISNULL(m.OpeningCash, 0) + ISNULL(p.Cash, 0) + ISNULL(m.PaidIn, 0) - ISNULL(m.PaidOut, 0) AS ExpectedCash,
           b.FirstBillAt, b.LastBillAt, m.LastMoveAt,
           ISNULL(cb.CashBack, 0) AS CashBack, ISNULL(cb.CashBackBills, 0) AS CashBackBills
    FROM dbo.z_tb_Terminal t
    LEFT JOIN (SELECT TerminalId,
                      SUM(CASE WHEN Status <> 9 AND InvType = 1 THEN 1 ELSE 0 END) AS Bills,
                      SUM(CASE WHEN Status <> 9 AND InvType = 2 THEN 1 ELSE 0 END) AS Refunds,
                      SUM(CASE WHEN Status = 9 THEN 1 ELSE 0 END) AS Voided,
                      SUM(CASE WHEN Status <> 9 AND InvType = 1 THEN NetAmount ELSE 0 END) AS SalesAmount,
                      SUM(CASE WHEN Status <> 9 AND InvType = 2 THEN NetAmount ELSE 0 END) AS RefundAmount,
                      SUM(CASE WHEN Status <> 9 AND InvType = 1 THEN Discount ELSE 0 END) AS BillDiscount,
                      MIN(InvDate) AS FirstBillAt, MAX(InvDate) AS LastBillAt
               FROM dbo.z_tb_SalesInvoice
               WHERE LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = z_tb_SalesInvoice.TerminalId AND z.ZNo = z_tb_SalesInvoice.ZNo)
               GROUP BY TerminalId) b ON b.TerminalId = t.TerminalId
    LEFT JOIN (SELECT s.TerminalId, SUM(it.Discount) AS ItemDiscount
               FROM dbo.z_tb_SalesInvoice s JOIN dbo.z_tb_SalesInvoiceItem it ON it.InvoiceId = s.InvoiceId
               WHERE s.LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = s.TerminalId AND z.ZNo = s.ZNo)
                 AND s.Status <> 9 AND s.InvType = 1
               GROUP BY s.TerminalId) l ON l.TerminalId = t.TerminalId
    LEFT JOIN (SELECT s.TerminalId,
                      SUM(CASE WHEN p.PayType = 1 THEN x.Amount ELSE 0 END) AS Cash,
                      SUM(CASE WHEN p.PayType = 2 THEN x.Amount ELSE 0 END) AS Card,
                      SUM(CASE WHEN p.PayType = 5 THEN x.Amount ELSE 0 END) AS Bank,
                      SUM(CASE WHEN p.PayType = 6 THEN x.Amount ELSE 0 END) AS Cheque,
                      SUM(CASE WHEN p.PayType NOT IN (1, 2, 5, 6) THEN x.Amount ELSE 0 END) AS OtherPay
               FROM dbo.z_tb_SalesInvoice s
               JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = s.InvoiceId
               CROSS APPLY (SELECT CASE WHEN s.InvType = 2 THEN -p.Amount ELSE p.Amount END AS Amount) x
               WHERE s.LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = s.TerminalId AND z.ZNo = s.ZNo) AND s.Status <> 9
               GROUP BY s.TerminalId) p ON p.TerminalId = t.TerminalId
    LEFT JOIN (SELECT TerminalId,
                      SUM(CASE WHEN Kind = 1 THEN Amount ELSE 0 END) AS OpeningCash,
                      SUM(CASE WHEN Kind = 2 THEN Amount ELSE 0 END) AS PaidIn,
                      SUM(CASE WHEN Kind = 3 THEN Amount ELSE 0 END) AS PaidOut,
                      MAX(CreatedAt) AS LastMoveAt
               FROM dbo.z_tb_CashMovement
               WHERE LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = z_tb_CashMovement.TerminalId AND z.ZNo = z_tb_CashMovement.ZNo) AND Status = 1
               GROUP BY TerminalId) m ON m.TerminalId = t.TerminalId
    LEFT JOIN (SELECT s.TerminalId, SUM(-p.Amount) AS CashBack, COUNT(DISTINCT s.InvoiceId) AS CashBackBills
               FROM dbo.z_tb_SalesInvoice s JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = s.InvoiceId
               WHERE s.LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = s.TerminalId AND z.ZNo = s.ZNo) AND s.Status <> 9
                 AND s.InvType = 1 AND p.PayType = 1 AND p.Amount < 0
               GROUP BY s.TerminalId) cb ON cb.TerminalId = t.TerminalId
    WHERE t.LocationId = @LocationId
      AND (@TerminalId IS NULL OR t.TerminalId = @TerminalId)
    ORDER BY t.TerminalId;
END
GO

IF OBJECT_ID('dbo.z_sp_DayReportCash', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportCash;
GO
-- Every opening cash / paid in / paid out of the day (till time), replaced opening cash too (Status 9).
CREATE PROCEDURE dbo.z_sp_DayReportCash
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- the day = the Zs whose business date is @Date (U056) - a Z balanced after midnight stays on its start day
    DECLARE @Z TABLE (TerminalId INT NOT NULL, ZNo INT NOT NULL, FromAt DATETIME NULL, ToAt DATETIME NULL,
                      PRIMARY KEY (TerminalId, ZNo));
    INSERT @Z (TerminalId, ZNo, FromAt, ToAt) SELECT TerminalId, ZNo, FromAt, ToAt FROM dbo.z_fn_DayZs(@Date, @LocationId, @TerminalId);

    SELECT m.TerminalId, t.TerminalCode, m.ZNo, m.MoveId, m.Kind, m.Amount, m.Reason, m.CashierId,
           u.UserName AS CashierName, m.CreatedAt, m.Status
    FROM dbo.z_tb_CashMovement m
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = m.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = m.CashierId
    WHERE m.LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = m.TerminalId AND z.ZNo = m.ZNo)
      AND (@TerminalId IS NULL OR m.TerminalId = @TerminalId)
    ORDER BY m.CreatedAt, m.TerminalId, m.MoveId;
END
GO

IF OBJECT_ID('dbo.z_sp_DayReportItems', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportItems;
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
    -- the day = the Zs whose business date is @Date (U056) - a Z balanced after midnight stays on its start day
    DECLARE @Z TABLE (TerminalId INT NOT NULL, ZNo INT NOT NULL, FromAt DATETIME NULL, ToAt DATETIME NULL,
                      PRIMARY KEY (TerminalId, ZNo));
    INSERT @Z (TerminalId, ZNo, FromAt, ToAt) SELECT TerminalId, ZNo, FromAt, ToAt FROM dbo.z_fn_DayZs(@Date, @LocationId, @TerminalId);

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
          WHERE s.LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = s.TerminalId AND z.ZNo = s.ZNo) AND s.Status <> 9
            AND (@TerminalId IS NULL OR s.TerminalId = @TerminalId)
          GROUP BY it.ItemId, CASE WHEN it.ItemId = 0 THEN it.LineDescrip END) x
    LEFT JOIN dbo.z_tb_Item i ON i.ItemId = x.ItemId AND x.ItemId <> 0
    ORDER BY x.SoldAmount - x.RefundAmount DESC, Name;
END
GO

IF OBJECT_ID('dbo.z_sp_DayReportBills', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportBills;
GO
-- Every bill of the day (voided ones too, Status 9), newest first, with how it was paid.
-- Cost / Profit as z_sp_DayReportItems (refund bills negative, after the bill discount); NULL = no line has a cost,
-- and always NULL on a voided bill. UncostedLines = lines left out of Cost / Profit (other items, items without a cost).
-- Payments as on the bill (plus, also on a refund bill): Cash, Card, Bank (5 bank transfer), Cheque (6), OtherPay =
-- the rest (3 credit, 4 voucher, 8 points ...) - Bank / Cheque split out by U043. PayRef = the transfer reference /
-- cheque number (the first one given on the bill), NULL = none.
CREATE PROCEDURE dbo.z_sp_DayReportBills
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- the day = the Zs whose business date is @Date (U056) - a Z balanced after midnight stays on its start day
    DECLARE @Z TABLE (TerminalId INT NOT NULL, ZNo INT NOT NULL, FromAt DATETIME NULL, ToAt DATETIME NULL,
                      PRIMARY KEY (TerminalId, ZNo));
    INSERT @Z (TerminalId, ZNo, FromAt, ToAt) SELECT TerminalId, ZNo, FromAt, ToAt FROM dbo.z_fn_DayZs(@Date, @LocationId, @TerminalId);

    SELECT s.InvoiceId, s.InvoiceNo, s.TerminalId, t.TerminalCode, s.ZNo, s.InvType, s.InvDate, s.CashierId,
           u.UserName AS CashierName, s.GrossAmount, s.Discount, s.NetAmount, s.Status, s.PriceType,
           (SELECT COUNT(*) FROM dbo.z_tb_SalesInvoiceItem it WHERE it.InvoiceId = s.InvoiceId) AS Lines,
           ISNULL((SELECT SUM(it.Discount) FROM dbo.z_tb_SalesInvoiceItem it WHERE it.InvoiceId = s.InvoiceId), 0) AS ItemDiscount,
           ISNULL((SELECT SUM(p.Amount) FROM dbo.z_tb_SalesPayment p WHERE p.InvoiceId = s.InvoiceId AND p.PayType = 1), 0) AS Cash,
           ISNULL((SELECT SUM(p.Amount) FROM dbo.z_tb_SalesPayment p WHERE p.InvoiceId = s.InvoiceId AND p.PayType = 2), 0) AS Card,
           ISNULL((SELECT SUM(p.Amount) FROM dbo.z_tb_SalesPayment p WHERE p.InvoiceId = s.InvoiceId AND p.PayType = 5), 0) AS Bank,
           ISNULL((SELECT SUM(p.Amount) FROM dbo.z_tb_SalesPayment p WHERE p.InvoiceId = s.InvoiceId AND p.PayType = 6), 0) AS Cheque,
           ISNULL((SELECT SUM(p.Amount) FROM dbo.z_tb_SalesPayment p WHERE p.InvoiceId = s.InvoiceId AND p.PayType NOT IN (1, 2, 5, 6)), 0) AS OtherPay,
           (SELECT TOP 1 p.RefNo FROM dbo.z_tb_SalesPayment p
            WHERE p.InvoiceId = s.InvoiceId AND p.PayType IN (5, 6) AND LTRIM(RTRIM(ISNULL(p.RefNo, ''))) <> ''
            ORDER BY p.LineNum) AS PayRef,
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
    WHERE s.LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = s.TerminalId AND z.ZNo = s.ZNo)
      AND (@TerminalId IS NULL OR s.TerminalId = @TerminalId)
    ORDER BY s.InvDate DESC, s.InvoiceId DESC;
END
GO

IF OBJECT_ID('dbo.z_sp_DayReportVoids', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportVoids;
GO
-- Every void line of the day (refund-bill lines too, Refund = 1), newest first.
CREATE PROCEDURE dbo.z_sp_DayReportVoids
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- the day = the Zs whose business date is @Date (U056) - a Z balanced after midnight stays on its start day
    DECLARE @Z TABLE (TerminalId INT NOT NULL, ZNo INT NOT NULL, FromAt DATETIME NULL, ToAt DATETIME NULL,
                      PRIMARY KEY (TerminalId, ZNo));
    INSERT @Z (TerminalId, ZNo, FromAt, ToAt) SELECT TerminalId, ZNo, FromAt, ToAt FROM dbo.z_fn_DayZs(@Date, @LocationId, @TerminalId);

    SELECT v.TerminalId, t.TerminalCode, v.VoidId, v.GroupNo, v.LoggedAt, v.Kind, v.ZNo, v.CashierId,
           u.UserName AS CashierName, v.Refund, v.ItemId, i.RefCode, i.Barcode,
           CASE WHEN v.ItemId = 0 THEN ISNULL(v.Descrip, N'Other item') ELSE ISNULL(v.Descrip, ISNULL(i.Inv_Descrip, i.Descrip)) END AS Name,
           v.Qty, v.UnitPrice, v.Amount
    FROM dbo.z_tb_TillVoidLog v
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = v.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = v.CashierId
    LEFT JOIN dbo.z_tb_Item i ON i.ItemId = v.ItemId AND v.ItemId <> 0
    WHERE v.LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = v.TerminalId
                   AND (z.ZNo = v.ZNo OR (v.ZNo IS NULL AND v.LoggedAt > ISNULL(z.FromAt, '19000101') AND (z.ToAt IS NULL OR v.LoggedAt <= z.ToAt))))
      AND (@TerminalId IS NULL OR v.TerminalId = @TerminalId)
    ORDER BY v.LoggedAt DESC, v.TerminalId, v.VoidId;
END
GO

IF OBJECT_ID('dbo.z_sp_DayReportNoSales', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportNoSales;
GO
-- Every No Sale drawer opening of the day (Opened 0 = the drawer did not open), newest first.
CREATE PROCEDURE dbo.z_sp_DayReportNoSales
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- the day = the Zs whose business date is @Date (U056) - a Z balanced after midnight stays on its start day
    DECLARE @Z TABLE (TerminalId INT NOT NULL, ZNo INT NOT NULL, FromAt DATETIME NULL, ToAt DATETIME NULL,
                      PRIMARY KEY (TerminalId, ZNo));
    INSERT @Z (TerminalId, ZNo, FromAt, ToAt) SELECT TerminalId, ZNo, FromAt, ToAt FROM dbo.z_fn_DayZs(@Date, @LocationId, @TerminalId);

    SELECT d.TerminalId, t.TerminalCode, d.DrawerLogId, d.OpenedAt, d.CashierId, u.UserName AS CashierName,
           d.Reason, d.Opened
    FROM dbo.z_tb_TillDrawerLog d
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = d.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = d.CashierId
    WHERE d.LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = d.TerminalId
                   AND d.OpenedAt > ISNULL(z.FromAt, '19000101') AND (z.ToAt IS NULL OR d.OpenedAt <= z.ToAt)) AND d.Kind = 2
      AND (@TerminalId IS NULL OR d.TerminalId = @TerminalId)
    ORDER BY d.OpenedAt DESC, d.TerminalId, d.DrawerLogId;
END
GO

IF OBJECT_ID('dbo.z_sp_DayReportAbandoned', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportAbandoned;
GO
-- Abandoned bills of the day (by the last change before the till stopped), newest first.
-- DownMinutes = minutes from that last change until the till was back (how long it was off / stuck).
CREATE PROCEDURE dbo.z_sp_DayReportAbandoned
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- the day = the Zs whose business date is @Date (U056) - a Z balanced after midnight stays on its start day
    DECLARE @Z TABLE (TerminalId INT NOT NULL, ZNo INT NOT NULL, FromAt DATETIME NULL, ToAt DATETIME NULL,
                      PRIMARY KEY (TerminalId, ZNo));
    INSERT @Z (TerminalId, ZNo, FromAt, ToAt) SELECT TerminalId, ZNo, FromAt, ToAt FROM dbo.z_fn_DayZs(@Date, @LocationId, @TerminalId);

    SELECT a.TerminalId, t.TerminalCode, a.AbandonId, a.ZNo, a.CashierId, u.UserName AS CashierName, a.InvType,
           a.LineCount, a.NetAmount, a.StartedAt, a.LastSavedAt, a.FoundAt, a.FoundBy, f.UserName AS FoundByName,
           DATEDIFF(MINUTE, a.LastSavedAt, a.FoundAt) AS DownMinutes,
           a.Outcome, a.Reason, a.FinalStatus, a.FinalAt, a.InvoiceNo, a.SuspendId
    FROM dbo.z_tb_TillAbandonedBill a
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = a.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = a.CashierId
    LEFT JOIN dbo.z_tb_User f ON f.LoginName = a.FoundBy
    WHERE a.LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = a.TerminalId
                   AND (z.ZNo = a.ZNo OR (a.ZNo IS NULL AND a.LastSavedAt > ISNULL(z.FromAt, '19000101') AND (z.ToAt IS NULL OR a.LastSavedAt <= z.ToAt))))
      AND (@TerminalId IS NULL OR a.TerminalId = @TerminalId)
    ORDER BY a.LastSavedAt DESC, a.TerminalId, a.AbandonId;
END
GO

IF OBJECT_ID('dbo.z_sp_DayReportLossCashiers', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportLossCashiers;
GO
-- One row per cashier who did anything that day: sales, voids (refund-bill lines left out), No Sale, refunds and
-- voided saved bills. VoidPercent = all voids / (sales + all voids) * 100.
CREATE PROCEDURE dbo.z_sp_DayReportLossCashiers
    @Date DATE, @LocationId INT = 1, @TerminalId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- the day = the Zs whose business date is @Date (U056) - a Z balanced after midnight stays on its start day
    DECLARE @Z TABLE (TerminalId INT NOT NULL, ZNo INT NOT NULL, FromAt DATETIME NULL, ToAt DATETIME NULL,
                      PRIMARY KEY (TerminalId, ZNo));
    INSERT @Z (TerminalId, ZNo, FromAt, ToAt) SELECT TerminalId, ZNo, FromAt, ToAt FROM dbo.z_fn_DayZs(@Date, @LocationId, @TerminalId);

    SELECT c.CashierId, u.UserName AS CashierName,
           ISNULL(b.Bills, 0) AS Bills, ISNULL(b.SalesAmount, 0) AS SalesAmount,
           ISNULL(v.VoidLines, 0) AS VoidLines, ISNULL(v.VoidLineAmount, 0) AS VoidLineAmount,
           ISNULL(v.VoidBills, 0) AS VoidBills, ISNULL(v.VoidBillAmount, 0) AS VoidBillAmount,
           ISNULL(v.QtyCuts, 0) AS QtyCuts, ISNULL(v.QtyCutAmount, 0) AS QtyCutAmount,
           ISNULL(v.VoidLineAmount, 0) + ISNULL(v.VoidBillAmount, 0) + ISNULL(v.QtyCutAmount, 0) AS VoidTotal,
           CAST(CASE WHEN ISNULL(b.SalesAmount, 0) + ISNULL(v.VoidLineAmount, 0) + ISNULL(v.VoidBillAmount, 0) + ISNULL(v.QtyCutAmount, 0) <= 0 THEN 0
                     ELSE (ISNULL(v.VoidLineAmount, 0) + ISNULL(v.VoidBillAmount, 0) + ISNULL(v.QtyCutAmount, 0)) * 100.0
                          / (ISNULL(b.SalesAmount, 0) + ISNULL(v.VoidLineAmount, 0) + ISNULL(v.VoidBillAmount, 0) + ISNULL(v.QtyCutAmount, 0))
                END AS DECIMAL(9,2)) AS VoidPercent,
           ISNULL(d.NoSales, 0) AS NoSales, ISNULL(d.DrawerFailed, 0) AS DrawerFailed,
           ISNULL(b.Refunds, 0) AS Refunds, ISNULL(b.RefundAmount, 0) AS RefundAmount,
           ISNULL(b.VoidedBills, 0) AS VoidedBills, ISNULL(b.VoidedAmount, 0) AS VoidedAmount
    FROM (SELECT CashierId FROM dbo.z_tb_SalesInvoice
          WHERE LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = z_tb_SalesInvoice.TerminalId AND z.ZNo = z_tb_SalesInvoice.ZNo) AND (@TerminalId IS NULL OR TerminalId = @TerminalId)
          UNION
          SELECT CashierId FROM dbo.z_tb_TillVoidLog
          WHERE LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = z_tb_TillVoidLog.TerminalId
                   AND (z.ZNo = z_tb_TillVoidLog.ZNo OR (z_tb_TillVoidLog.ZNo IS NULL AND z_tb_TillVoidLog.LoggedAt > ISNULL(z.FromAt, '19000101') AND (z.ToAt IS NULL OR z_tb_TillVoidLog.LoggedAt <= z.ToAt)))) AND (@TerminalId IS NULL OR TerminalId = @TerminalId)
          UNION
          SELECT CashierId FROM dbo.z_tb_TillDrawerLog
          WHERE LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = z_tb_TillDrawerLog.TerminalId
                   AND z_tb_TillDrawerLog.OpenedAt > ISNULL(z.FromAt, '19000101') AND (z.ToAt IS NULL OR z_tb_TillDrawerLog.OpenedAt <= z.ToAt)) AND Kind = 2
            AND (@TerminalId IS NULL OR TerminalId = @TerminalId)) c
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = c.CashierId
    LEFT JOIN (SELECT CashierId,
                      SUM(CASE WHEN Status <> 9 AND InvType = 1 THEN 1 ELSE 0 END) AS Bills,
                      SUM(CASE WHEN Status <> 9 AND InvType = 1 THEN NetAmount ELSE 0 END) AS SalesAmount,
                      SUM(CASE WHEN Status <> 9 AND InvType = 2 THEN 1 ELSE 0 END) AS Refunds,
                      SUM(CASE WHEN Status <> 9 AND InvType = 2 THEN NetAmount ELSE 0 END) AS RefundAmount,
                      SUM(CASE WHEN Status = 9 THEN 1 ELSE 0 END) AS VoidedBills,
                      SUM(CASE WHEN Status = 9 THEN NetAmount ELSE 0 END) AS VoidedAmount
               FROM dbo.z_tb_SalesInvoice
               WHERE LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = z_tb_SalesInvoice.TerminalId AND z.ZNo = z_tb_SalesInvoice.ZNo)
                 AND (@TerminalId IS NULL OR TerminalId = @TerminalId)
               GROUP BY CashierId) b ON ISNULL(b.CashierId, '') = ISNULL(c.CashierId, '')
    LEFT JOIN (SELECT CashierId,
                      SUM(CASE WHEN Kind = 1 THEN 1 ELSE 0 END) AS VoidLines,
                      SUM(CASE WHEN Kind = 1 THEN Amount ELSE 0 END) AS VoidLineAmount,
                      COUNT(DISTINCT CASE WHEN Kind = 2 THEN CAST(TerminalId AS VARCHAR(10)) + '-' + CAST(GroupNo AS VARCHAR(10)) END) AS VoidBills,
                      SUM(CASE WHEN Kind = 2 THEN Amount ELSE 0 END) AS VoidBillAmount,
                      SUM(CASE WHEN Kind = 3 THEN 1 ELSE 0 END) AS QtyCuts,
                      SUM(CASE WHEN Kind = 3 THEN Amount ELSE 0 END) AS QtyCutAmount
               FROM dbo.z_tb_TillVoidLog
               WHERE LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = z_tb_TillVoidLog.TerminalId
                   AND (z.ZNo = z_tb_TillVoidLog.ZNo OR (z_tb_TillVoidLog.ZNo IS NULL AND z_tb_TillVoidLog.LoggedAt > ISNULL(z.FromAt, '19000101') AND (z.ToAt IS NULL OR z_tb_TillVoidLog.LoggedAt <= z.ToAt)))) AND Refund = 0
                 AND (@TerminalId IS NULL OR TerminalId = @TerminalId)
               GROUP BY CashierId) v ON ISNULL(v.CashierId, '') = ISNULL(c.CashierId, '')
    LEFT JOIN (SELECT CashierId, COUNT(*) AS NoSales, SUM(CASE WHEN Opened = 0 THEN 1 ELSE 0 END) AS DrawerFailed
               FROM dbo.z_tb_TillDrawerLog
               WHERE LocationId = @LocationId AND EXISTS (SELECT 1 FROM @Z z WHERE z.TerminalId = z_tb_TillDrawerLog.TerminalId
                   AND z_tb_TillDrawerLog.OpenedAt > ISNULL(z.FromAt, '19000101') AND (z.ToAt IS NULL OR z_tb_TillDrawerLog.OpenedAt <= z.ToAt)) AND Kind = 2
                 AND (@TerminalId IS NULL OR TerminalId = @TerminalId)
               GROUP BY CashierId) d ON ISNULL(d.CashierId, '') = ISNULL(c.CashierId, '')
    ORDER BY ISNULL(v.VoidLineAmount, 0) + ISNULL(v.VoidBillAmount, 0) + ISNULL(v.QtyCutAmount, 0) DESC, c.CashierId;
END
GO
SET NOEXEC OFF;
GO
PRINT 'U056 back office: Day Reports by business date (z_fn_DayZs; z_sp_DayReportTills / Cash / Items / Bills / Voids / NoSales / Abandoned / LossCashiers).';
GO
