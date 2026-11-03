/* =============================================================================
   F003_Till_ZDateFirstBill.sql   (2026-11-03)
   One-time data fix on a till db (z_pos_fnt_db). SQL Server 2008 R2 and newer.
   STATUS: not run on production yet. Dev till (T01) run 2026-11-03.

   A Z took its date when it opened (fixed by U044). The Z opened right
   after a day end at night got that night's date, although its bills were
   made the next day (dev T01: Z12 dated 2 Nov, bills 3 Nov; Z10 dated
   20 Oct, its bill 22 Oct).

   This sets BusinessDate = the date of the Z's first bill, on every CLOSED
   Z whose date is before its first bill. The open Z is left to U044.
   OpenedAt / ClosedAt / totals are not changed.
   Run on each till, and F003_BackOffice_ZDateFirstBill.sql on easyway
   (a Z sent up already is not sent again).

   @DryRun = 1 only lists; set it to 0 and run again to do it.
   ============================================================================= */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @DryRun BIT;
SET @DryRun = 1;

IF OBJECT_ID(N'dbo.zf_tb_ZReport', 'U') IS NULL
   OR OBJECT_ID(N'dbo.zf_tb_Invoice', 'U') IS NULL
BEGIN
    RAISERROR('Not a till database - nothing was changed.', 16, 1);
    RETURN;
END

DECLARE @Fix TABLE (ZNo INT PRIMARY KEY, OldDate DATE,
                    NewDate DATE, Bills INT);

INSERT @Fix (ZNo, OldDate, NewDate, Bills)
SELECT z.ZNo, z.BusinessDate,
       CAST(MIN(i.InvDate) AS DATE), COUNT(*)
FROM dbo.zf_tb_ZReport z
JOIN dbo.zf_tb_Invoice i ON i.ZNo = z.ZNo
WHERE z.Status <> 0
GROUP BY z.ZNo, z.BusinessDate
HAVING z.BusinessDate < CAST(MIN(i.InvDate) AS DATE);

SELECT ZNo, OldDate, NewDate, Bills FROM @Fix ORDER BY ZNo;

IF NOT EXISTS (SELECT 1 FROM @Fix)
BEGIN
    PRINT 'F003 till: no Z to fix.';
    RETURN;
END

IF @DryRun = 1
BEGIN
    PRINT 'F003 till: DRY RUN - nothing changed. Set @DryRun = 0.';
    RETURN;
END

BEGIN TRAN;
    UPDATE z SET BusinessDate = f.NewDate
    FROM dbo.zf_tb_ZReport z
    JOIN @Fix f ON f.ZNo = z.ZNo;
COMMIT;

PRINT 'F003 till: Z dates set to their first bill.';
