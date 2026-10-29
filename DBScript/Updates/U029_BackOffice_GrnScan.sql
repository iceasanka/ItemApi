/* =============================================================================
   U029_BackOffice_GrnScan.sql   (2026-10-29)
   Update for the back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. No data is changed (one new, empty table).

   What changes (GRN scan step 2 - matching invoice lines to our items, Docs/StockSystem.md 6.31):
     - table z_tb_SupplierItemMap: supplier + the supplier's item code (or their item name when there is no code)
       -> our ItemId, with the supplier's name of the item and the case size. Filled from the GRN Scan page when a
       line is matched by hand, so the same supplier item is matched by itself next time.
     - types z_tt_GrnScanLine, z_tt_GrnScanMap
     - procedures z_sp_GrnScanMatch (code, then name, then a printed barcode), z_sp_GrnScanSaveMaps,
       z_sp_GrnScanGetMaps, z_sp_GrnScanDeleteMap
   Same objects in the full script: 25_BackOffice_GrnScan.sql.

   Order: this script, then the new ItemApi (the old ItemApi keeps working after it), then the back office UI
   (Purchasing > GRN Scan).
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_Item', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Supplier', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_Item / z_tb_Supplier not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. table
-- DescripKey = SupplierDescrip in capitals, letters and digits only (made by ItemApi), so "SUNLIGHT YELLOW 110G X120"
-- and "SUNLIGHTYELLOW110GX120" are the same name. A row has a SupplierCode when the invoice prints one; without a
-- code the name is the key.
IF OBJECT_ID(N'dbo.z_tb_SupplierItemMap', 'U') IS NULL
CREATE TABLE dbo.z_tb_SupplierItemMap (
    MapId           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_SupplierItemMap PRIMARY KEY,
    SuppId          INT           NOT NULL,       -- z_tb_Supplier.SuppId
    SupplierCode    NVARCHAR(50)  NULL,           -- the supplier's own item code, as printed
    SupplierDescrip NVARCHAR(200) NOT NULL,       -- the supplier's name of the item, as printed
    DescripKey      NVARCHAR(200) NOT NULL,
    ItemId          INT           NOT NULL,       -- z_tb_Item.ItemId
    CaseSize        DECIMAL(18,3) NULL,           -- pieces in the supplier's case, when printed
    UseCount        INT           NOT NULL CONSTRAINT DF_z_tb_SupplierItemMap_UseCount DEFAULT (1),
    CreatedAt       DATETIME      NOT NULL CONSTRAINT DF_z_tb_SupplierItemMap_CreatedAt DEFAULT (GETDATE()),
    CreatedBy       INT           NULL,           -- z_tb_User.UserId
    UpdatedAt       DATETIME      NULL,
    UpdatedBy       INT           NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_z_tb_SupplierItemMap_Code')
    CREATE UNIQUE INDEX UX_z_tb_SupplierItemMap_Code ON dbo.z_tb_SupplierItemMap (SuppId, SupplierCode) WHERE SupplierCode IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_SupplierItemMap_Name')
    CREATE INDEX IX_z_tb_SupplierItemMap_Name ON dbo.z_tb_SupplierItemMap (SuppId, DescripKey);
GO

-- 2. types (dropped with their procs)
IF OBJECT_ID(N'dbo.z_sp_GrnScanMatch', 'P')     IS NOT NULL DROP PROCEDURE dbo.z_sp_GrnScanMatch;
IF OBJECT_ID(N'dbo.z_sp_GrnScanSaveMaps', 'P')  IS NOT NULL DROP PROCEDURE dbo.z_sp_GrnScanSaveMaps;
IF OBJECT_ID(N'dbo.z_sp_GrnScanGetMaps', 'P')   IS NOT NULL DROP PROCEDURE dbo.z_sp_GrnScanGetMaps;
IF OBJECT_ID(N'dbo.z_sp_GrnScanDeleteMap', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_GrnScanDeleteMap;
GO
IF TYPE_ID(N'dbo.z_tt_GrnScanLine') IS NOT NULL DROP TYPE dbo.z_tt_GrnScanLine;
IF TYPE_ID(N'dbo.z_tt_GrnScanMap') IS NOT NULL DROP TYPE dbo.z_tt_GrnScanMap;
GO
-- a line read from the invoice (LineKey = its place in the answer, 1, 2, ...)
CREATE TYPE dbo.z_tt_GrnScanLine AS TABLE (
    LineKey      INT           NOT NULL PRIMARY KEY,
    SupplierCode NVARCHAR(50)  NULL,
    DescripKey   NVARCHAR(200) NULL,
    Barcode      NVARCHAR(100) NULL
);
GO
-- a confirmed match (one row per supplier code, or per name when there is no code)
CREATE TYPE dbo.z_tt_GrnScanMap AS TABLE (
    SupplierCode    NVARCHAR(50)  NULL,
    SupplierDescrip NVARCHAR(200) NOT NULL,
    DescripKey      NVARCHAR(200) NOT NULL,
    ItemId          INT           NOT NULL,
    CaseSize        DECIMAL(18,3) NULL
);
GO

-- 3. procedures
-- The item of each line: by the supplier's code, else by the supplier's item name, else by a printed barcode (one
-- active item only). MatchedBy 'code' / 'name' / 'barcode', NULL = no match (the page offers the closest names).
-- A saved match to an item that is no longer active is still returned (ItemStatus) so the page can say so.
CREATE PROCEDURE dbo.z_sp_GrnScanMatch
    @SuppId INT,
    @Lines  dbo.z_tt_GrnScanLine READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SELECT m.LineKey, m.ItemId, m.MatchedBy, m.MapId, m.MapCaseSize,
           i.RefCode, i.Barcode AS ItemBarcode, i.Descrip AS ItemDescrip, i.Status AS ItemStatus,
           d.RetailPrice, d.CostPrice
    FROM (
        SELECT l.LineKey,
               COALESCE(c.ItemId, n.ItemId, b.ItemId) AS ItemId,
               CASE WHEN c.ItemId IS NOT NULL THEN 'code' WHEN n.ItemId IS NOT NULL THEN 'name'
                    WHEN b.ItemId IS NOT NULL THEN 'barcode' END AS MatchedBy,
               COALESCE(c.MapId, n.MapId) AS MapId,
               CASE WHEN c.ItemId IS NOT NULL THEN c.CaseSize WHEN n.ItemId IS NOT NULL THEN n.CaseSize END AS MapCaseSize
        FROM @Lines l
        OUTER APPLY (SELECT TOP 1 x.ItemId, x.MapId, x.CaseSize FROM dbo.z_tb_SupplierItemMap x
                     WHERE x.SuppId = @SuppId AND l.SupplierCode IS NOT NULL AND x.SupplierCode = l.SupplierCode) c
        OUTER APPLY (SELECT TOP 1 x.ItemId, x.MapId, x.CaseSize FROM dbo.z_tb_SupplierItemMap x
                     WHERE x.SuppId = @SuppId AND l.DescripKey IS NOT NULL AND l.DescripKey <> N'' AND x.DescripKey = l.DescripKey
                     ORDER BY ISNULL(x.UpdatedAt, x.CreatedAt) DESC) n
        OUTER APPLY (SELECT MIN(x.ItemId) AS ItemId FROM dbo.z_tb_Item x
                     WHERE l.Barcode IS NOT NULL AND l.Barcode <> N'' AND x.Barcode = l.Barcode AND x.Status = 1
                     HAVING COUNT(*) = 1) b
    ) m
    LEFT JOIN dbo.z_tb_Item i ON i.ItemId = m.ItemId
    LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = m.ItemId AND d.LocationId = 1
    ORDER BY m.LineKey;
END
GO

-- Keeps the confirmed matches of one supplier: a row with a code replaces the match of that code, a row without a
-- code the match of that name. Returns the number of rows kept.
CREATE PROCEDURE dbo.z_sp_GrnScanSaveMaps
    @SuppId INT,
    @Rows   dbo.z_tt_GrnScanMap READONLY,
    @UserId INT = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Supplier WHERE SuppId = @SuppId)
        RAISERROR(N'%s', 16, 1, N'Supplier not found.');
    IF EXISTS (SELECT 1 FROM @Rows r WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_Item i WHERE i.ItemId = r.ItemId))
        RAISERROR(N'%s', 16, 1, N'An item of these matches no longer exists.');
    IF EXISTS (SELECT 1 FROM @Rows WHERE SupplierCode IS NOT NULL GROUP BY SupplierCode HAVING COUNT(*) > 1)
        RAISERROR(N'%s', 16, 1, N'The same supplier code is matched twice.');

    BEGIN TRAN;
        -- by code
        UPDATE m SET ItemId = r.ItemId, SupplierDescrip = r.SupplierDescrip, DescripKey = r.DescripKey,
                     CaseSize = ISNULL(r.CaseSize, m.CaseSize), UseCount = m.UseCount + 1,
                     UpdatedAt = GETDATE(), UpdatedBy = @UserId
        FROM dbo.z_tb_SupplierItemMap m WITH (UPDLOCK, HOLDLOCK)
        JOIN @Rows r ON r.SupplierCode IS NOT NULL AND m.SuppId = @SuppId AND m.SupplierCode = r.SupplierCode;
        -- by name (no code)
        UPDATE m SET ItemId = r.ItemId, SupplierDescrip = r.SupplierDescrip,
                     CaseSize = ISNULL(r.CaseSize, m.CaseSize), UseCount = m.UseCount + 1,
                     UpdatedAt = GETDATE(), UpdatedBy = @UserId
        FROM dbo.z_tb_SupplierItemMap m WITH (UPDLOCK, HOLDLOCK)
        JOIN @Rows r ON r.SupplierCode IS NULL AND m.SuppId = @SuppId AND m.SupplierCode IS NULL AND m.DescripKey = r.DescripKey;

        INSERT dbo.z_tb_SupplierItemMap (SuppId, SupplierCode, SupplierDescrip, DescripKey, ItemId, CaseSize, CreatedBy)
        SELECT @SuppId, r.SupplierCode, r.SupplierDescrip, r.DescripKey, r.ItemId, r.CaseSize, @UserId
        FROM @Rows r
        WHERE (r.SupplierCode IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_SupplierItemMap m
                                                          WHERE m.SuppId = @SuppId AND m.SupplierCode = r.SupplierCode))
           OR (r.SupplierCode IS NULL AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_SupplierItemMap m
                                                      WHERE m.SuppId = @SuppId AND m.SupplierCode IS NULL AND m.DescripKey = r.DescripKey));
    COMMIT;
    SELECT COUNT(*) AS Saved FROM @Rows;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0
        BEGIN
            IF XACT_STATE() <> 0 ROLLBACK;
        END
        ELSE
        BEGIN
            -- called inside the caller's transaction: give its level back, the caller's CATCH rolls back
            WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT;
        END
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

-- The saved matches of one supplier (newest first).
CREATE PROCEDURE dbo.z_sp_GrnScanGetMaps
    @SuppId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT m.MapId, m.SuppId, m.SupplierCode, m.SupplierDescrip, m.ItemId, i.RefCode, i.Descrip AS ItemDescrip,
           i.Status AS ItemStatus, m.CaseSize, m.UseCount, m.CreatedAt, ISNULL(m.UpdatedAt, m.CreatedAt) AS LastSavedAt
    FROM dbo.z_tb_SupplierItemMap m
    LEFT JOIN dbo.z_tb_Item i ON i.ItemId = m.ItemId
    WHERE m.SuppId = @SuppId
    ORDER BY ISNULL(m.UpdatedAt, m.CreatedAt) DESC, m.MapId DESC;
END
GO

-- Removes a wrong saved match (the line is matched by hand again next time).
CREATE PROCEDURE dbo.z_sp_GrnScanDeleteMap
    @MapId INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE dbo.z_tb_SupplierItemMap WHERE MapId = @MapId;
    SELECT @@ROWCOUNT AS Deleted;
END
GO

PRINT 'U029_BackOffice_GrnScan done.';
GO
