/* =============================================================================
   U055_BackOffice_CashSettlement.sql   (2026-11-10)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer. Safe to run again.

   What changes (Cash Management saved, cash to bank from the real count):
     - new table z_tb_CashSettlement: one till's cash counted on the Cash Management page - the notes / coins counted,
       cash in / out, what goes back to the till (cashier cash + the notes / coins of 100 and below) and the cash to
       bank. Its slip has the barcode CS-<till>-<id>. Scanned on that till: at day end it fills the counted cash and
       the Z is linked to it (ZNo, sent with the Z - till U055); at the next opening cash it fills the opening cash.
     - procs z_sp_CashSettlementSave / List / Delete / LinkZ.
   The cheque Google sheet's Avg_Cash of a Z linked to a settlement = its cash to bank (else as U054).
   Same change in the full script: 34_BackOffice_CashSettlement.sql.

   Run BEFORE the new ItemApi (the old ItemApi keeps working after it):
     sqlcmd -S <server> -d easyway -E -I -b -i U055_BackOffice_CashSettlement.sql
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
IF OBJECT_ID(N'dbo.z_tb_ZReport', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Terminal', 'U') IS NULL
BEGIN
    RAISERROR('z_tb_ZReport / z_tb_Terminal are not in this database (run U003 first) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF OBJECT_ID(N'dbo.z_tb_CashSettlement', 'U') IS NULL
CREATE TABLE dbo.z_tb_CashSettlement (
    SettlementId   INT            IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_CashSettlement PRIMARY KEY,
    TerminalId     INT            NOT NULL,
    CashierId      VARCHAR(20)    NULL,            -- z_tb_User.LoginName, optional
    CountedCash    DECIMAL(18,2)  NOT NULL,        -- notes and coins counted (the till's counted cash at day end)
    CashIn         DECIMAL(18,2)  NOT NULL,        -- Cash Management "cash in" rows
    CashOut        DECIMAL(18,2)  NOT NULL,        -- Cash Management "cash out" rows
    CashierCash    DECIMAL(18,2)  NOT NULL,        -- big notes back to the till (15,000 by default)
    ReturnedCoins  DECIMAL(18,2)  NOT NULL,        -- the notes / coins of 100 and below, all back to the till
    ReturnedCash   DECIMAL(18,2)  NOT NULL,        -- CashierCash + ReturnedCoins = the next opening cash
    BankCash       DECIMAL(18,2)  NOT NULL,        -- CountedCash + CashIn - CashOut - ReturnedCash
    Detail         NVARCHAR(MAX)  NULL,            -- the page's tables (JSON) for a reprint
    ZNo            INT            NULL,            -- the till's Z closed with this slip scanned (NULL = not yet)
    ZLinkedAt      DATETIME       NULL,
    Status         INT            NOT NULL CONSTRAINT DF_z_tb_CashSettlement_Status DEFAULT (1),   -- 1 active, 0 cancelled
    CreatedBy      VARCHAR(50)    NULL,
    CreatedAt      DATETIME       NOT NULL CONSTRAINT DF_z_tb_CashSettlement_CreatedAt DEFAULT (GETDATE()),
    CancelledBy    VARCHAR(50)    NULL,
    CancelledAt    DATETIME       NULL
);
GO
-- one active settlement per Z
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_z_tb_CashSettlement_Z' AND object_id = OBJECT_ID('dbo.z_tb_CashSettlement'))
    CREATE UNIQUE INDEX UX_z_tb_CashSettlement_Z ON dbo.z_tb_CashSettlement (TerminalId, ZNo)
        WHERE ZNo IS NOT NULL AND Status = 1;
GO

IF OBJECT_ID('dbo.z_sp_CashSettlementList', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_CashSettlementList;
GO
-- Settlements newest first: one (@SettlementId), or those counted @From..@To (dates, both optional) matching @Search
-- (slip code CS-T01-12, slip no, till, cashier, counted by, Z no). OpeningUsed = the till took its returned cash as the
-- opening cash (a cash movement "Cash slip <id>" arrived from that till).
CREATE PROCEDURE dbo.z_sp_CashSettlementList
    @SettlementId INT          = NULL,
    @Top          INT          = 500,
    @From         DATE         = NULL,
    @To           DATE         = NULL,
    @Search       VARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');
    DECLARE @Like VARCHAR(160) = '%' + REPLACE(REPLACE(REPLACE(@Search, '[', '[[]'), '%', '[%]'), '_', '[_]') + '%';
    DECLARE @ToNext DATETIME = DATEADD(DAY, 1, CAST(@To AS DATETIME));

    SELECT TOP (CASE WHEN @SettlementId IS NULL THEN ISNULL(@Top, 500) ELSE 1 END)
           s.SettlementId, s.TerminalId, t.TerminalCode, s.CashierId, u.UserName AS CashierName,
           s.CountedCash, s.CashIn, s.CashOut, s.CashierCash, s.ReturnedCoins, s.ReturnedCash, s.BankCash, s.Detail,
           s.ZNo, z.BusinessDate, s.ZLinkedAt, s.Status, s.CreatedBy, s.CreatedAt, s.CancelledBy, s.CancelledAt,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM dbo.z_tb_CashMovement m
                                  WHERE m.TerminalId = s.TerminalId AND m.Kind = 1 AND m.Status = 1
                                    AND m.Reason = 'Cash slip ' + CAST(s.SettlementId AS VARCHAR(12)))
                     THEN 1 ELSE 0 END AS BIT) AS OpeningUsed
    FROM dbo.z_tb_CashSettlement s
    LEFT JOIN dbo.z_tb_Terminal t ON t.TerminalId = s.TerminalId
    LEFT JOIN dbo.z_tb_User u ON u.LoginName = s.CashierId
    LEFT JOIN dbo.z_tb_ZReport z ON z.TerminalId = s.TerminalId AND z.ZNo = s.ZNo
    WHERE (@SettlementId IS NOT NULL AND s.SettlementId = @SettlementId)
       OR (@SettlementId IS NULL
           AND (@From IS NULL OR s.CreatedAt >= @From)
           AND (@To IS NULL OR s.CreatedAt < @ToNext)
           AND (@Search IS NULL
                OR 'CS-' + ISNULL(t.TerminalCode, '') + '-' + CAST(s.SettlementId AS VARCHAR(12)) LIKE @Like
                OR CAST(s.SettlementId AS VARCHAR(12)) = @Search
                OR t.TerminalCode LIKE @Like OR t.TerminalName LIKE @Like
                OR s.CashierId LIKE @Like OR u.UserName LIKE @Like OR s.CreatedBy LIKE @Like
                OR CAST(s.ZNo AS VARCHAR(12)) = @Search))
    ORDER BY s.SettlementId DESC;
END
GO

IF OBJECT_ID('dbo.z_sp_CashSettlementSave', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_CashSettlementSave;
GO
-- A new settlement. Returned cash and cash to bank are worked out here (the page shows the same figures).
CREATE PROCEDURE dbo.z_sp_CashSettlementSave
    @TerminalId    INT,
    @CashierId     VARCHAR(20)   = NULL,
    @CountedCash   DECIMAL(18,2),
    @CashIn        DECIMAL(18,2) = 0,
    @CashOut       DECIMAL(18,2) = 0,
    @CashierCash   DECIMAL(18,2),
    @ReturnedCoins DECIMAL(18,2),
    @Detail        NVARCHAR(MAX) = NULL,
    @CreatedBy     VARCHAR(50)   = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Terminal WHERE TerminalId = @TerminalId AND Status = 1)
    BEGIN RAISERROR('Choose a till - this one is not registered or is disabled.', 16, 1); RETURN; END
    IF @CountedCash IS NULL OR @CountedCash <= 0
    BEGIN RAISERROR('Enter the counted notes and coins.', 16, 1); RETURN; END
    IF @CashIn < 0 OR @CashOut < 0 OR @CashierCash < 0 OR @ReturnedCoins < 0
    BEGIN RAISERROR('Amounts can not be below 0.', 16, 1); RETURN; END
    IF @CashierId = '' SET @CashierId = NULL;
    IF @CashierId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_User WHERE LoginName = @CashierId)
    BEGIN RAISERROR('The cashier is not a user.', 16, 1); RETURN; END

    DECLARE @Returned DECIMAL(18,2) = ISNULL(@CashierCash, 0) + ISNULL(@ReturnedCoins, 0);
    DECLARE @Bank DECIMAL(18,2) = @CountedCash + ISNULL(@CashIn, 0) - ISNULL(@CashOut, 0) - @Returned;
    IF @Bank < 0
    BEGIN RAISERROR('Cash to bank is below 0 - more goes back to the till than was counted.', 16, 1); RETURN; END

    INSERT dbo.z_tb_CashSettlement
        (TerminalId, CashierId, CountedCash, CashIn, CashOut, CashierCash, ReturnedCoins, ReturnedCash, BankCash, Detail, CreatedBy)
    VALUES (@TerminalId, @CashierId, @CountedCash, ISNULL(@CashIn, 0), ISNULL(@CashOut, 0), ISNULL(@CashierCash, 0),
            ISNULL(@ReturnedCoins, 0), @Returned, @Bank, @Detail, @CreatedBy);

    DECLARE @Id INT = SCOPE_IDENTITY();
    EXEC dbo.z_sp_CashSettlementList @SettlementId = @Id;
END
GO

IF OBJECT_ID('dbo.z_sp_CashSettlementCancel', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_CashSettlementCancel;
GO
IF OBJECT_ID('dbo.z_sp_CashSettlementDelete', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_CashSettlementDelete;
GO
-- A wrong count (counted again): deleted while no Z is closed with it and its opening cash is not taken yet.
-- The printed slip then can not be scanned (not found).
CREATE PROCEDURE dbo.z_sp_CashSettlementDelete
    @SettlementId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @T INT, @Z INT;
    SELECT @T = TerminalId, @Z = ZNo FROM dbo.z_tb_CashSettlement WITH (UPDLOCK) WHERE SettlementId = @SettlementId;
    IF @T IS NULL
    BEGIN RAISERROR('Cash slip not found.', 16, 1); RETURN; END
    IF @Z IS NOT NULL
    BEGIN RAISERROR('The till already closed Z %d with this cash slip - it can not be deleted.', 16, 1, @Z); RETURN; END
    IF EXISTS (SELECT 1 FROM dbo.z_tb_CashMovement WHERE TerminalId = @T AND Kind = 1 AND Status = 1
                 AND Reason = 'Cash slip ' + CAST(@SettlementId AS VARCHAR(12)))
    BEGIN RAISERROR('The till already took this cash slip as its opening cash - it can not be deleted.', 16, 1); RETURN; END

    DELETE dbo.z_tb_CashSettlement WHERE SettlementId = @SettlementId;
END
GO

IF OBJECT_ID('dbo.z_sp_CashSettlementLinkZ', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_CashSettlementLinkZ;
GO
-- A Z arrived from a till that closed it with this slip scanned. Again with the same Z = nothing changes.
-- Another Z / another till / cancelled → error (the Z itself is already saved; the ItemApi only logs it).
CREATE PROCEDURE dbo.z_sp_CashSettlementLinkZ
    @SettlementId INT,
    @TerminalId   INT,
    @ZNo          INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @T INT, @Z INT, @Status INT;
    SELECT @T = TerminalId, @Z = ZNo, @Status = Status FROM dbo.z_tb_CashSettlement WITH (UPDLOCK) WHERE SettlementId = @SettlementId;
    IF @T IS NULL
    BEGIN RAISERROR('Cash slip %d not found.', 16, 1, @SettlementId); RETURN; END
    IF @T <> @TerminalId
    BEGIN RAISERROR('Cash slip %d is for another till.', 16, 1, @SettlementId); RETURN; END
    IF @Status <> 1
    BEGIN RAISERROR('Cash slip %d is cancelled.', 16, 1, @SettlementId); RETURN; END
    IF @Z = @ZNo RETURN;
    IF @Z IS NOT NULL
    BEGIN RAISERROR('Cash slip %d is already on Z %d.', 16, 1, @SettlementId, @Z); RETURN; END
    IF EXISTS (SELECT 1 FROM dbo.z_tb_CashSettlement WHERE TerminalId = @TerminalId AND ZNo = @ZNo AND Status = 1)
    BEGIN RAISERROR('Z %d already has another cash slip.', 16, 1, @ZNo); RETURN; END

    UPDATE dbo.z_tb_CashSettlement SET ZNo = @ZNo, ZLinkedAt = GETDATE() WHERE SettlementId = @SettlementId;
END
GO
SET NOEXEC OFF;
GO
PRINT 'U055 back office: cash settlement (z_tb_CashSettlement, z_sp_CashSettlementSave / List / Delete / LinkZ).';
GO
