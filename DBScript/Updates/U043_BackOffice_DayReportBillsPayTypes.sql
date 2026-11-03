/* =============================================================================
   U043_BackOffice_DayReportBillsPayTypes.sql   (2026-11-03)
   Update for a back office db (easyway) that is ALREADY deployed (U018 + U021 run). SQL Server 2008 R2 and newer.
   Safe to run again. No table or data change.

   What changes (back office Day Reports > Bills tab, Docs/StockSystem.md 6.25): bank transfer and cheque on their own.
     - z_sp_DayReportBills: new columns Bank (PayType 5), Cheque (PayType 6) and PayRef (the transfer reference /
       cheque number of the bill). OtherPay is now only the rest (3 credit, 4 voucher, 8 points ...) - it was every
       payment that is not cash or card. The till Z and the per-till Day Report totals are not changed.
   Same change in the full script: 21_BackOffice_DayReports.sql (this script = that proc, with U021's profit columns).

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U043_BackOffice_DayReportBillsPayTypes.sql
   Then: the new ItemApi and the back office UI straight after it (an old UI would show transfers / cheques in no
         column of the Bills tab until it is updated; the old ItemApi keeps working - extra columns not read).
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_SalesInvoice', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_SalesPayment', 'U') IS NULL
   OR OBJECT_ID(N'dbo.z_tb_ItemDet', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_SalesInvoice / z_tb_SalesPayment / z_tb_ItemDet not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.z_sp_DayReportBills', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_DayReportBills;
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
    DECLARE @From DATETIME, @To DATETIME;
    SET @From = @Date;
    SET @To = DATEADD(DAY, 1, @From);

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
    WHERE s.InvDate >= @From AND s.InvDate < @To AND s.LocationId = @LocationId
      AND (@TerminalId IS NULL OR s.TerminalId = @TerminalId)
    ORDER BY s.InvDate DESC, s.InvoiceId DESC;
END
GO
SET NOEXEC OFF;
GO
PRINT 'U043 back office: bank transfer / cheque on the Day Reports bills list (z_sp_DayReportBills).';
GO
