/* =============================================================================
   U057_BackOffice_Reports.sql   (2026-11-11)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer. Safe to run again.
   No table or column change; one data change only when a user presses Deactivate / Activate (z_tb_Item.Status).

   Back office > Reports (new sidebar group):
     Period report   z_sp_RptPeriod      per day or per month in a date range: sales, cost, profit, the payments the
                                         bills took (cash, card, bank transfer, cheque, other), till paid in / paid out,
                                         supplier bills (purchases), supplier returns, supplier payments by cheque /
                                         at the till (cash) / transfer or other, stock in (GRN at cost), adjustments.
                     z_sp_RptStockNow    one row: stock value now, items with stock / zero / minus.
     Payments        z_sp_RptMoney       every money row in a date range, one list: cheques written (by the written
                                         date or by the cheque date), supplier payments by transfer / other, till
                                         paid in / paid out (the supplier when it was a till payment), bills paid by
                                         bank transfer / cheque.
     Stock health    z_sp_RptStockHealth every item (active, or the deactivated ones) with stock qty and value, last
                                         sale, last GRN, last stock move, last edit - the page lists minus / zero
                                         stock, items not sold or not moved for N days.
                     z_sp_RptItemSetStatus  Deactivate (Status 0) / Activate (Status 1) the ticked items. UDate is set,
                                         so the tills get the change at their next item sync (a deactivated item does
                                         not sell). Nothing is deleted - the bills, GRNs and ledgers keep the item.
                                         Refused for an item that still has stock (qty above 0).
   Supplier payments split: ChequeId set = cheque; made by a till payment request (z_tb_TillPayRequest /
   z_tb_TillPayReceipt) or typed on the till (remark "... [till 1, cashier]") = cash at the till (it is also a till paid out - not counted twice in "money out");
   the rest = bank transfer / marked as paid / correction.
   Same procs in the full script: 36_BackOffice_Reports.sql.

   Run, then the new ItemApi (api/Report) and the back office UI:
     sqlcmd -S <server> -d easyway -E -I -b -i U057_BackOffice_Reports.sql
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_SalesInvoice', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_CashMovement', 'U') IS NULL
   OR OBJECT_ID(N'dbo.z_tb_SupplierLedger', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_WrittenCheque', 'U') IS NULL
   OR OBJECT_ID(N'dbo.z_tb_TillPayRequest', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_StockLedger', 'U') IS NULL
   OR TYPE_ID(N'dbo.z_tt_IdList') IS NULL
BEGIN
    RAISERROR('Sales / cash movements / supplier payments / till payments / stock ledger are not in this database (run U003, U007, U018, U032 first) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF OBJECT_ID('dbo.z_sp_RptPeriod', 'P')         IS NOT NULL DROP PROCEDURE dbo.z_sp_RptPeriod;
IF OBJECT_ID('dbo.z_sp_RptStockNow', 'P')       IS NOT NULL DROP PROCEDURE dbo.z_sp_RptStockNow;
IF OBJECT_ID('dbo.z_sp_RptMoney', 'P')          IS NOT NULL DROP PROCEDURE dbo.z_sp_RptMoney;
IF OBJECT_ID('dbo.z_sp_RptStockHealth', 'P')    IS NOT NULL DROP PROCEDURE dbo.z_sp_RptStockHealth;
IF OBJECT_ID('dbo.z_sp_RptItemSetStatus', 'P')  IS NOT NULL DROP PROCEDURE dbo.z_sp_RptItemSetStatus;
GO

-- Per day (@Month 0) or per month (@Month 1, Period = the 1st) from @FromDate to @ToDate (both included).
-- Sales by the clock (as Sales Analysis); refund bills negative, voided bills left out.
CREATE PROCEDURE dbo.z_sp_RptPeriod
    @FromDate DATE, @ToDate DATE, @LocationId INT = 1, @Month BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME = @FromDate, @To DATETIME = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME));

    DECLARE @p TABLE (Period DATE PRIMARY KEY);
    DECLARE @d DATE = CASE WHEN @Month = 1 THEN DATEADD(MONTH, DATEDIFF(MONTH, 0, @FromDate), 0) ELSE @FromDate END;
    WHILE @d <= @ToDate
    BEGIN
        INSERT @p VALUES (@d);
        SET @d = CASE WHEN @Month = 1 THEN DATEADD(MONTH, 1, @d) ELSE DATEADD(DAY, 1, @d) END;
    END

    -- the bills
    DECLARE @b TABLE (InvoiceId INT PRIMARY KEY, Period DATE, Sign INT);
    INSERT @b
    SELECT InvoiceId,
           CASE WHEN @Month = 1 THEN DATEADD(MONTH, DATEDIFF(MONTH, 0, InvDate), 0) ELSE CAST(InvDate AS DATE) END,
           CASE WHEN InvType = 2 THEN -1 ELSE 1 END
    FROM dbo.z_tb_SalesInvoice
    WHERE InvDate >= @From AND InvDate < @To AND Status <> 9 AND LocationId = @LocationId;

    DECLARE @s TABLE (Period DATE PRIMARY KEY, Bills INT, NetSales DECIMAL(18,2), Cost DECIMAL(18,2), Profit DECIMAL(18,2),
                      CostedSales DECIMAL(18,2));
    INSERT @s
    SELECT b.Period, COUNT(DISTINCT CASE WHEN b.Sign = 1 THEN b.InvoiceId END),
           SUM(l.NetAmount), ISNULL(SUM(l.Cost), 0), ISNULL(SUM(l.Profit), 0),
           ISNULL(SUM(CASE WHEN l.Cost IS NOT NULL THEN l.NetAmount END), 0)
    FROM dbo.z_fn_SalesLines(@From, @To, @LocationId, NULL) l
    JOIN @b b ON b.InvoiceId = l.InvoiceId
    GROUP BY b.Period;

    DECLARE @pay TABLE (Period DATE PRIMARY KEY, Cash DECIMAL(18,2), Card DECIMAL(18,2), BankIn DECIMAL(18,2),
                        ChequeIn DECIMAL(18,2), OtherIn DECIMAL(18,2));
    INSERT @pay
    SELECT b.Period,
           SUM(CASE WHEN p.PayType = 1 THEN b.Sign * p.Amount ELSE 0 END),
           SUM(CASE WHEN p.PayType = 2 THEN b.Sign * p.Amount ELSE 0 END),
           SUM(CASE WHEN p.PayType = 5 THEN b.Sign * p.Amount ELSE 0 END),
           SUM(CASE WHEN p.PayType = 6 THEN b.Sign * p.Amount ELSE 0 END),
           SUM(CASE WHEN p.PayType NOT IN (1, 2, 5, 6) THEN b.Sign * p.Amount ELSE 0 END)
    FROM @b b JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = b.InvoiceId
    GROUP BY b.Period;

    -- till paid in (Kind 2) / paid out (Kind 3)
    DECLARE @cm TABLE (Period DATE PRIMARY KEY, PaidIn DECIMAL(18,2), PaidOut DECIMAL(18,2));
    INSERT @cm
    SELECT x.Period, SUM(CASE WHEN m.Kind = 2 THEN m.Amount ELSE 0 END), SUM(CASE WHEN m.Kind = 3 THEN m.Amount ELSE 0 END)
    FROM dbo.z_tb_CashMovement m
    CROSS APPLY (SELECT CASE WHEN @Month = 1 THEN DATEADD(MONTH, DATEDIFF(MONTH, 0, m.CreatedAt), 0)
                             ELSE CAST(m.CreatedAt AS DATE) END AS Period) x
    WHERE m.CreatedAt >= @From AND m.CreatedAt < @To AND m.Kind IN (2, 3) AND m.Status <> 9 AND m.LocationId = @LocationId
    GROUP BY x.Period;

    -- supplier bills / returns / payments (by the ledger date)
    DECLARE @sl TABLE (Period DATE PRIMARY KEY, Purchases DECIMAL(18,2), SupReturns DECIMAL(18,2), PayCheque DECIMAL(18,2),
                       PayCash DECIMAL(18,2), PayTransfer DECIMAL(18,2));
    INSERT @sl
    SELECT x.Period,
           SUM(CASE WHEN l.Type = 1 THEN l.DebitAmount ELSE 0 END),
           SUM(CASE WHEN l.Type = 3 AND l.ChequeId IS NULL THEN l.CreditAmount ELSE 0 END),
           SUM(CASE WHEN l.Type = 2 AND l.ChequeId IS NOT NULL THEN l.CreditAmount ELSE 0 END),
           SUM(CASE WHEN l.Type = 2 AND l.ChequeId IS NULL AND t.Till = 1 THEN l.CreditAmount ELSE 0 END),
           SUM(CASE WHEN l.Type = 2 AND l.ChequeId IS NULL AND t.Till = 0 THEN l.CreditAmount ELSE 0 END)
    FROM dbo.z_tb_SupplierLedger l
    CROSS APPLY (SELECT CASE WHEN @Month = 1 THEN DATEADD(MONTH, DATEDIFF(MONTH, 0, l.TxnDate), 0) ELSE l.TxnDate END AS Period) x
    CROSS APPLY (SELECT CASE WHEN EXISTS (SELECT 1 FROM dbo.z_tb_TillPayRequest r WHERE r.PaymentLedgerId = l.LedgerId)
                               OR EXISTS (SELECT 1 FROM dbo.z_tb_TillPayReceipt r WHERE r.PaymentLedgerId = l.LedgerId)
                               OR l.Remark LIKE N'%[[]till [0-9]%'
                             THEN 1 ELSE 0 END AS Till) t
    WHERE l.TxnDate >= @FromDate AND l.TxnDate <= @ToDate
    GROUP BY x.Period;

    -- stock in (GRN, TxnType 1) and adjustments (5) at cost
    DECLARE @st TABLE (Period DATE PRIMARY KEY, StockIn DECIMAL(18,2), StockAdj DECIMAL(18,2));
    INSERT @st
    SELECT x.Period,
           SUM(CASE WHEN g.TxnType = 1 THEN g.Qty * ISNULL(g.CostPrice, 0) ELSE 0 END),
           SUM(CASE WHEN g.TxnType = 5 THEN g.Qty * ISNULL(g.CostPrice, 0) ELSE 0 END)
    FROM dbo.z_tb_StockLedger g
    CROSS APPLY (SELECT CASE WHEN @Month = 1 THEN DATEADD(MONTH, DATEDIFF(MONTH, 0, g.TxnDate), 0)
                             ELSE CAST(g.TxnDate AS DATE) END AS Period) x
    WHERE g.TxnDate >= @From AND g.TxnDate < @To AND g.TxnType IN (1, 5) AND g.LocationId = @LocationId
    GROUP BY x.Period;

    SELECT p.Period,
           ISNULL(s.Bills, 0) AS Bills, ISNULL(s.NetSales, 0) AS NetSales, ISNULL(s.Cost, 0) AS Cost,
           ISNULL(s.Profit, 0) AS Profit,
           CAST(CASE WHEN ISNULL(s.CostedSales, 0) <> 0 THEN s.Profit * 100 / s.CostedSales ELSE 0 END AS DECIMAL(9,2)) AS MarginPct,
           ISNULL(y.Cash, 0) AS Cash, ISNULL(y.Card, 0) AS Card, ISNULL(y.BankIn, 0) AS BankIn,
           ISNULL(y.ChequeIn, 0) AS ChequeIn, ISNULL(y.OtherIn, 0) AS OtherIn,
           ISNULL(c.PaidIn, 0) AS PaidIn, ISNULL(c.PaidOut, 0) AS PaidOut,
           ISNULL(l.Purchases, 0) AS Purchases, ISNULL(l.SupReturns, 0) AS SupReturns,
           ISNULL(l.PayCheque, 0) AS PayCheque, ISNULL(l.PayCash, 0) AS PayCash, ISNULL(l.PayTransfer, 0) AS PayTransfer,
           CAST(ISNULL(t.StockIn, 0) AS DECIMAL(18,2)) AS StockIn, CAST(ISNULL(t.StockAdj, 0) AS DECIMAL(18,2)) AS StockAdj
    FROM @p p
    LEFT JOIN @s s   ON s.Period = p.Period
    LEFT JOIN @pay y ON y.Period = p.Period
    LEFT JOIN @cm c  ON c.Period = p.Period
    LEFT JOIN @sl l  ON l.Period = p.Period
    LEFT JOIN @st t  ON t.Period = p.Period
    ORDER BY p.Period;
END
GO

-- Stock now (active items): value at average cost of what is in stock, and how many items are in / zero / minus.
CREATE PROCEDURE dbo.z_sp_RptStockNow
    @LocationId INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SELECT COUNT(*) AS Items,
           SUM(CASE WHEN ISNULL(b.Qty, 0) > 0 THEN 1 ELSE 0 END) AS InStock,
           SUM(CASE WHEN ISNULL(b.Qty, 0) = 0 THEN 1 ELSE 0 END) AS ZeroStock,
           SUM(CASE WHEN ISNULL(b.Qty, 0) < 0 THEN 1 ELSE 0 END) AS MinusStock,
           CAST(ISNULL(SUM(CASE WHEN b.Qty > 0 THEN b.Qty * COALESCE(NULLIF(b.AvgCost, 0), d.CostPrice, 0) END), 0) AS DECIMAL(18,2)) AS CostValue,
           CAST(ISNULL(SUM(CASE WHEN b.Qty > 0 THEN b.Qty * ISNULL(d.RetailPrice, 0) END), 0) AS DECIMAL(18,2)) AS RetailValue
    FROM dbo.z_tb_Item i
    LEFT JOIN dbo.z_tb_ItemDet d     ON d.ItemId = i.ItemId AND d.LocationId = @LocationId
    LEFT JOIN dbo.z_tb_StockBalance b ON b.ItemId = i.ItemId AND b.LocationId = @LocationId
    WHERE i.Status = 1;
END
GO

-- Every money row from @FromDate to @ToDate (both included), newest first. Kind:
--   CHEQUE   cheque written (date = written date, or the cheque date when @ChequeByDate = 1); Cleared = out of the bank
--   TRANSFER supplier payment that is not a cheque and not cash at a till (bank transfer / marked as paid / correction)
--   PAIDOUT  till paid out (Party = the supplier when it paid a till payment request)
--   PAIDIN   till paid in
--   BANKIN   bill paid by bank transfer (refund negative)   CHEQUEIN  bill paid by cheque
CREATE PROCEDURE dbo.z_sp_RptMoney
    @FromDate DATE, @ToDate DATE, @LocationId INT = 1, @ChequeByDate BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From DATETIME = @FromDate, @To DATETIME = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME));

    SELECT x.Kind, x.TxnDate, CAST(x.Amount AS DECIMAL(18,2)) AS Amount, x.Party, x.Ref, x.Note, x.ChequeDate,
           x.Cleared, x.Terminal, x.SourceId
    FROM (
        SELECT CAST('CHEQUE' AS VARCHAR(10)) AS Kind,
               COALESCE(w.ChequeWrittenDate, w.CreatedDate) AS TxnDate, w.Amount,
               CAST(COALESCE(NULLIF(w.PayeeName, N''), NULLIF(w.SupplierName, N''), s.SuppName) AS NVARCHAR(200)) AS Party,
               CAST(CAST(w.ChequeNumber AS VARCHAR(20)) AS NVARCHAR(100)) AS Ref,
               CAST(CASE WHEN s.SuppName IS NOT NULL AND ISNULL(w.PayeeName, N'') <> s.SuppName THEN s.SuppName END AS NVARCHAR(400)) AS Note,
               w.ChequeDate, CAST(CASE WHEN w.IsDebited = 1 THEN 1 ELSE 0 END AS BIT) AS Cleared,
               CAST(NULL AS VARCHAR(20)) AS Terminal, w.ChequeId AS SourceId
        FROM dbo.z_tb_WrittenCheque w
        LEFT JOIN dbo.z_tb_Supplier s ON s.SuppId = w.SuppId
        WHERE (@ChequeByDate = 0 AND COALESCE(w.ChequeWrittenDate, w.CreatedDate) >= @From
                                 AND COALESCE(w.ChequeWrittenDate, w.CreatedDate) < @To)
           OR (@ChequeByDate = 1 AND w.ChequeDate >= @FromDate AND w.ChequeDate <= @ToDate)

        UNION ALL
        SELECT 'TRANSFER', CAST(l.TxnDate AS DATETIME), l.CreditAmount, CAST(s.SuppName AS NVARCHAR(200)),
               CAST(l.ReferenceId AS NVARCHAR(100)), CAST(l.Remark AS NVARCHAR(400)), NULL, NULL, NULL, l.LedgerId
        FROM dbo.z_tb_SupplierLedger l
        LEFT JOIN dbo.z_tb_Supplier s ON s.SuppId = l.SuppId
        WHERE l.Type = 2 AND l.ChequeId IS NULL AND l.TxnDate >= @FromDate AND l.TxnDate <= @ToDate
          AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_TillPayRequest r WHERE r.PaymentLedgerId = l.LedgerId)
          AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_TillPayReceipt r WHERE r.PaymentLedgerId = l.LedgerId)
          AND ISNULL(l.Remark, N'') NOT LIKE N'%[[]till [0-9]%'

        UNION ALL
        SELECT CASE WHEN m.Kind = 2 THEN 'PAIDIN' ELSE 'PAIDOUT' END, m.CreatedAt, m.Amount,
               CAST(sp.SuppName AS NVARCHAR(200)), CAST('Z ' + CAST(m.ZNo AS VARCHAR(10)) AS NVARCHAR(100)),
               CAST(m.Reason AS NVARCHAR(400)), NULL, NULL, t.TerminalCode, m.MoveId
        FROM dbo.z_tb_CashMovement m
        LEFT JOIN dbo.z_tb_Terminal t ON t.TerminalId = m.TerminalId
        OUTER APPLY (SELECT TOP 1 su.SuppName FROM dbo.z_tb_TillPayRequest r JOIN dbo.z_tb_Supplier su ON su.SuppId = r.SuppId
                     WHERE m.Kind = 3 AND r.PaidTerminalId = m.TerminalId AND r.PaidMoveId = m.MoveId) sp
        WHERE m.Kind IN (2, 3) AND m.Status <> 9 AND m.LocationId = @LocationId AND m.CreatedAt >= @From AND m.CreatedAt < @To

        UNION ALL
        SELECT CASE WHEN p.PayType = 5 THEN 'BANKIN' ELSE 'CHEQUEIN' END, i.InvDate,
               CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END,
               CAST(i.InvoiceNo AS NVARCHAR(200)), CAST(p.RefNo AS NVARCHAR(100)),
               CAST(CASE WHEN i.InvType = 2 THEN N'Refund' END AS NVARCHAR(400)), NULL, NULL, t.TerminalCode, i.InvoiceId
        FROM dbo.z_tb_SalesInvoice i
        JOIN dbo.z_tb_SalesPayment p ON p.InvoiceId = i.InvoiceId AND p.PayType IN (5, 6)
        LEFT JOIN dbo.z_tb_Terminal t ON t.TerminalId = i.TerminalId
        WHERE i.Status <> 9 AND i.LocationId = @LocationId AND i.InvDate >= @From AND i.InvDate < @To
    ) x
    ORDER BY x.TxnDate DESC, x.Kind;
END
GO

-- Every item (@Inactive 0: active, 1: deactivated) with its stock and the last sale / GRN / stock move / edit.
-- Last sale = the newest bill of this system (sales before it are not known).
CREATE PROCEDURE dbo.z_sp_RptStockHealth
    @LocationId INT = 1, @Inactive BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sale TABLE (ItemId INT PRIMARY KEY, LastSale DATETIME);
    INSERT @sale
    SELECT it.ItemId, MAX(s.InvDate)
    FROM dbo.z_tb_SalesInvoiceItem it
    JOIN dbo.z_tb_SalesInvoice s ON s.InvoiceId = it.InvoiceId
    WHERE s.Status <> 9 AND s.InvType <> 2 AND s.LocationId = @LocationId AND it.ItemId <> 0
    GROUP BY it.ItemId;

    DECLARE @move TABLE (ItemId INT PRIMARY KEY, LastIn DATETIME, LastMove DATETIME);
    INSERT @move
    SELECT ItemId, MAX(CASE WHEN TxnType = 1 THEN TxnDate END), MAX(TxnDate)
    FROM dbo.z_tb_StockLedger
    WHERE LocationId = @LocationId
    GROUP BY ItemId;

    SELECT i.ItemId, i.RefCode, i.Barcode, i.Descrip, c.CatName, su.SuppName,
           CAST(ISNULL(b.Qty, 0) AS DECIMAL(18,3)) AS Qty,
           CAST(COALESCE(NULLIF(b.AvgCost, 0), d.CostPrice, 0) AS DECIMAL(18,2)) AS UnitCost,
           CAST(ISNULL(b.Qty, 0) * COALESCE(NULLIF(b.AvgCost, 0), d.CostPrice, 0) AS DECIMAL(18,2)) AS CostValue,
           CAST(ISNULL(d.RetailPrice, 0) AS DECIMAL(18,2)) AS RetailPrice,
           sa.LastSale, mv.LastIn, mv.LastMove,
           CAST(CASE WHEN u.Edited < '19000101' THEN NULL ELSE u.Edited END AS DATETIME) AS Edited,
           CAST(CASE WHEN i.CDate < '19000101' THEN NULL ELSE i.CDate END AS DATETIME) AS Created,
           i.Status
    FROM dbo.z_tb_Item i
    LEFT JOIN dbo.z_tb_ItemDet d      ON d.ItemId = i.ItemId AND d.LocationId = @LocationId
    LEFT JOIN dbo.z_tb_StockBalance b ON b.ItemId = i.ItemId AND b.LocationId = @LocationId
    LEFT JOIN dbo.z_tb_Category c     ON c.CatId = i.CatId
    LEFT JOIN dbo.z_tb_Supplier su    ON su.SuppId = i.SupId
    LEFT JOIN @sale sa                ON sa.ItemId = i.ItemId
    LEFT JOIN @move mv                ON mv.ItemId = i.ItemId
    CROSS APPLY (SELECT CASE WHEN d.UDate > i.UDate THEN d.UDate ELSE i.UDate END AS Edited) u
    WHERE (@Inactive = 0 AND i.Status = 1) OR (@Inactive = 1 AND i.Status = 0)
    ORDER BY i.Descrip;
END
GO

-- Deactivate (@Status 0) or activate (@Status 1) items. UDate = now, so the tills take the change at the next item
-- sync. An item with stock (qty above 0) is not deactivated - the whole call is refused. Returns how many changed.
CREATE PROCEDURE dbo.z_sp_RptItemSetStatus
    @Ids dbo.z_tt_IdList READONLY, @Status INT, @LocationId INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    IF @Status NOT IN (0, 1)
    BEGIN
        RAISERROR('Status must be 0 (deactivate) or 1 (activate).', 16, 1);
        RETURN;
    END

    DECLARE @n INT, @msg NVARCHAR(400);
    IF @Status = 0
    BEGIN
        SELECT @n = COUNT(*) FROM @Ids x
        JOIN dbo.z_tb_StockBalance b ON b.ItemId = x.Id AND b.LocationId = @LocationId
        WHERE b.Qty > 0;
        IF @n > 0
        BEGIN
            SET @msg = CAST(@n AS NVARCHAR(10)) + N' of the items still have stock - adjust the stock to 0 first or untick them. Nothing was changed.';
            RAISERROR(@msg, 16, 1);
            RETURN;
        END
    END

    UPDATE i SET Status = @Status, UDate = SYSDATETIME()
    FROM dbo.z_tb_Item i JOIN @Ids x ON x.Id = i.ItemId
    WHERE i.Status <> @Status;

    SELECT @@ROWCOUNT AS Changed;
END
GO

SET NOEXEC OFF;
GO
PRINT 'U057 done: z_sp_RptPeriod, z_sp_RptStockNow, z_sp_RptMoney, z_sp_RptStockHealth, z_sp_RptItemSetStatus.';
GO
