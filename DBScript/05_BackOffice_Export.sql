/* =============================================================================
   05_BackOffice_Export.sql
   Run on: back office db (easyway), AFTER 01_BackOffice_Stock.sql. Prefix z_. Re-runnable.
   File exports to a folder (first one: the weighing scale item file). API: api/Export (ExportController).
   Docs/StockSystem.md §6.10.

   Scale file (export SCALE): one line per scale item, CRLF, no header:  PLU#Description#Price#
     - scale item = active item (Status 1) whose unit at the location is KGS (z_tb_ItemDet.UnitId → z_tb_Unit)
     - PLU = RefCode, digits only, padded to 5 with leading zeros (5 → 00005); longer / not digits = skipped
     - price = z_tb_ItemDet.RetailPrice (price per kg), 2 decimals
   The file is written only when someone presses Export. z_tb_ScaleExportItem keeps what the last export sent,
   so the page can show what changed since then (new item, price changed, name changed, removed).
   easyway is at compatibility level 100 (SQL 2008): no IIF / FORMAT / CONCAT.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- One row per export type. FolderPath is a folder on the API SERVER (local drive or \\pc\share).
IF OBJECT_ID('dbo.z_tb_ExportSetting', 'U') IS NULL
CREATE TABLE dbo.z_tb_ExportSetting (
    ExportCode     VARCHAR(20)   NOT NULL PRIMARY KEY,
    Name           NVARCHAR(50)  NOT NULL,
    FolderPath     NVARCHAR(260) NULL,
    FileName       NVARCHAR(100) NOT NULL,
    NameMaxLength  INT           NOT NULL DEFAULT 0,      -- 0 = no limit; longer names are cut
    LastExportAt   DATETIME      NULL,
    LastExportBy   INT           NULL,
    LastLineCount  INT           NULL,
    UserId         INT           NULL,
    UDate          DATETIME      NOT NULL DEFAULT GETDATE()
);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_ExportSetting WHERE ExportCode = 'SCALE')
    INSERT INTO dbo.z_tb_ExportSetting (ExportCode, Name, FolderPath, FileName, NameMaxLength)
    VALUES ('SCALE', N'Weighing scale items', NULL, N'ScaleItem.txt', 30);
GO

-- Every export attempt. Status 1 written, 9 failed (Error says why).
IF OBJECT_ID('dbo.z_tb_ExportLog', 'U') IS NULL
CREATE TABLE dbo.z_tb_ExportLog (
    ExportLogId    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ExportCode     VARCHAR(20)   NOT NULL,
    FilePath       NVARCHAR(400) NULL,
    LineCount      INT           NOT NULL DEFAULT 0,
    SkippedCount   INT           NOT NULL DEFAULT 0,
    Status         INT           NOT NULL,
    Error          NVARCHAR(500) NULL,
    UserId         INT           NULL,
    CDate          DATETIME      NOT NULL DEFAULT GETDATE()
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_ExportLog_Code')
    CREATE INDEX IX_z_tb_ExportLog_Code ON dbo.z_tb_ExportLog (ExportCode, CDate DESC);
GO

-- What the last successful SCALE export sent (replaced on every export).
IF OBJECT_ID('dbo.z_tb_ScaleExportItem', 'U') IS NULL
CREATE TABLE dbo.z_tb_ScaleExportItem (
    ItemId      INT           NOT NULL PRIMARY KEY,
    Plu         VARCHAR(5)    NOT NULL,
    Descrip     NVARCHAR(100) NOT NULL,
    Price       DECIMAL(18,2) NOT NULL,
    ExportedAt  DATETIME      NOT NULL
);
GO
