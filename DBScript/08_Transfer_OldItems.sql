/* =============================================================================
   08_Transfer_OldItems.sql
   Run on: back office db (easyway). Prefix z_. Re-runnable.
   One-time copy of the OLD item master (tb_Item + tb_ItemDet) into the NEW one (z_tb_Item + z_tb_ItemDet).
   Docs/StockSystem.md §6.13.

   Run a dry run first — it does the whole transfer inside a transaction, reports, and rolls it back:
       EXEC dbo.z_sp_TransferOldItems @DryRun = 1;
       EXEC dbo.z_sp_TransferOldItems @DryRun = 0;          -- the real one
   Result sets: 1) summary counts, 2) items skipped or worth a look (with the reason).

   Mapping (old → new), location @LocaCode '01' → @LocationId 1:
     RefCode         = Ref_Code when it is filled (the 5-digit SCALE code, e.g. 10001 — what the scale export and
                       scale labels use), else Item_Code. The old codes are kept in z_tb_ItemOldCode.
     Barcode         = Barcode ('' → NULL)
     Descrip, Inv_Descrip (trimmed, max 50), SinhalaDescrip ('' → NULL), UseExp, OpenPrice, MaxPrice (0 → NULL)
     Category, sub-category, supplier: NOT linked (CatId / SubCatId / SupId stay NULL). The old codes are kept in
                       z_tb_ItemOldCode so they can be linked later.
     RetailPrice     = ERet_Price — the price the old tills charged (checked on 2026-10-09: 155 of the 162 items whose
                       PRet_Price differs were last sold at ERet_Price). PRet_Price is not used.
     WholesalePrice  = EWhole_Price, SpecialPrice = ESp_Price, CostPrice = Cost_Price, AverageCost = AvgCost (0 → NULL)
     UnitId          = z_tb_Unit with UnitCode = EUnit (NOS, KGS); a unit not in z_tb_Unit → NULL (reported)
     IsSaleLocked    = Lock_S, NoDiscount, ReorderLevel = Rol, ReorderQty = Re_Qty (0 → NULL)
     Margins         = W_Margine / R_Margine (text) when they are numbers
     Quantity prices = SPQ/SPR → level 2, TPQ/TPR → level 3, FPQ/FPR → level 4, only when they pass the Item Entry
                       rules (qty > 1 and rising, price > 0, below retail and falling); otherwise left out (reported).
   Stock, price links (tb_PriceLink) and sales history are NOT copied here.

   Re-running: items already copied (in z_tb_ItemOldCode) are skipped unless @UpdateExisting = 1, which refreshes them
   from the old tables (overwriting changes made in the new system — only while the new system is not in use yet).
   Skipped: an old item whose new RefCode is already used by another new item.
   The tills download the new items on their next item download (UDate = now).
   easyway is at compatibility level 100 (SQL 2008): no IIF / FORMAT / CONCAT / TRY_CONVERT.
   ============================================================================= */
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

    -- ── 1. Source rows, already mapped to the new columns ──
    CREATE TABLE #src (
        OldItemCode VARCHAR(200) PRIMARY KEY, OldRefCode VARCHAR(200), OldCatCode VARCHAR(10), OldSubCatCode VARCHAR(10),
        OldSuppCode VARCHAR(10), OldUnit VARCHAR(5),
        RefCode NVARCHAR(50), Barcode NVARCHAR(100), Descrip NVARCHAR(255), Inv_Descrip NVARCHAR(50), SinhalaDescrip NVARCHAR(255),
        UseExp BIT, OpenPrice BIT, MaxPrice DECIMAL(18,2),
        RetailPrice DECIMAL(18,2), WholesalePrice DECIMAL(18,2), SpecialPrice DECIMAL(18,2), CostPrice DECIMAL(18,2),
        AverageCost DECIMAL(18,2), UnitId INT, WholesaleMargin DECIMAL(10,2), RetailMargin DECIMAL(10,2),
        IsSaleLocked BIT, NoDiscount BIT, ReorderLevel DECIMAL(18,2), ReorderQty DECIMAL(18,2),
        Q2 DECIMAL(18,2), P2 DECIMAL(18,2), Q3 DECIMAL(18,2), P3 DECIMAL(18,2), Q4 DECIMAL(18,2), P4 DECIMAL(18,2),
        CDate DATETIME, ItemId INT NULL, Problem NVARCHAR(500) NULL, Note NVARCHAR(1000) NULL
    );

    INSERT #src (OldItemCode, OldRefCode, OldCatCode, OldSubCatCode, OldSuppCode, OldUnit,
                 RefCode, Barcode, Descrip, Inv_Descrip, SinhalaDescrip, UseExp, OpenPrice, MaxPrice,
                 RetailPrice, WholesalePrice, SpecialPrice, CostPrice, AverageCost, UnitId, WholesaleMargin, RetailMargin,
                 IsSaleLocked, NoDiscount, ReorderLevel, ReorderQty, Q2, P2, Q3, P3, Q4, P4, CDate)
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

    -- a new RefCode already used by ANOTHER new item → skip (RefCode is unique)
    UPDATE s SET Problem = 'RefCode ' + s.RefCode + ' is already used by new item ' + CAST(z.ItemId AS VARCHAR(10)) + ' ' + ISNULL(z.Descrip, '')
    FROM #src s JOIN dbo.z_tb_Item z ON z.RefCode = s.RefCode AND (s.ItemId IS NULL OR z.ItemId <> s.ItemId);

    UPDATE #src SET Problem = 'No description' WHERE Problem IS NULL AND (Descrip IS NULL OR Descrip = N'');

    -- two old items that would get the same new RefCode → skip both (none on 2026-10-09; keeps a later run safe)
    UPDATE s SET Problem = 'Two old items would get RefCode ' + s.RefCode
    FROM #src s WHERE s.Problem IS NULL AND s.ItemId IS NULL
      AND (SELECT COUNT(*) FROM #src o WHERE o.RefCode = s.RefCode) > 1;

    -- worth a look, but copied
    UPDATE s SET Note = ISNULL(s.Note + '; ', '') + 'Unit ' + ISNULL(s.OldUnit, '(none)') + ' is not in z_tb_Unit — unit left empty'
    FROM #src s WHERE s.UnitId IS NULL AND s.Problem IS NULL;
    UPDATE s SET Note = ISNULL(s.Note + '; ', '') + 'Code ' + s.RefCode + ' is also the barcode of ' + o.OldItemCode + ' ' + o.Descrip
                        + ' — the till finds that item first when this code is typed'
    FROM #src s JOIN #src o ON o.Barcode = s.RefCode AND o.OldItemCode <> s.OldItemCode WHERE s.Problem IS NULL;
    UPDATE #src SET Note = ISNULL(Note + '; ', '') + 'No retail price' WHERE Problem IS NULL AND ISNULL(RetailPrice, 0) <= 0;

    DECLARE @Inserted INT = 0, @Updated INT = 0;
    -- copied before and fine: counted now, because a dry run's ROLLBACK also undoes changes to #src
    DECLARE @Already INT = (SELECT COUNT(*) FROM #src WHERE ItemId IS NOT NULL AND Problem IS NULL);
    -- a table variable survives ROLLBACK (a temp table does not), so the dry run can still report the new items
    DECLARE @new TABLE (ItemId INT, OldItemCode VARCHAR(200));

    BEGIN TRAN;

        -- ── 2. New items (MERGE so each new ItemId comes back with its old code) ──
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
                                 QtyLevel2, PriceLevel2, QtyLevel3, PriceLevel3, QtyLevel4, PriceLevel4, UserId, CDate, UDate)
        SELECT s.ItemId, @LocationId, s.RetailPrice, s.WholesalePrice, s.SpecialPrice, s.CostPrice, s.AverageCost, s.UnitId,
               s.WholesaleMargin, s.RetailMargin, s.IsSaleLocked, s.NoDiscount, s.ReorderLevel, s.ReorderQty,
               s.Q2, s.P2, s.Q3, s.P3, s.Q4, s.P4, @UserId, s.CDate, @Now
        FROM #src s JOIN @new n ON n.OldItemCode = s.OldItemCode;

        INSERT dbo.z_tb_ItemOldCode (OldItemCode, ItemId, OldRefCode, OldCatCode, OldSubCatCode, OldSuppCode, OldUnit, TransferredAt)
        SELECT s.OldItemCode, s.ItemId, s.OldRefCode, s.OldCatCode, s.OldSubCatCode, s.OldSuppCode, s.OldUnit, @Now
        FROM #src s JOIN @new n ON n.OldItemCode = s.OldItemCode;

        -- ── 3. Items copied before: refresh only when asked ──
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
                         UserId = @UserId, UDate = @Now
            FROM dbo.z_tb_ItemDet d JOIN #src s ON s.ItemId = d.ItemId AND d.LocationId = @LocationId
            WHERE s.Problem IS NULL AND NOT EXISTS (SELECT 1 FROM @new n WHERE n.OldItemCode = s.OldItemCode);

            UPDATE m SET OldRefCode = s.OldRefCode, OldCatCode = s.OldCatCode, OldSubCatCode = s.OldSubCatCode,
                         OldSuppCode = s.OldSuppCode, OldUnit = s.OldUnit, TransferredAt = @Now
            FROM dbo.z_tb_ItemOldCode m JOIN #src s ON s.OldItemCode = m.OldItemCode
            WHERE s.Problem IS NULL AND NOT EXISTS (SELECT 1 FROM @new n WHERE n.OldItemCode = s.OldItemCode);
        END

    IF @DryRun = 1 ROLLBACK ELSE COMMIT;

    -- ── 4. Report ──
    SELECT CASE WHEN @DryRun = 1 THEN 'DRY RUN — nothing saved' ELSE 'SAVED' END AS Result,
           (SELECT COUNT(*) FROM #src)                                                   AS OldItems,
           @Inserted                                                                     AS NewItemsAdded,
           @Updated                                                                      AS ExistingRefreshed,
           @Already - @Updated                                                           AS AlreadyCopiedLeftAsIs,
           (SELECT COUNT(*) FROM #src WHERE Problem IS NOT NULL)                         AS Skipped,
           (SELECT COUNT(*) FROM #src WHERE Problem IS NULL AND Note IS NOT NULL)        AS CopiedWithNote,
           (SELECT COUNT(*) FROM #src WHERE Problem IS NULL AND OldRefCode IS NOT NULL)  AS UsingScaleCode,
           (SELECT COUNT(*) FROM dbo.tb_Item i WHERE NOT EXISTS
               (SELECT 1 FROM dbo.tb_ItemDet d WHERE d.Item_Code = i.Item_Code AND d.Loca_Code = @LocaCode)) AS OldItemsWithoutPrices;

    SELECT OldItemCode, RefCode, Descrip, CASE WHEN Problem IS NOT NULL THEN 'SKIPPED' ELSE 'copied' END AS Status,
           ISNULL(Problem, Note) AS Reason
    FROM #src WHERE Problem IS NOT NULL OR Note IS NOT NULL
    ORDER BY CASE WHEN Problem IS NOT NULL THEN 0 ELSE 1 END, OldItemCode;
END
GO
