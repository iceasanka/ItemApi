/* =============================================================================
   F003_BackOffice_ZDateFirstBill.sql   (2026-11-03)
   One-time data fix on the back office db (easyway). SQL Server 2008 R2 and newer.
   STATUS: not run on production yet. Dev run 2026-11-03.

   A Z took its date when it opened on the till (fixed by U044). The Z
   opened right after a day end at night got that night's date, although
   its bills were made the next day, so the Tills page and Day Reports
   showed it under the wrong day (dev T01: Z12 dated 2 Nov, bills 3 Nov;
   Z10 dated 20 Oct, its bill 22 Oct).

   This sets BusinessDate = the date of the Z's first bill (uploaded bills,
   z_tb_SalesInvoice) on every Z whose date is before its first bill.
   Totals, status and reconcile are not changed. A resend of a reconciled
   Z is ignored, so the till fix does not reach here - run both:
   F003_Till_ZDateFirstBill.sql on each till, this one on easyway.

   @DryRun = 1 only lists; set it to 0 and run again to do it.
   ============================================================================= */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @DryRun BIT;
SET @DryRun = 1;

IF OBJECT_ID(N'dbo.z_tb_ZReport', 'U') IS NULL
   OR OBJECT_ID(N'dbo.z_tb_SalesInvoice', 'U') IS NULL
BEGIN
    RAISERROR('Not the back office database - nothing was changed.', 16, 1);
    RETURN;
END

DECLARE @Fix TABLE (ZId INT PRIMARY KEY, TerminalId INT, ZNo INT,
                    OldDate DATE, NewDate DATE, Bills INT);

INSERT @Fix (ZId, TerminalId, ZNo, OldDate, NewDate, Bills)
SELECT z.ZId, z.TerminalId, z.ZNo, z.BusinessDate,
       CAST(MIN(s.InvDate) AS DATE), COUNT(*)
FROM dbo.z_tb_ZReport z
JOIN dbo.z_tb_SalesInvoice s
  ON s.TerminalId = z.TerminalId AND s.ZNo = z.ZNo
 AND s.LocationId = z.LocationId
GROUP BY z.ZId, z.TerminalId, z.ZNo, z.BusinessDate
HAVING z.BusinessDate < CAST(MIN(s.InvDate) AS DATE);

SELECT TerminalId, ZNo, OldDate, NewDate, Bills
FROM @Fix ORDER BY TerminalId, ZNo;

IF NOT EXISTS (SELECT 1 FROM @Fix)
BEGIN
    PRINT 'F003 back office: no Z to fix.';
    RETURN;
END

IF @DryRun = 1
BEGIN
    PRINT 'F003 back office: DRY RUN - nothing changed. Set @DryRun = 0.';
    RETURN;
END

BEGIN TRAN;
    UPDATE z SET BusinessDate = f.NewDate
    FROM dbo.z_tb_ZReport z
    JOIN @Fix f ON f.ZId = z.ZId;
COMMIT;

PRINT 'F003 back office: Z dates set to their first bill.';
