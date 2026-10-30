/* =============================================================================
   25_BackOffice_GrnScan.sql
   Run on: back office db (easyway), AFTER 01_BackOffice_Stock.sql. Prefix z_. Re-runnable. SQL 2008 R2.
   GRN scan (Docs/StockSystem.md 6.31): a supplier invoice photo is read by AI (ItemApi api/GrnScan/Read) and every
   line is matched to one of our items. A match made by hand on the GRN Scan page is kept here, so the same supplier
   item is matched by itself next time.
     z_tb_SupplierItemMap   supplier + the supplier's item code (or, without a code, their item name) -> ItemId.
                            SupplierDescrip keeps the supplier's own name of the item (the remark).
   Matching order (z_sp_GrnScanMatch): supplier code, then the supplier's item name, then a printed barcode.
   Section 4 (U030, U033, U035): z_sp_GrnScanMakeDraft - the confirmed lines become a suspended GRN, committed on GRN Entry;
                           z_tb_TempPurchase.FreeQty keeps the free pieces of a line (U033).
   Section 5 (U031): z_tb_GrnScan - every read kept, so the matching can go on another day; flushed when done.
   Deployed databases: Updates/U029 + U030 + U031 + U033 (same objects).
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

-- 4. GRN draft from a scan (U030)
-- The confirmed lines of a scanned invoice become a NEW suspended GRN (z_tb_TempPurchaseSummary Status 0, Type 1,
-- UserId 'scan', number GRN + z_tb_System.PNO like GRN Entry / the mobile GRN). The back office opens it on GRN Entry,
-- checks it and commits it to stock as usual. No stock or price moves here.
--   CostPrice = what one piece really costs: (gross - line discount) / (qty + free qty), as the GRN commit takes the
--   line CostPrice for the stock cost (free goods and the scheme discount lower the cost of every piece).
--   GAmount = the invoice line amount after its discount. SellPrice NULL = the item's selling price now.
--   FreeQty (U033) = how many of the line's Qty came free; Qty stays bought + free, so stock and the GRN commit are
--   as before. A free line of an item with no bought line: CostPrice NULL = the item's cost now, GAmount 0.
--   The same supplier invoice no on another GRN is refused (state 2) unless @AllowSameRef = 1.
-- z_tb_TempPurchase.FreeQty (U033): the free pieces in Qty (GRN scan; NULL on lines made elsewhere)
IF COL_LENGTH(N'dbo.z_tb_TempPurchase', N'FreeQty') IS NULL
    ALTER TABLE dbo.z_tb_TempPurchase ADD FreeQty DECIMAL(18,2) NULL;
GO
IF OBJECT_ID(N'dbo.z_sp_GrnScanMakeDraft', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_GrnScanMakeDraft;
GO
IF TYPE_ID(N'dbo.z_tt_GrnScanDraftLine') IS NOT NULL DROP TYPE dbo.z_tt_GrnScanDraftLine;
GO
CREATE TYPE dbo.z_tt_GrnScanDraftLine AS TABLE (
    LineKey   INT           NOT NULL PRIMARY KEY,   -- order on the invoice
    ItemId    INT           NOT NULL,
    Qty       DECIMAL(18,2) NOT NULL,               -- pieces bought + free
    CostPrice DECIMAL(18,2) NULL,                   -- a piece; NULL = the item's cost now (a free line only)
    SellPrice DECIMAL(18,2) NULL,                   -- NULL = the item's selling price now
    GAmount   DECIMAL(18,2) NOT NULL,               -- the invoice line amount after its discount
    FreeQty   DECIMAL(18,2) NULL                    -- of Qty, the free pieces
);
GO
CREATE PROCEDURE dbo.z_sp_GrnScanMakeDraft
    @SuppId       INT,
    @RefNo        VARCHAR(30) = NULL,              -- the supplier's invoice no
    @Remark       VARCHAR(200) = NULL,
    @Lines        dbo.z_tt_GrnScanDraftLine READONLY,
    @AllowSameRef BIT = 0,
    @LocationId   INT = 1
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @GrnNo VARCHAR(20), @No INT, @Tries INT, @Now DATETIME, @Today DATETIME, @Other VARCHAR(20), @Msg NVARCHAR(400);
    SET @Now = GETDATE();
    SET @Today = CAST(CONVERT(VARCHAR(10), @Now, 120) AS DATETIME);
    SET @LocationId = ISNULL(@LocationId, 1);
    SET @RefNo = NULLIF(LTRIM(RTRIM(@RefNo)), '');

    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Supplier WHERE SuppId = @SuppId)
        RAISERROR(N'%s', 16, 1, N'Supplier not found.');
    IF NOT EXISTS (SELECT 1 FROM @Lines)
        RAISERROR(N'%s', 16, 1, N'No lines to put on the GRN.');
    IF EXISTS (SELECT 1 FROM @Lines WHERE Qty <= 0 OR CostPrice < 0 OR SellPrice < 0 OR GAmount < 0
                                       OR FreeQty < 0 OR FreeQty > Qty)
        RAISERROR(N'%s', 16, 1, N'A line has no qty, free qty above its qty, or a cost / price / amount below 0.');
    IF EXISTS (SELECT 1 FROM @Lines l WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_Item i WHERE i.ItemId = l.ItemId AND i.Status = 1))
        RAISERROR(N'%s', 16, 1, N'An item of these lines is not found or not active.');
    IF @RefNo IS NOT NULL AND ISNULL(@AllowSameRef, 0) = 0
    BEGIN
        SELECT TOP 1 @Other = GrnNo FROM dbo.z_tb_TempPurchaseSummary
        WHERE SuppId = @SuppId AND RefNo = @RefNo AND Type = 1 ORDER BY Idx DESC;
        IF @Other IS NOT NULL
        BEGIN
            SET @Msg = N'Invoice ' + @RefNo + N' of this supplier is already on ' + @Other + N'.';
            RAISERROR(N'%s', 16, 2, @Msg);   -- state 2 = the page may ask "make it anyway?"
        END
    END

    BEGIN TRAN;
        -- the next GRN number, taken and moved on in one statement (GRN Entry and the mobile GRN use the same counter);
        -- a number already on a GRN (e.g. saved from a GRN Entry tab with the number it showed) is skipped (U035)
        SET @Tries = 0;
        WHILE 1 = 1
        BEGIN
            SET @No = NULL;
            UPDATE dbo.z_tb_System SET @No = PNO, PNO = PNO + 1 WHERE LocaId = '01';
            IF @No IS NULL RAISERROR(N'%s', 16, 1, N'GRN counter (z_tb_System.PNO) not found.');
            SET @GrnNo = 'GRN' + RIGHT('00000000' + CAST(@No AS VARCHAR(10)), 8);
            IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_TempPurchaseSummary WHERE GrnNo = @GrnNo)
               AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_TempPurchase WHERE GrnNo = @GrnNo) BREAK;
            SET @Tries = @Tries + 1;
            IF @Tries >= 1000 RAISERROR(N'%s', 16, 1, N'No free GRN number found - check z_tb_System.PNO.');
        END

        INSERT dbo.z_tb_TempPurchase (GrnNo, LocationId, ItemId, PDate, CostPrice, SellPrice, Qty, FreeQty, Discount, GAmount,
                                      Status, UDate, UserId)
        SELECT @GrnNo, @LocationId, l.ItemId, @Today, ISNULL(l.CostPrice, ISNULL(d.CostPrice, 0)),
               ISNULL(l.SellPrice, ISNULL(d.RetailPrice, 0)), l.Qty, NULLIF(l.FreeQty, 0), 0, l.GAmount, 1, @Now, 'scan'
        FROM @Lines l
        LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = l.ItemId AND d.LocationId = @LocationId
        ORDER BY l.LineKey;

        INSERT dbo.z_tb_TempPurchaseSummary (GrnNo, LocationId, RefNo, PDate, SuppId, PMode, GAmount, SubTotDisc, NetAmount,
                                             Advance, Returns, Qty, Status, Remark, UDate, UserId, POderNo, Type)
        SELECT @GrnNo, @LocationId, @RefNo, @Today, @SuppId, 1, SUM(GAmount), 0, SUM(GAmount), 0, 0, SUM(Qty), 0,
               ISNULL(NULLIF(LTRIM(RTRIM(@Remark)), ''), 'GRN scan'), @Now, 'scan', NULL, 1
        FROM @Lines;
    COMMIT;
    SELECT @GrnNo AS GrnNo, COUNT(*) AS Lines, SUM(Qty) AS Qty, SUM(GAmount) AS Amount FROM @Lines;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048), @z_state INT; SET @z_msg = ERROR_MESSAGE(); SET @z_state = ERROR_STATE();
        IF @z_tc = 0
        BEGIN
            IF XACT_STATE() <> 0 ROLLBACK;
        END
        ELSE
        BEGIN
            -- called inside the caller's transaction: give its level back, the caller's CATCH rolls back
            WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT;
        END
        RAISERROR(N'%s', 16, @z_state, @z_msg);
        RETURN 1;
    END CATCH
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
