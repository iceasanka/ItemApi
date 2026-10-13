/* =============================================================================
   U005_BackOffice_TransferPriceLinks.sql   (2026-10-13)
   Run on: back office db (easyway). SQL Server 2008 R2 and newer. Safe to run again.
   Running this file only creates the procedure - no data is changed until you EXEC it.

   One-time copy of the OLD price links (tb_PriceLink) into the NEW ones (z_tb_ItemPriceLink), for the items that
   were copied by 08_Transfer_OldItems.sql (the old code -> new ItemId link is z_tb_ItemOldCode).
   tb_PriceLink is only read, never changed.

   Run a dry run first - it does the whole copy inside a transaction, reports, and rolls it back:
       EXEC dbo.z_sp_TransferOldPriceLinks @DryRun = 1;
       EXEC dbo.z_sp_TransferOldPriceLinks @DryRun = 0;          -- the real one
   Result sets: 1) summary counts, 2) links skipped or worth a look (with the reason).

   Mapping (old -> new), location @LocaCode '01' -> @LocationId 1:
     only Status '1' (active). '0' = deleted and '3' = closed by a purchase at that price are not copied.
     ItemId          = z_tb_ItemOldCode.ItemId of ItemCode
     RetailPrice     = Price
     WholesalePrice  = EWholePrice (0 -> NULL)
     CostPrice       = CostPrice   (0 -> NULL: the till then uses the item's cost)
     Remark          = NULL, Status = 1, CDate = CreateDate, UDate = now (so the tills download them)
     PRetPrice, PWholePrice, PackSize, Inv_Descrip: not used by the new system.
   Also, every run: a price link in z_tb_ItemPriceLink whose item is no longer in z_tb_Item is deleted the way
   Item Entry deletes one (Status 0 + new UDate, so the tills drop it; the row stays). Count: LinksOfMissingItemsDeleted.
   Skipped (listed in result set 2):
     - the item is not in the new system: never copied there, or deleted there since
     - Price is 0 or less, or @MaxPrice or more (a barcode typed into the price box)
     - Price = the item's normal retail price (z_tb_ItemDet.RetailPrice) - that is not an extra price
     - the same item + price twice: the newest one is kept
     - the new item already has an active link at that price (this also makes a second run add nothing)
   Listed but copied: cost above the price (the profit view shows a loss on that price).
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.tb_PriceLink', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_ItemPriceLink', 'U') IS NULL
   OR OBJECT_ID(N'dbo.z_tb_ItemOldCode', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database with the old item transfer done (tb_PriceLink / z_tb_ItemPriceLink / z_tb_ItemOldCode not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.z_sp_TransferOldPriceLinks', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_TransferOldPriceLinks;
GO
CREATE PROCEDURE dbo.z_sp_TransferOldPriceLinks
    @DryRun      BIT           = 1,
    @LocaCode    VARCHAR(5)    = '01',
    @LocationId  INT           = 1,
    @MaxPrice    DECIMAL(18,2) = 100000,   -- a price this big is a typing mistake (a barcode in the price box)
    @UserId      INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME, @Inserted INT, @Closed INT;
    SET @Now = GETDATE();
    SET @Inserted = 0;
    SET @Closed = 0;

    -- 1. active old links, already mapped to the new columns
    CREATE TABLE #src (
        RowId INT IDENTITY(1,1) PRIMARY KEY,
        OldItemCode VARCHAR(20), Descrip VARCHAR(40), Price MONEY, CreateDate DATETIME,
        ItemId INT NULL, RetailPrice DECIMAL(18,2) NULL, WholesalePrice DECIMAL(18,2) NULL, CostPrice DECIMAL(18,2) NULL,
        Problem NVARCHAR(300) NULL, Note NVARCHAR(300) NULL
    );

    INSERT #src (OldItemCode, Descrip, Price, CreateDate, ItemId, RetailPrice, WholesalePrice, CostPrice)
    SELECT LTRIM(RTRIM(p.ItemCode)), LTRIM(RTRIM(p.Inv_Descrip)), p.Price, p.CreateDate, z.ItemId,
           CASE WHEN p.Price > 0 AND p.Price < @MaxPrice THEN CAST(p.Price AS DECIMAL(18,2)) END,
           NULLIF(CASE WHEN p.EWholePrice > 0 AND p.EWholePrice < @MaxPrice THEN CAST(p.EWholePrice AS DECIMAL(18,2)) END, 0),
           NULLIF(CASE WHEN p.CostPrice > 0 AND p.CostPrice < @MaxPrice THEN CAST(p.CostPrice AS DECIMAL(18,2)) END, 0)
    FROM dbo.tb_PriceLink p
    LEFT JOIN dbo.z_tb_ItemOldCode m ON m.OldItemCode = LTRIM(RTRIM(p.ItemCode))
    LEFT JOIN dbo.z_tb_Item z ON z.ItemId = m.ItemId   -- the item must still be there (it can be deleted after the copy)
    WHERE p.[Status] = '1' AND LTRIM(RTRIM(p.Loca)) = @LocaCode
    ORDER BY p.ItemCode, p.Price, p.CreateDate;

    UPDATE #src SET Problem = N'The item is not in the new system (not copied, or deleted there)' WHERE ItemId IS NULL;

    UPDATE #src SET Problem = N'Price is not a real price (' + CONVERT(NVARCHAR(40), Price) + N')'
    WHERE Problem IS NULL AND RetailPrice IS NULL;

    UPDATE s SET Problem = N'Same as the item''s normal price - no extra price needed'
    FROM #src s JOIN dbo.z_tb_ItemDet d ON d.ItemId = s.ItemId AND d.LocationId = @LocationId
    WHERE s.Problem IS NULL AND d.RetailPrice = s.RetailPrice;

    -- the same item + price twice: keep the newest
    UPDATE s SET Problem = N'The same price twice for this item - the newest one is kept'
    FROM #src s
    JOIN (SELECT RowId, ROW_NUMBER() OVER (PARTITION BY ItemId, RetailPrice ORDER BY CreateDate DESC, RowId DESC) AS n
          FROM #src WHERE Problem IS NULL) x ON x.RowId = s.RowId
    WHERE x.n > 1;

    UPDATE s SET Problem = N'The new item already has this price as a price link'
    FROM #src s
    WHERE s.Problem IS NULL
      AND EXISTS (SELECT 1 FROM dbo.z_tb_ItemPriceLink l
                  WHERE l.ItemId = s.ItemId AND l.LocationId = @LocationId AND l.RetailPrice = s.RetailPrice AND l.[Status] = 1);

    -- worth a look, but copied
    UPDATE #src SET Note = N'Cost ' + CONVERT(NVARCHAR(40), CostPrice) + N' is above the price - the profit view shows a loss on it'
    WHERE Problem IS NULL AND CostPrice > RetailPrice;

    -- counted now: a dry run's ROLLBACK does not undo the temp table, but keep the numbers in one place
    DECLARE @Total INT, @Skipped INT, @Noted INT;
    SELECT @Total = COUNT(*), @Skipped = SUM(CASE WHEN Problem IS NOT NULL THEN 1 ELSE 0 END),
           @Noted = SUM(CASE WHEN Problem IS NULL AND Note IS NOT NULL THEN 1 ELSE 0 END)
    FROM #src;

    -- 2. copy
    BEGIN TRAN;
        INSERT dbo.z_tb_ItemPriceLink (ItemId, LocationId, RetailPrice, WholesalePrice, CostPrice, Remark, [Status], UserId, CDate, UDate)
        SELECT ItemId, @LocationId, RetailPrice, WholesalePrice, CostPrice, NULL, 1, @UserId, ISNULL(CreateDate, @Now), @Now
        FROM #src WHERE Problem IS NULL
        ORDER BY ItemId, RetailPrice;
        SET @Inserted = @@ROWCOUNT;

        -- 3. price links whose item is gone (any location): delete them the way Item Entry does - Status 0 and a
        --    new UDate, so the tills drop them on their next download. Rows are never removed.
        UPDATE l SET [Status] = 0, UDate = @Now, UserId = ISNULL(@UserId, l.UserId)
        FROM dbo.z_tb_ItemPriceLink l
        WHERE l.[Status] = 1 AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_Item z WHERE z.ItemId = l.ItemId);
        SET @Closed = @@ROWCOUNT;
    IF @DryRun = 1 ROLLBACK ELSE COMMIT;

    -- 4. report
    SELECT CASE WHEN @DryRun = 1 THEN 'DRY RUN - nothing saved' ELSE 'SAVED' END AS Result,
           ISNULL(@Total, 0)                                                      AS OldActiveLinks,
           @Inserted                                                              AS PriceLinksAdded,
           @Closed                                                                AS LinksOfMissingItemsDeleted,
           ISNULL(@Skipped, 0)                                                    AS Skipped,
           ISNULL(@Noted, 0)                                                      AS CopiedWithNote,
           (SELECT COUNT(DISTINCT ItemId) FROM #src WHERE Problem IS NULL)        AS ItemsWithLinks,
           (SELECT COUNT(*) FROM dbo.tb_PriceLink WHERE [Status] <> '1' OR [Status] IS NULL) AS OldDeletedOrClosedNotCopied,
           (SELECT COUNT(*) FROM dbo.z_tb_ItemPriceLink WHERE LocationId = @LocationId AND [Status] = 1) AS NewActiveLinksNow;

    SELECT s.OldItemCode, z.RefCode, ISNULL(z.Descrip, s.Descrip) AS Descrip, s.Price,
           CASE WHEN s.Problem IS NOT NULL THEN 'SKIPPED' ELSE 'copied' END AS [Status],
           ISNULL(s.Problem, s.Note) AS Reason
    FROM #src s LEFT JOIN dbo.z_tb_Item z ON z.ItemId = s.ItemId
    WHERE s.Problem IS NOT NULL OR s.Note IS NOT NULL
    ORDER BY CASE WHEN s.Problem IS NOT NULL THEN 0 ELSE 1 END, s.OldItemCode, s.Price;
END
GO
PRINT 'U005 back office: z_sp_TransferOldPriceLinks created. Dry run:  EXEC dbo.z_sp_TransferOldPriceLinks @DryRun = 1;';
GO
SET NOEXEC OFF;
GO
