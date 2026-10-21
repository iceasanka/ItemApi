/* =============================================================================
   U012_BackOffice_ItemDiscounts.sql   (2026-10-21)
   Update for the back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. The file itself changes NO data - it (re)creates two procedures.

   What changes (old item discounts, Docs/StockSystem.md 6.13):
     - z_sp_TransferOldItems: also copies the old discount - Tax2 (discount %) -> z_tb_ItemDet.DiscountPercent,
       Tax3 (discount amount) -> z_tb_ItemDet.DiscountAmount (0 / not a number -> NULL)
     - NEW z_sp_TransferOldItemDiscounts: fills the discount of the items ALREADY copied (left out before)
   Same change in the full script: 08_Transfer_OldItems.sql (this file is a copy of it).

   After running this file, on easyway:
       EXEC dbo.z_sp_TransferOldItemDiscounts @DryRun = 1;   -- check the report
       EXEC dbo.z_sp_TransferOldItemDiscounts @DryRun = 0;   -- save
   The tills get the discounts on their next item download. No ItemApi / TillService change.
   ============================================================================= */
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'dbo.tb_Item', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Item', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_ItemDet', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (tb_Item / z_tb_Item / z_tb_ItemDet not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Old codes of every copied item: the link between the two systems (also what makes a re-run safe).
IF OBJECT_ID('dbo.z_tb_ItemOldCode', 'U') IS NULL
CREATE TABLE dbo.z_tb_ItemOldCode (
    OldItemCode    VARCHAR(200) NOT NULL PRIMARY KEY,
    ItemId         INT          NOT NULL UNIQUE,
    OldRefCode     VARCHAR(200) NULL,
    OldCatCode     VARCHAR(10)  NULL,
    OldSubCatCode  VARCHAR(10)  NULL,
    OldSuppCode    VARCHAR(10)  NULL,
    OldUnit        VARCHAR(5)   NULL,
    TransferredAt  DATETIME     NOT NULL DEFAULT GETDATE()
);
GO

IF OBJECT_ID('dbo.z_sp_TransferOldItems', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_TransferOldItems;
GO

CREATE PROCEDURE dbo.z_sp_TransferOldItems
    @DryRun          BIT        = 1,
    @UpdateExisting  BIT        = 0,
    @LocaCode        VARCHAR(5) = '01',
    @LocationId      INT        = 1,
    @UserId          INT        = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE();

    -- -- 1. Source rows, already mapped to the new columns --
    CREATE TABLE #src (
        OldItemCode VARCHAR(200) PRIMARY KEY, OldRefCode VARCHAR(200), OldCatCode VARCHAR(10), OldSubCatCode VARCHAR(10),
        OldSuppCode VARCHAR(10), OldUnit VARCHAR(5),
        RefCode NVARCHAR(50), Barcode NVARCHAR(100), Descrip NVARCHAR(255), Inv_Descrip NVARCHAR(50), SinhalaDescrip NVARCHAR(255),
        UseExp BIT, OpenPrice BIT, MaxPrice DECIMAL(18,2),
        RetailPrice DECIMAL(18,2), WholesalePrice DECIMAL(18,2), SpecialPrice DECIMAL(18,2), CostPrice DECIMAL(18,2),
        AverageCost DECIMAL(18,2), UnitId INT, WholesaleMargin DECIMAL(10,2), RetailMargin DECIMAL(10,2),
        IsSaleLocked BIT, NoDiscount BIT, ReorderLevel DECIMAL(18,2), ReorderQty DECIMAL(18,2),
        Q2 DECIMAL(18,2), P2 DECIMAL(18,2), Q3 DECIMAL(18,2), P3 DECIMAL(18,2), Q4 DECIMAL(18,2), P4 DECIMAL(18,2),
        DiscountPercent DECIMAL(5,2), DiscountAmount DECIMAL(18,2),
        CDate DATETIME, ItemId INT NULL, Problem NVARCHAR(500) NULL, Note NVARCHAR(1000) NULL
    );

    INSERT #src (OldItemCode, OldRefCode, OldCatCode, OldSubCatCode, OldSuppCode, OldUnit,
                 RefCode, Barcode, Descrip, Inv_Descrip, SinhalaDescrip, UseExp, OpenPrice, MaxPrice,
                 RetailPrice, WholesalePrice, SpecialPrice, CostPrice, AverageCost, UnitId, WholesaleMargin, RetailMargin,
                 IsSaleLocked, NoDiscount, ReorderLevel, ReorderQty, Q2, P2, Q3, P3, Q4, P4,
                 DiscountPercent, DiscountAmount, CDate)
    SELECT i.Item_Code, NULLIF(LTRIM(RTRIM(i.Ref_Code)), ''), NULLIF(LTRIM(RTRIM(i.Cat_Code)), ''),
           NULLIF(LTRIM(RTRIM(i.SubCat_Code)), ''), NULLIF(LTRIM(RTRIM(i.Supp_Code)), ''), NULLIF(LTRIM(RTRIM(i.EUnit)), ''),
           CASE WHEN LTRIM(RTRIM(i.Ref_Code)) <> '' THEN LTRIM(RTRIM(i.Ref_Code)) ELSE LTRIM(RTRIM(i.Item_Code)) END,
           NULLIF(LTRIM(RTRIM(i.Barcode)), ''),
           LTRIM(RTRIM(i.Descrip)),
           LEFT(NULLIF(LTRIM(RTRIM(i.Inv_Descrip)), ''), 50),
           NULLIF(LTRIM(RTRIM(i.SinhalaDescrip)), N''),
           CASE WHEN i.Use_Exp = 1 THEN 1 ELSE 0 END,
           CASE WHEN i.OpenPrice = 1 THEN 1 ELSE 0 END,
           NULLIF(CAST(i.MaxPrice AS DECIMAL(18,2)), 0),
           CAST(d.ERet_Price AS DECIMAL(18,2)),
           NULLIF(CAST(d.EWhole_Price AS DECIMAL(18,2)), 0),
           NULLIF(CAST(d.ESp_Price AS DECIMAL(18,2)), 0),
           NULLIF(CAST(d.Cost_Price AS DECIMAL(18,2)), 0),
           NULLIF(CAST(d.AvgCost AS DECIMAL(18,2)), 0),
           u.UnitId,
           CASE WHEN LTRIM(RTRIM(i.W_Margine)) LIKE '%[0-9]%' AND LTRIM(RTRIM(i.W_Margine)) NOT LIKE '%[^0-9.-]%'
                THEN CAST(LTRIM(RTRIM(i.W_Margine)) AS DECIMAL(10,2)) END,
           CASE WHEN LTRIM(RTRIM(i.R_Margine)) LIKE '%[0-9]%' AND LTRIM(RTRIM(i.R_Margine)) NOT LIKE '%[^0-9.-]%'
                THEN CAST(LTRIM(RTRIM(i.R_Margine)) AS DECIMAL(10,2)) END,
           d.Lock_S, d.NoDiscount,
           NULLIF(CAST(d.Rol AS DECIMAL(18,2)), 0), NULLIF(CAST(d.Re_Qty AS DECIMAL(18,2)), 0),
           NULLIF(d.SPQ, 0), NULLIF(CAST(d.SPR AS DECIMAL(18,2)), 0),
           NULLIF(d.TPQ, 0), NULLIF(CAST(d.TPR AS DECIMAL(18,2)), 0),
           NULLIF(d.FPQ, 0), NULLIF(CAST(d.FPR AS DECIMAL(18,2)), 0),
           -- Tax2 = discount %, Tax3 = discount amount (nchar(10) text); 0 or not a number -> NULL; % over 100 -> NULL
           CASE WHEN LTRIM(RTRIM(i.Tax2)) LIKE '%[0-9]%' AND LTRIM(RTRIM(i.Tax2)) NOT LIKE '%[^0-9.]%'
                THEN CASE WHEN CAST(LTRIM(RTRIM(i.Tax2)) AS DECIMAL(18,2)) BETWEEN 0.01 AND 100
                          THEN CAST(LTRIM(RTRIM(i.Tax2)) AS DECIMAL(5,2)) END END,
           CASE WHEN LTRIM(RTRIM(i.Tax3)) LIKE '%[0-9]%' AND LTRIM(RTRIM(i.Tax3)) NOT LIKE '%[^0-9.]%'
                THEN NULLIF(CAST(LTRIM(RTRIM(i.Tax3)) AS DECIMAL(18,2)), 0) END,
           ISNULL(d.CDate, @Now)
    FROM dbo.tb_Item i
    JOIN dbo.tb_ItemDet d ON d.Item_Code = i.Item_Code AND d.Loca_Code = @LocaCode
    LEFT JOIN dbo.z_tb_Unit u ON LTRIM(RTRIM(u.UnitCode)) = LTRIM(RTRIM(i.EUnit));

    -- quantity prices: keep a level only when it passes the Item Entry rules (and every level below it does)
    UPDATE #src SET Note = 'Quantity prices left out (they break the Item Entry rules)', Q2 = NULL, P2 = NULL, Q3 = NULL, P3 = NULL, Q4 = NULL, P4 = NULL
    WHERE (Q2 IS NOT NULL OR P2 IS NOT NULL OR Q3 IS NOT NULL OR P3 IS NOT NULL OR Q4 IS NOT NULL OR P4 IS NOT NULL)
      AND NOT (    Q2 > 1 AND P2 > 0 AND P2 < RetailPrice
               AND (Q3 IS NULL AND P3 IS NULL OR Q3 > Q2 AND P3 > 0 AND P3 < P2)
               AND (Q4 IS NULL AND P4 IS NULL OR Q3 IS NOT NULL AND Q4 > Q3 AND P4 > 0 AND P4 < P3));

    -- already copied before
    UPDATE s SET ItemId = m.ItemId FROM #src s JOIN dbo.z_tb_ItemOldCode m ON m.OldItemCode = s.OldItemCode;

    -- a new RefCode already used by ANOTHER new item -> skip (RefCode is unique)
    UPDATE s SET Problem = 'RefCode ' + s.RefCode + ' is already used by new item ' + CAST(z.ItemId AS VARCHAR(10)) + ' ' + ISNULL(z.Descrip, '')
    FROM #src s JOIN dbo.z_tb_Item z ON z.RefCode = s.RefCode AND (s.ItemId IS NULL OR z.ItemId <> s.ItemId);

    UPDATE #src SET Problem = 'No description' WHERE Problem IS NULL AND (Descrip IS NULL OR Descrip = N'');

    -- two old items that would get the same new RefCode -> skip both (none on 2026-10-09; keeps a later run safe)
    UPDATE s SET Problem = 'Two old items would get RefCode ' + s.RefCode
    FROM #src s WHERE s.Problem IS NULL AND s.ItemId IS NULL
      AND (SELECT COUNT(*) FROM #src o WHERE o.RefCode = s.RefCode) > 1;

    -- worth a look, but copied
    UPDATE s SET Note = ISNULL(s.Note + '; ', '') + 'Unit ' + ISNULL(s.OldUnit, '(none)') + ' is not in z_tb_Unit - unit left empty'
    FROM #src s WHERE s.UnitId IS NULL AND s.Problem IS NULL;
    UPDATE s SET Note = ISNULL(s.Note + '; ', '') + 'Code ' + s.RefCode + ' is also the barcode of ' + o.OldItemCode + ' ' + o.Descrip
                        + ' - the till finds that item first when this code is typed'
    FROM #src s JOIN #src o ON o.Barcode = s.RefCode AND o.OldItemCode <> s.OldItemCode WHERE s.Problem IS NULL;
    UPDATE #src SET Note = ISNULL(Note + '; ', '') + 'No retail price' WHERE Problem IS NULL AND ISNULL(RetailPrice, 0) <= 0;

    DECLARE @Inserted INT = 0, @Updated INT = 0;
    -- copied before and fine: counted now, because a dry run's ROLLBACK also undoes changes to #src
    DECLARE @Already INT = (SELECT COUNT(*) FROM #src WHERE ItemId IS NOT NULL AND Problem IS NULL);
    -- a table variable survives ROLLBACK (a temp table does not), so the dry run can still report the new items
    DECLARE @new TABLE (ItemId INT, OldItemCode VARCHAR(200));

    BEGIN TRAN;

        -- -- 2. New items (MERGE so each new ItemId comes back with its old code) --
        MERGE dbo.z_tb_Item AS t
        USING (SELECT * FROM #src WHERE ItemId IS NULL AND Problem IS NULL) AS s ON 1 = 0
        WHEN NOT MATCHED THEN
            INSERT (RefCode, Barcode, Descrip, SinhalaDescrip, CatId, SubCatId, SupId, UseExp, UserId, CDate, UDate, Status,
                    Inv_Descrip, MaxPrice, OpenPrice)
            VALUES (s.RefCode, s.Barcode, s.Descrip, s.SinhalaDescrip, NULL, NULL, NULL, s.UseExp, @UserId, s.CDate, @Now, 1,
                    s.Inv_Descrip, s.MaxPrice, s.OpenPrice)
        OUTPUT inserted.ItemId, s.OldItemCode INTO @new (ItemId, OldItemCode);
        SET @Inserted = @@ROWCOUNT;

        UPDATE s SET ItemId = n.ItemId FROM #src s JOIN @new n ON n.OldItemCode = s.OldItemCode;

        INSERT dbo.z_tb_ItemDet (ItemId, LocationId, RetailPrice, WholesalePrice, SpecialPrice, CostPrice, AverageCost, unitId,
                                 WholesaleMargin, RetailMargin, IsSaleLocked, NoDiscount, ReorderLevel, ReorderQty,
                                 QtyLevel2, PriceLevel2, QtyLevel3, PriceLevel3, QtyLevel4, PriceLevel4,
                                 DiscountPercent, DiscountAmount, UserId, CDate, UDate)
        SELECT s.ItemId, @LocationId, s.RetailPrice, s.WholesalePrice, s.SpecialPrice, s.CostPrice, s.AverageCost, s.UnitId,
               s.WholesaleMargin, s.RetailMargin, s.IsSaleLocked, s.NoDiscount, s.ReorderLevel, s.ReorderQty,
               s.Q2, s.P2, s.Q3, s.P3, s.Q4, s.P4, s.DiscountPercent, s.DiscountAmount, @UserId, s.CDate, @Now
        FROM #src s JOIN @new n ON n.OldItemCode = s.OldItemCode;

        INSERT dbo.z_tb_ItemOldCode (OldItemCode, ItemId, OldRefCode, OldCatCode, OldSubCatCode, OldSuppCode, OldUnit, TransferredAt)
        SELECT s.OldItemCode, s.ItemId, s.OldRefCode, s.OldCatCode, s.OldSubCatCode, s.OldSuppCode, s.OldUnit, @Now
        FROM #src s JOIN @new n ON n.OldItemCode = s.OldItemCode;

        -- -- 3. Items copied before: refresh only when asked --
        IF @UpdateExisting = 1
        BEGIN
            UPDATE z SET RefCode = s.RefCode, Barcode = s.Barcode, Descrip = s.Descrip, SinhalaDescrip = s.SinhalaDescrip,
                         UseExp = s.UseExp, Inv_Descrip = s.Inv_Descrip, MaxPrice = s.MaxPrice, OpenPrice = s.OpenPrice,
                         UserId = @UserId, UDate = @Now
            FROM dbo.z_tb_Item z JOIN #src s ON s.ItemId = z.ItemId
            WHERE s.Problem IS NULL AND NOT EXISTS (SELECT 1 FROM @new n WHERE n.OldItemCode = s.OldItemCode);
            SET @Updated = @@ROWCOUNT;

            UPDATE d SET RetailPrice = s.RetailPrice, WholesalePrice = s.WholesalePrice, SpecialPrice = s.SpecialPrice,
                         CostPrice = s.CostPrice, AverageCost = s.AverageCost, unitId = s.UnitId,
                         WholesaleMargin = s.WholesaleMargin, RetailMargin = s.RetailMargin, IsSaleLocked = s.IsSaleLocked,
                         NoDiscount = s.NoDiscount, ReorderLevel = s.ReorderLevel, ReorderQty = s.ReorderQty,
                         QtyLevel2 = s.Q2, PriceLevel2 = s.P2, QtyLevel3 = s.Q3, PriceLevel3 = s.P3, QtyLevel4 = s.Q4, PriceLevel4 = s.P4,
                         DiscountPercent = s.DiscountPercent, DiscountAmount = s.DiscountAmount,
                         UserId = @UserId, UDate = @Now
            FROM dbo.z_tb_ItemDet d JOIN #src s ON s.ItemId = d.ItemId AND d.LocationId = @LocationId
            WHERE s.Problem IS NULL AND NOT EXISTS (SELECT 1 FROM @new n WHERE n.OldItemCode = s.OldItemCode);

            UPDATE m SET OldRefCode = s.OldRefCode, OldCatCode = s.OldCatCode, OldSubCatCode = s.OldSubCatCode,
                         OldSuppCode = s.OldSuppCode, OldUnit = s.OldUnit, TransferredAt = @Now
            FROM dbo.z_tb_ItemOldCode m JOIN #src s ON s.OldItemCode = m.OldItemCode
            WHERE s.Problem IS NULL AND NOT EXISTS (SELECT 1 FROM @new n WHERE n.OldItemCode = s.OldItemCode);
        END

    IF @DryRun = 1 ROLLBACK ELSE COMMIT;

    -- -- 4. Report --
    SELECT CASE WHEN @DryRun = 1 THEN 'DRY RUN - nothing saved' ELSE 'SAVED' END AS Result,
           (SELECT COUNT(*) FROM #src)                                                   AS OldItems,
           @Inserted                                                                     AS NewItemsAdded,
           @Updated                                                                      AS ExistingRefreshed,
           @Already - @Updated                                                           AS AlreadyCopiedLeftAsIs,
           (SELECT COUNT(*) FROM #src WHERE Problem IS NOT NULL)                         AS Skipped,
           (SELECT COUNT(*) FROM #src WHERE Problem IS NULL AND Note IS NOT NULL)        AS CopiedWithNote,
           (SELECT COUNT(*) FROM #src WHERE Problem IS NULL AND OldRefCode IS NOT NULL)  AS UsingScaleCode,
           (SELECT COUNT(*) FROM #src WHERE Problem IS NULL
                                        AND (DiscountPercent IS NOT NULL OR DiscountAmount IS NOT NULL)) AS WithDiscount,
           (SELECT COUNT(*) FROM dbo.tb_Item i WHERE NOT EXISTS
               (SELECT 1 FROM dbo.tb_ItemDet d WHERE d.Item_Code = i.Item_Code AND d.Loca_Code = @LocaCode)) AS OldItemsWithoutPrices;

    SELECT OldItemCode, RefCode, Descrip, CASE WHEN Problem IS NOT NULL THEN 'SKIPPED' ELSE 'copied' END AS Status,
           ISNULL(Problem, Note) AS Reason
    FROM #src WHERE Problem IS NOT NULL OR Note IS NOT NULL
    ORDER BY CASE WHEN Problem IS NOT NULL THEN 0 ELSE 1 END, OldItemCode;
END
GO

/* -----------------------------------------------------------------------------
   z_sp_TransferOldItemDiscounts (2026-10-21) - the old discount of items ALREADY copied (the transfer above did not
   copy Tax2 / Tax3 before this date). Only z_tb_ItemDet.DiscountPercent / DiscountAmount change; UDate = now so the
   tills download them. Re-runnable.
       EXEC dbo.z_sp_TransferOldItemDiscounts @DryRun = 1;   -- report only, nothing saved
       EXEC dbo.z_sp_TransferOldItemDiscounts @DryRun = 0;   -- the real one
   Tax2 = discount % (0.01 - 100), Tax3 = discount amount (> 0); 0 / empty / not a number = no discount.
   An item that already has a discount in the new system (set in Item Entry) is left as it is, unless @Overwrite = 1.
   An amount not below the retail price is not copied (the price label refuses it) - reported.
   Result sets: 1) counts, 2) every item with an old discount and what was done.
   ----------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.z_sp_TransferOldItemDiscounts', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_TransferOldItemDiscounts;
GO

CREATE PROCEDURE dbo.z_sp_TransferOldItemDiscounts
    @DryRun     BIT        = 1,
    @Overwrite  BIT        = 0,
    @LocationId INT        = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE();

    CREATE TABLE #d (
        ItemId INT PRIMARY KEY, OldItemCode VARCHAR(200), OldTax2 NVARCHAR(10), OldTax3 NVARCHAR(10),
        Pct DECIMAL(5,2) NULL, Amt DECIMAL(18,2) NULL, Action VARCHAR(100) NULL
    );

    INSERT #d (ItemId, OldItemCode, OldTax2, OldTax3, Pct, Amt)
    SELECT m.ItemId, m.OldItemCode, LTRIM(RTRIM(o.Tax2)), LTRIM(RTRIM(o.Tax3)),
           CASE WHEN LTRIM(RTRIM(o.Tax2)) LIKE '%[0-9]%' AND LTRIM(RTRIM(o.Tax2)) NOT LIKE '%[^0-9.]%'
                THEN CASE WHEN CAST(LTRIM(RTRIM(o.Tax2)) AS DECIMAL(18,2)) BETWEEN 0.01 AND 100
                          THEN CAST(LTRIM(RTRIM(o.Tax2)) AS DECIMAL(5,2)) END END,
           CASE WHEN LTRIM(RTRIM(o.Tax3)) LIKE '%[0-9]%' AND LTRIM(RTRIM(o.Tax3)) NOT LIKE '%[^0-9.]%'
                THEN NULLIF(CAST(LTRIM(RTRIM(o.Tax3)) AS DECIMAL(18,2)), 0) END
    FROM dbo.z_tb_ItemOldCode m
    JOIN dbo.tb_Item o ON o.Item_Code = m.OldItemCode;

    -- keep only items with an old discount, or an old value that is not a usable number (reported)
    DELETE FROM #d WHERE Pct IS NULL AND Amt IS NULL
                     AND ISNULL(OldTax2, '') IN ('', '0', '0.0', '0.00') AND ISNULL(OldTax3, '') IN ('', '0', '0.0', '0.00');

    UPDATE x SET Action = CASE
            WHEN d.ItemId IS NULL                                        THEN 'skipped - no price row at this location'
            WHEN x.Pct IS NULL AND x.Amt IS NULL                         THEN 'skipped - Tax2 / Tax3 is not a usable number'
            WHEN x.Amt IS NOT NULL AND x.Amt >= ISNULL(d.RetailPrice, 0) THEN 'skipped - amount is not below the retail price'
            WHEN ISNULL(d.DiscountPercent, -1) = ISNULL(x.Pct, -1)
             AND ISNULL(d.DiscountAmount, -1) = ISNULL(x.Amt, -1)        THEN 'same already'
            WHEN @Overwrite = 0 AND (d.DiscountPercent IS NOT NULL OR d.DiscountAmount IS NOT NULL)
                                                                         THEN 'kept - already has a discount in the new system'
            ELSE 'set' END
    FROM #d x
    LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = x.ItemId AND d.LocationId = @LocationId;

    IF @DryRun = 0
        UPDATE d SET DiscountPercent = x.Pct, DiscountAmount = x.Amt, UDate = @Now
        FROM dbo.z_tb_ItemDet d JOIN #d x ON x.ItemId = d.ItemId AND d.LocationId = @LocationId
        WHERE x.Action = 'set';

    SELECT CASE WHEN @DryRun = 1 THEN 'DRY RUN - nothing saved' ELSE 'SAVED' END AS Result,
           (SELECT COUNT(*) FROM #d WHERE Action = 'set')                          AS DiscountsSet,
           (SELECT COUNT(*) FROM #d WHERE Action = 'set' AND Pct IS NOT NULL)      AS WithPercent,
           (SELECT COUNT(*) FROM #d WHERE Action = 'set' AND Amt IS NOT NULL)      AS WithAmount,
           (SELECT COUNT(*) FROM #d WHERE Action = 'same already')                 AS SameAlready,
           (SELECT COUNT(*) FROM #d WHERE Action LIKE 'kept%')                     AS KeptNewSystemValue,
           (SELECT COUNT(*) FROM #d WHERE Action LIKE 'skipped%')                  AS Skipped;

    SELECT i.RefCode, i.Descrip, d.RetailPrice, x.OldItemCode, x.OldTax2 AS OldPercent, x.OldTax3 AS OldAmount,
           x.Pct AS NewDiscountPercent, x.Amt AS NewDiscountAmount, x.Action
    FROM #d x
    JOIN dbo.z_tb_Item i ON i.ItemId = x.ItemId
    LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = x.ItemId AND d.LocationId = @LocationId
    ORDER BY CASE WHEN x.Action LIKE 'skipped%' THEN 0 WHEN x.Action LIKE 'kept%' THEN 1 ELSE 2 END, i.RefCode;
END
GO
SET NOEXEC OFF;
GO
PRINT 'U012_BackOffice_ItemDiscounts done.';
GO
