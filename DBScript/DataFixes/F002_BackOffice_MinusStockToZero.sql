/* =============================================================================
   F002_BackOffice_MinusStockToZero.sql   (2026-10-28)
   One-time data fix on the back office db (easyway). SQL Server 2008 R2 and newer.
   STATUS: not run yet.

   Opening stock was never loaded, so the sales took 1,512 items below 0 (production 2026-10-28,
   about -11,700 qty). Those minus figures are not real stock. With the cost batches (U026) a
   GRN fills the minus first, so those items got no batch: no new cost, no price link.

   This posts ONE stock adjustment (reason 7 Opening stock, quantity mode) that brings every item
   below 0 up to 0, through z_sp_SaveStockAdjustment - a normal ADJ document in the ledger.
   Items above 0 are not touched. Real counts later: Stock take.

   Run when the tills are synced / the shop is quiet (a bill uploaded in between can leave an
   item a little below 0 again - run this again for it).
   Order: U026 first. Then this. Then (if not done yet):
     EXEC dbo.z_sp_RebuildStockBatches @LocationId = 1, @DryRun = 0;

   @DryRun = 1 only shows (it posts and rolls back); set it to 0 and run again to do it.
   ============================================================================= */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @DryRun BIT;
SET @DryRun = 1;

DECLARE @LocationId INT;
SET @LocationId = 1;

DECLARE @Items dbo.z_tt_AdjustmentItem;
DECLARE @AdjNo VARCHAR(20);
DECLARE @Lines INT;
DECLARE @Qty DECIMAL(18,3);
DECLARE @Left INT;

IF OBJECT_ID(N'dbo.z_sp_SaveStockAdjustment', 'P') IS NULL
BEGIN
    RAISERROR('z_sp_SaveStockAdjustment not found - not the back office db. Nothing changed.', 16, 1);
    RETURN;
END

INSERT @Items (LineNum, ItemId, CountedQty, AdjQty, ReasonId, Remark)
SELECT ROW_NUMBER() OVER (ORDER BY b.ItemId), b.ItemId, NULL,
       -b.Qty, 7, 'F002 minus stock to 0'
FROM dbo.z_tb_StockBalance b
JOIN dbo.z_tb_Item i ON i.ItemId = b.ItemId
WHERE b.LocationId = @LocationId
  AND b.Qty < 0;

SELECT @Lines = COUNT(*) FROM @Items;
SELECT @Qty = SUM(AdjQty) FROM @Items;

IF @Lines = 0
BEGIN
    RAISERROR('No item is below 0 - nothing to do. Nothing changed.', 16, 1);
    RETURN;
END

-- below 0 but not in z_tb_Item (deleted items): left as they are
SELECT b.ItemId, b.Qty AS LeftBelow0_NotInItemList
FROM dbo.z_tb_StockBalance b
WHERE b.LocationId = @LocationId
  AND b.Qty < 0
  AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_Item i
                  WHERE i.ItemId = b.ItemId);

BEGIN TRAN;
    EXEC dbo.z_sp_SaveStockAdjustment
        @LocationId = @LocationId,
        @ReasonId   = 7,
        @Remark     = 'F002: stock below 0 set to 0 (no opening stock)',
        @UserId     = 'F002',
        @Items      = @Items,
        @AdjNo      = @AdjNo OUTPUT;

    SELECT @Left = COUNT(*)
    FROM dbo.z_tb_StockBalance b
    JOIN dbo.z_tb_Item i ON i.ItemId = b.ItemId
    WHERE b.LocationId = @LocationId
      AND b.Qty < 0;

    IF @Left <> 0
    BEGIN
        ROLLBACK;
        RAISERROR('Items still below 0 after the adjustment - rolled back, nothing changed.', 16, 1);
        RETURN;
    END
IF @DryRun = 1
    ROLLBACK;
ELSE
    COMMIT;

SELECT CASE WHEN @DryRun = 1 THEN 'DRY RUN - nothing changed'
            ELSE 'Done - posted' END AS Result,
       @AdjNo AS AdjNo, @Lines AS Items, @Qty AS QtyAdded;

-- the 50 biggest
SELECT TOP 50 t.ItemId, i.RefCode, i.Barcode, i.Descrip,
       -t.AdjQty AS StockWas, t.AdjQty AS Added
FROM @Items t
JOIN dbo.z_tb_Item i ON i.ItemId = t.ItemId
ORDER BY t.AdjQty DESC;
