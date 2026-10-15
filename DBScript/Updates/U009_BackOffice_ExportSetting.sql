/* =============================================================================
   U009_BackOffice_ExportSetting.sql   (2026-10-15)
   Run on: back office db (easyway). SQL Server 2008 R2 and newer. Safe to run again.
   Needs: nothing new in ItemApi / TillService.

   The Exports page showed "No exports set up" on production: z_tb_ExportSetting had no SCALE row there.
   This adds the SCALE (weighing scale items) row when it is missing, and the export tables when they are missing -
   the same as 05_BackOffice_Export.sql (StockSystem.md section 6.10). A row that is already there is not changed
   (its folder stays). After it: Exports page -> Settings -> set the folder -> Export now.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_Item', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_ItemDet', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_Item / z_tb_ItemDet not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
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
BEGIN
    INSERT INTO dbo.z_tb_ExportSetting (ExportCode, Name, FolderPath, FileName, NameMaxLength)
    VALUES ('SCALE', N'Weighing scale items', NULL, N'ScaleItem.txt', 30);
    PRINT 'U009: SCALE export added - set its folder on the Exports page.';
END
ELSE
    PRINT 'U009: SCALE export was already there - not changed.';
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
SELECT ExportCode, Name, FolderPath, FileName, NameMaxLength, LastExportAt FROM dbo.z_tb_ExportSetting;
GO
SET NOEXEC OFF;
GO
