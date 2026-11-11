/* =============================================================================
   U058_BackOffice_ZDateDayEnd.sql   (2026-11-11)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer. Safe to run again.
   No table change. Zs already stored keep their date (not corrected).

   What was wrong (production, 10 Nov): the till was opened at night right after the 9 Nov day end (T01 Z20 10:14 PM,
   T02 Z18 9:47 PM) and balanced on the night of 10 Nov, but the Zs were dated 9 Nov - a Z keeps the date of its
   first bill, and a bill / refund made that night (or a till without U044) kept it on the 9th. Tills & Z Reports,
   Day Reports and the cheque sheet showed 10 Nov's takings on 9 Nov.

   New rule: a Z's date = the day it was balanced (its day end); a day end before 06:00 counts for the day before
   (a till that sold past midnight stays on its start day, as U056), but never before the day the Z opened.
     - ItemApi (new): sets BusinessDate from the Z's ClosedAt when the Z arrives (api/Sync/ZReport) and writes the
       cheque sheet for the new day and the till's day.
     - Till (U058_Till_ZDateDayEnd.sql): zf_sp_CloseZ dates the Z the same way, so the till Z slip matches.
     - Here: z_fn_DayZs (Day Reports) shows a Z not balanced yet on the day of its LAST bill / cash movement (before
       06:00 = the day before), not its first - the open Z moves to today as soon as it sells today, like it will be
       dated at the day end. Closed Zs: by BusinessDate as before.
   Same function in the full script 35_BackOffice_DayReportBusinessDate.sql.

   Run, then the new ItemApi:
     sqlcmd -S <server> -d easyway -E -I -b -i U058_BackOffice_ZDateDayEnd.sql
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_fn_DayZs', 'IF') IS NULL
BEGIN
    RAISERROR('z_fn_DayZs is not in this database (run U056 first) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- The Zs of a day: closed Zs by BusinessDate (= the day end day, U058); a Z not balanced yet (no z_tb_ZReport row)
-- on the day of its last bill / cash movement, the day running 06:00 to 06:00. FromAt = the till's previous Z
-- close (else OpenedAt), ToAt = ClosedAt (NULL while open).
ALTER FUNCTION dbo.z_fn_DayZs (@Date DATE, @LocationId INT, @TerminalId INT)
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
            AND s.InvDate >= DATEADD(HOUR, 6, CAST(@Date AS DATETIME)) AND s.InvDate < DATEADD(HOUR, 30, CAST(@Date AS DATETIME))
            AND (@TerminalId IS NULL OR s.TerminalId = @TerminalId)
          UNION
          SELECT m.TerminalId, m.ZNo FROM dbo.z_tb_CashMovement m
          WHERE m.LocationId = @LocationId AND m.ZNo IS NOT NULL
            AND m.CreatedAt >= DATEADD(HOUR, 6, CAST(@Date AS DATETIME)) AND m.CreatedAt < DATEADD(HOUR, 30, CAST(@Date AS DATETIME))
            AND (@TerminalId IS NULL OR m.TerminalId = @TerminalId)) o
    WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_ZReport z WHERE z.TerminalId = o.TerminalId AND z.ZNo = o.ZNo)
      AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_SalesInvoice s
                      WHERE s.TerminalId = o.TerminalId AND s.ZNo = o.ZNo AND s.InvDate >= DATEADD(HOUR, 30, CAST(@Date AS DATETIME)))
      AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_CashMovement m
                      WHERE m.TerminalId = o.TerminalId AND m.ZNo = o.ZNo AND m.CreatedAt >= DATEADD(HOUR, 30, CAST(@Date AS DATETIME)));
GO

SET NOEXEC OFF;
GO
PRINT 'U058 done: z_fn_DayZs - open Zs on the day of their last bill / cash movement (06:00 to 06:00).';
GO
