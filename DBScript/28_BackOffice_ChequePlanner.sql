/* =============================================================================
   28_BackOffice_ChequePlanner.sql
   Run on: back office db (easyway). Prefix z_. Re-runnable. SQL Server 2008 R2 and newer.
   Cheque planner (Docs/StockSystem.md 6.34). API: api/ChequePlanner (ChequePlannerController).
   Back office page: Payments & Cash > Cheque Planner.

   "Can I write this cheque?" from the database - separate from the Google sheet (AsankaTemp), which the Cheque
   Writer keeps updating as before.
   - Money in per day: a day with Z reports uses the real figures - cash in hand (cash sales + paid in - paid out,
     not the opening float) and card sales (+ bank transfers) of its Zs. A day with no Z yet uses the expected
     takings: z_tb_CashPlanDay for that day, else the average in z_tb_CashPlanConfig (400,000 cash).
   - Money out per day: written cheques (z_tb_WrittenCheque; IsDebited = 1 is already out of the bank) and planned
     cheques (z_tb_CashPlanCheque, not written yet). A planned cheque is left out once a written cheque with the same
     date and amount for the same supplier exists.
   - z_tb_CashPlanConfig (one row): the bank balance typed on the page, the amount always to keep, the averages.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO
IF OBJECT_ID(N'dbo.z_tb_WrittenCheque', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_ZReport', 'U') IS NULL
   OR OBJECT_ID(N'dbo.z_tb_CashMovement', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_WrittenCheque / z_tb_ZReport / z_tb_CashMovement not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. tables ------------------------------------------------------------------
IF OBJECT_ID(N'dbo.z_tb_CashPlanConfig', 'U') IS NULL
CREATE TABLE dbo.z_tb_CashPlanConfig (
    ConfigId       INT           NOT NULL CONSTRAINT PK_z_tb_CashPlanConfig PRIMARY KEY,   -- always 1
    AvgCash        DECIMAL(18,2) NOT NULL CONSTRAINT DF_z_tb_CashPlanConfig_AvgCash DEFAULT (400000),
    AvgCard        DECIMAL(18,2) NOT NULL CONSTRAINT DF_z_tb_CashPlanConfig_AvgCard DEFAULT (0),
    KeepMin        DECIMAL(18,2) NOT NULL CONSTRAINT DF_z_tb_CashPlanConfig_KeepMin DEFAULT (0),
    BankBalance    DECIMAL(18,2) NULL,          -- typed on the page; NULL = not entered
    BankBalanceAt  DATETIME      NULL,
    TodayNotBanked BIT           NOT NULL CONSTRAINT DF_z_tb_CashPlanConfig_TodayNotBanked DEFAULT (1),  -- add today's takings
    OverdueDays    INT           NOT NULL CONSTRAINT DF_z_tb_CashPlanConfig_OverdueDays DEFAULT (45),    -- look back for cheques not debited
    UpdatedAt      DATETIME      NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_CashPlanConfig WHERE ConfigId = 1)
    INSERT dbo.z_tb_CashPlanConfig (ConfigId) VALUES (1);
GO

-- expected takings of one day (a holiday, a big day); NULL = the average
IF OBJECT_ID(N'dbo.z_tb_CashPlanDay', 'U') IS NULL
CREATE TABLE dbo.z_tb_CashPlanDay (
    PlanDate     DATE          NOT NULL CONSTRAINT PK_z_tb_CashPlanDay PRIMARY KEY,
    ExpectedCash DECIMAL(18,2) NULL,
    ExpectedCard DECIMAL(18,2) NULL,
    Note         NVARCHAR(200) NULL,
    UpdatedAt    DATETIME      NULL
);
GO

-- a cheque planned for a day, not written yet
IF OBJECT_ID(N'dbo.z_tb_CashPlanCheque', 'U') IS NULL
CREATE TABLE dbo.z_tb_CashPlanCheque (
    PlanId       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_CashPlanCheque PRIMARY KEY,
    PlanDate     DATE          NOT NULL,
    SupplierName NVARCHAR(150) NOT NULL,
    SuppId       INT           NULL,
    Amount       DECIMAL(18,2) NOT NULL,
    Note         NVARCHAR(200) NULL,
    Status       INT           NOT NULL CONSTRAINT DF_z_tb_CashPlanCheque_Status DEFAULT (1),   -- 1 planned, 9 removed
    CreatedAt    DATETIME      NOT NULL CONSTRAINT DF_z_tb_CashPlanCheque_CreatedAt DEFAULT (GETDATE()),
    UpdatedAt    DATETIME      NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_CashPlanCheque_PlanDate' AND object_id = OBJECT_ID(N'dbo.z_tb_CashPlanCheque'))
    CREATE INDEX IX_z_tb_CashPlanCheque_PlanDate ON dbo.z_tb_CashPlanCheque (PlanDate) INCLUDE (Amount, Status);
GO

-- 2. procs -------------------------------------------------------------------
-- one row per day @From..@To: the Z figures (ZCount 0 = no Z yet) and the day's expected takings
IF OBJECT_ID(N'dbo.z_sp_ChequePlanDays', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_ChequePlanDays;
GO
CREATE PROCEDURE dbo.z_sp_ChequePlanDays
    @From DATE, @To DATE, @LocationId INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    WITH d AS (
        SELECT @From AS D
        UNION ALL
        SELECT DATEADD(DAY, 1, D) FROM d WHERE D < @To
    )
    SELECT d.D AS PlanDate,
           ISNULL(z.ZCount, 0) AS ZCount,
           ISNULL(z.CashSales, 0) AS CashSales,
           ISNULL(m.PaidIn, 0) AS PaidIn,
           ISNULL(m.PaidOut, 0) AS PaidOut,
           ISNULL(z.CashSales, 0) + ISNULL(m.PaidIn, 0) - ISNULL(m.PaidOut, 0) AS CashInHand,
           ISNULL(z.CardAmount, 0) AS CardAmount,
           z.CardSettlement,
           ISNULL(z.BankAmount, 0) AS BankAmount,
           p.ExpectedCash, p.ExpectedCard, p.Note
    FROM d
    LEFT JOIN (SELECT BusinessDate, COUNT(*) AS ZCount, SUM(CashAmount) AS CashSales, SUM(CardAmount) AS CardAmount,
                      SUM(CardSettlement) AS CardSettlement, SUM(ISNULL(BankAmount, 0)) AS BankAmount
               FROM dbo.z_tb_ZReport
               WHERE LocationId = @LocationId AND BusinessDate BETWEEN @From AND @To
               GROUP BY BusinessDate) z ON z.BusinessDate = d.D
    LEFT JOIN (SELECT zz.BusinessDate,
                      SUM(CASE WHEN c.Kind = 2 THEN c.Amount ELSE 0 END) AS PaidIn,
                      SUM(CASE WHEN c.Kind = 3 THEN c.Amount ELSE 0 END) AS PaidOut
               FROM dbo.z_tb_CashMovement c
               JOIN dbo.z_tb_ZReport zz ON zz.TerminalId = c.TerminalId AND zz.ZNo = c.ZNo
               WHERE c.Status = 1 AND zz.LocationId = @LocationId AND zz.BusinessDate BETWEEN @From AND @To
               GROUP BY zz.BusinessDate) m ON m.BusinessDate = d.D
    LEFT JOIN dbo.z_tb_CashPlanDay p ON p.PlanDate = d.D
    WHERE @From <= @To
    ORDER BY d.D
    OPTION (MAXRECURSION 2000);
END
GO

-- written (Source 1) and planned (Source 2) cheques dated @From..@To, and the ones dated @OverdueFrom..@From - 1 that
-- the bank has not debited yet
IF OBJECT_ID(N'dbo.z_sp_ChequePlanCheques', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_ChequePlanCheques;
GO
CREATE PROCEDURE dbo.z_sp_ChequePlanCheques
    @From DATE, @To DATE, @OverdueFrom DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @OverdueFrom IS NULL OR @OverdueFrom > @From SET @OverdueFrom = @From;

    SELECT 1 AS Source, w.ChequeId AS Id, w.ChequeNumber, w.ChequeDate AS PlanDate, w.Amount,
           ISNULL(NULLIF(LTRIM(RTRIM(w.SupplierName)), N''), ISNULL(w.PayeeName, N'')) AS Name,
           w.SuppId, CAST(CASE WHEN w.IsDebited = 1 THEN 1 ELSE 0 END AS BIT) AS IsDebited,
           CAST(NULL AS NVARCHAR(200)) AS Note
    FROM dbo.z_tb_WrittenCheque w
    WHERE w.ChequeDate BETWEEN @From AND @To
       OR (w.ChequeDate >= @OverdueFrom AND w.ChequeDate < @From AND ISNULL(w.IsDebited, 0) = 0)
    UNION ALL
    SELECT 2, p.PlanId, NULL, p.PlanDate, p.Amount, p.SupplierName, p.SuppId, CAST(0 AS BIT), p.Note
    FROM dbo.z_tb_CashPlanCheque p
    WHERE p.Status = 1
      AND p.PlanDate >= @OverdueFrom AND p.PlanDate <= @To
      AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_WrittenCheque w
                      WHERE w.ChequeDate = p.PlanDate AND w.Amount = p.Amount
                        AND (w.SuppId = p.SuppId OR LTRIM(RTRIM(w.SupplierName)) = LTRIM(RTRIM(p.SupplierName))))
    ORDER BY PlanDate, Source, Id;
END
GO
