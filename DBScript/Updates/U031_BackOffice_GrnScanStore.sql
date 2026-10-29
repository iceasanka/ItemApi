/* =============================================================================
   U031_BackOffice_GrnScanStore.sql   (2026-10-29)
   Update for the back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. No data is changed (one new, empty table). Needs U029_BackOffice_GrnScan.sql.

   What changes (GRN scan - saved scans, Docs/StockSystem.md 6.31):
     - table z_tb_GrnScan: every invoice read is kept (what was read, the fixes, the picks, the lines left out), so the
       matching can go on another day without reading the photo again. The GRN Scan page lists them (Saved scans),
       opens one, and the user flushes the ones that are done (row + photos deleted).
   Same objects in the full script: 25_BackOffice_GrnScan.sql (section 5).

   Order: this script, then the new ItemApi (the old ItemApi keeps working after it), then the back office UI.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_Supplier', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_Supplier not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.z_tb_SupplierItemMap', 'U') IS NULL
BEGIN
    RAISERROR('Run U029_BackOffice_GrnScan.sql first - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 5. saved scans (U031)
-- Every read is kept here, so matching can go on another day without reading the photo again: what was read (with
-- the fixes made on the page) and the page's picks / lines left out. The photos stay in GrnScan:SaveFolder\<Folder>.
-- Status 0 open, 1 GRN draft made (GrnNo). Flushed by the user when done (row and photo folder deleted by ItemApi).
IF OBJECT_ID(N'dbo.z_tb_GrnScan', 'U') IS NULL
CREATE TABLE dbo.z_tb_GrnScan (
    ScanId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_GrnScan PRIMARY KEY,
    SuppId      INT            NULL,           -- z_tb_Supplier.SuppId (chosen on the page)
    InvoiceNo   NVARCHAR(50)   NULL,           -- as read
    InvoiceDate NVARCHAR(20)   NULL,
    Folder      NVARCHAR(100)  NULL,           -- the photos: GrnScan:SaveFolder\<Folder>\page1.jpg ...
    Pages       INT            NOT NULL CONSTRAINT DF_z_tb_GrnScan_Pages DEFAULT (0),
    Lines       INT            NOT NULL CONSTRAINT DF_z_tb_GrnScan_Lines DEFAULT (0),
    Matched     INT            NOT NULL CONSTRAINT DF_z_tb_GrnScan_Matched DEFAULT (0),   -- lines with our item
    Status      INT            NOT NULL CONSTRAINT DF_z_tb_GrnScan_Status DEFAULT (0),    -- 0 open, 1 GRN draft made
    GrnNo       VARCHAR(20)    NULL,
    ResultJson  NVARCHAR(MAX)  NOT NULL,       -- header, lines, checks (api/GrnScan/Read answer, with the page's fixes)
    StateJson   NVARCHAR(MAX)  NULL,           -- the page's picks and lines left out
    CreatedAt   DATETIME       NOT NULL CONSTRAINT DF_z_tb_GrnScan_CreatedAt DEFAULT (GETDATE()),
    CreatedBy   INT            NULL,
    UpdatedAt   DATETIME       NULL,
    UpdatedBy   INT            NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_GrnScan_Status')
    CREATE INDEX IX_z_tb_GrnScan_Status ON dbo.z_tb_GrnScan (Status, CreatedAt);
GO

PRINT 'U031_BackOffice_GrnScanStore done.';
GO
