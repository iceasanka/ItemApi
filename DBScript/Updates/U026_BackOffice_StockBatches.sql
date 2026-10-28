/* =============================================================================
   U026_BackOffice_StockBatches.sql   (2026-10-28)
   Run on: back office db (easyway), after U025. SQL Server 2008 R2 and newer. Safe to run again.
   Needs: z_tb_StockLedger / z_tb_StockBalance / z_tb_ItemPriceLink / z_tb_System.
   Same change in the full script: 01_BackOffice_Stock.sql - change both together.

   FIFO cost batches (StockSystem.md 6.30). Fixes U025: a GRN at another selling price changed the item's cost, so
   the till showed the new cost on the old-price stock.
     - every stock-in is a batch (price + cost + qty left): z_tb_StockBatch; what each movement took: z_tb_StockBatchMove
     - a sale / PRN / minus adjustment takes from the batches: same price first, then the normal price, oldest first
     - GRN line at another price than the item's RetailPrice -> its batch is at a price link (made when there is none)
     - the item's CostPrice / each link's CostPrice = the cost of the oldest batch left at that price
     - a link price sold out -> the link is deleted (Status 0)
     - the normal price sold out while a link price has stock -> that price becomes the item's RetailPrice, link deleted
     - UDate moves on every change, so the tills download it. No ItemApi / TillService change.
   z_sp_PostPurchaseDoc: the U025 price code is gone (the batches do it).

   This file changes NO data and the batches stay OFF (z_tb_System.StockBatchAt NULL) until you run:
     EXEC dbo.z_sp_RebuildStockBatches @LocationId = 1, @DryRun = 1;   -- lists what would change, rolls back
     EXEC dbo.z_sp_RebuildStockBatches @LocationId = 1, @DryRun = 0;   -- builds the batches from the ledger, switches on

   sqlcmd -S <server> -d easyway -E -I -b -i U026_BackOffice_StockBatches.sql
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;   -- filtered indexes
GO
IF OBJECT_ID(N'dbo.z_tb_StockLedger', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_ItemPriceLink', 'U') IS NULL
   OR OBJECT_ID(N'dbo.z_sp_PostStockMovements', 'P') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_StockLedger / z_tb_ItemPriceLink / z_sp_PostStockMovements not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- when z_sp_RebuildStockBatches built the cost batches of the location; NULL = batches off
IF COL_LENGTH('dbo.z_tb_System', 'StockBatchAt') IS NULL
    ALTER TABLE dbo.z_tb_System ADD StockBatchAt DATETIME NULL;
GO

-- Cost batches (FIFO): one row per stock-in, Qty = what is left. Written by z_sp_ApplyStockBatches only.
-- An item's open batches add up to its balance (0 while the balance is below 0).
IF OBJECT_ID('dbo.z_tb_StockBatch', 'U') IS NULL
    CREATE TABLE dbo.z_tb_StockBatch (
        BatchId      INT           IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_StockBatch PRIMARY KEY,   -- = FIFO order
        LocationId   INT           NOT NULL,
        ItemId       INT           NOT NULL,
        SellPrice    DECIMAL(18,2) NULL,       -- NULL = the item's normal price (follows z_tb_ItemDet.RetailPrice)
        PriceLinkId  INT           NULL,       -- set = stock at that price link's price
        CostPrice    DECIMAL(18,2) NULL,
        InQty        DECIMAL(18,3) NOT NULL,   -- came in
        Qty          DECIMAL(18,3) NOT NULL,   -- left; 0 = sold out
        LedgerId     BIGINT        NOT NULL,   -- the movement that brought it in
        TxnType      INT           NOT NULL,
        DocNo        VARCHAR(30)   NOT NULL,
        InDate       DATETIME      NOT NULL,
        UDate        DATETIME      NOT NULL CONSTRAINT DF_z_tb_StockBatch_UDate DEFAULT (GETDATE())
    );
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_StockBatch_Open')
    CREATE INDEX IX_z_tb_StockBatch_Open ON dbo.z_tb_StockBatch (LocationId, ItemId, BatchId)
        INCLUDE (Qty, SellPrice, PriceLinkId, CostPrice) WHERE Qty > 0;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_StockBatch_Link')
    CREATE INDEX IX_z_tb_StockBatch_Link ON dbo.z_tb_StockBatch (PriceLinkId) INCLUDE (Qty) WHERE PriceLinkId IS NOT NULL;
GO

-- Which batch each ledger row took from (-) or put into (+). Sale cost at FIFO = these rows x the batch cost.
IF OBJECT_ID('dbo.z_tb_StockBatchMove', 'U') IS NULL
    CREATE TABLE dbo.z_tb_StockBatchMove (
        LedgerId  BIGINT        NOT NULL,
        BatchId   INT           NOT NULL,
        Qty       DECIMAL(18,3) NOT NULL,   -- signed
        CONSTRAINT PK_z_tb_StockBatchMove PRIMARY KEY (LedgerId, BatchId)
    );
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_StockBatchMove_Batch')
    CREATE INDEX IX_z_tb_StockBatchMove_Batch ON dbo.z_tb_StockBatchMove (BatchId);
GO

-- procs first, then the type they take
IF OBJECT_ID(N'dbo.z_sp_PostStockMovements', 'P')  IS NOT NULL DROP PROCEDURE dbo.z_sp_PostStockMovements;
IF OBJECT_ID(N'dbo.z_sp_ApplyStockBatches', 'P')   IS NOT NULL DROP PROCEDURE dbo.z_sp_ApplyStockBatches;
IF OBJECT_ID(N'dbo.z_sp_RebuildStockBatches', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_RebuildStockBatches;
IF OBJECT_ID(N'dbo.z_sp_PostPurchaseDoc', 'P')     IS NOT NULL DROP PROCEDURE dbo.z_sp_PostPurchaseDoc;
GO
IF TYPE_ID(N'dbo.z_tt_LedgerId') IS NOT NULL DROP TYPE dbo.z_tt_LedgerId;
GO
CREATE TYPE dbo.z_tt_LedgerId AS TABLE (
    LedgerId  BIGINT NOT NULL PRIMARY KEY
);
GO
/* ---------------------------------------------------------------------------
   4. Procs
   --------------------------------------------------------------------------- */

-- FIFO cost batches and the prices that follow them (StockSystem.md 6.30). Called by z_sp_PostStockMovements with the
-- ledger rows it just wrote (in its transaction, before the balance moves), and by z_sp_RebuildStockBatches (@FromZero 1).
-- Does nothing for a location whose batches are off (z_tb_System.StockBatchAt NULL).
--   + row: a new batch (when the stock was below 0, only the part above 0). A GRN line keeps its selling price: another
--          price than the item's RetailPrice = stock at a price link (made when there is none). Refund / adjustment /
--          opening: the item's normal price (a refund at an active link's price: that link).
--   - row: takes from the batches left - same price first, then the normal price, then the rest; oldest first.
--   Then per item: normal-price stock sold out while a link price has stock -> that price becomes RetailPrice (link
--   Status 0); a link price sold out -> link Status 0; CostPrice of the item / each link = its oldest batch left.
--   UDate moves only on a change, so the tills download the new prices.
CREATE PROCEDURE dbo.z_sp_ApplyStockBatches
    @LocationId INT,
    @Ids        dbo.z_tt_LedgerId READONLY,
    @FromZero   BIT = 0   -- 1 = rebuild: the stock starts at 0 (else: the balance before these rows)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(@FromZero, 0) = 0
       AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_System
                       WHERE LocaId = RIGHT('00' + CAST(@LocationId AS VARCHAR(5)), 2) AND StockBatchAt IS NOT NULL)
        RETURN;

    DECLARE @rows TABLE (Rn INT IDENTITY(1,1) PRIMARY KEY, LedgerId BIGINT, ItemId INT, TxnType INT, DocNo VARCHAR(30),
                         Qty DECIMAL(18,3), CostPrice DECIMAL(18,2), SellPrice DECIMAL(18,2), TxnDate DATETIME);
    DECLARE @bal TABLE (ItemId INT PRIMARY KEY, Qty DECIMAL(18,3));   -- running stock per item
    DECLARE @newLink TABLE (BatchId INT PRIMARY KEY);                  -- GRN batches at a price without a link
    DECLARE @mk TABLE (ItemId INT, Price DECIMAL(18,2), BatchId INT, PRIMARY KEY (ItemId, Price));
    DECLARE @up TABLE (ItemId INT PRIMARY KEY, PriceLinkId INT);
    DECLARE @Rn INT, @Max INT, @LedgerId BIGINT, @ItemId INT, @TxnType INT, @DocNo VARCHAR(30), @TxnDate DATETIME,
            @Qty DECIMAL(18,3), @B DECIMAL(18,3), @Add DECIMAL(18,3), @Take DECIMAL(18,3),
            @Cost DECIMAL(18,2), @Sell DECIMAL(18,2), @Main DECIMAL(18,2), @Price DECIMAL(18,2),
            @LinkId INT, @BatchId INT;

    INSERT @rows (LedgerId, ItemId, TxnType, DocNo, Qty, CostPrice, SellPrice, TxnDate)
    SELECT g.LedgerId, g.ItemId, g.TxnType, g.DocNo, g.Qty, g.CostPrice, g.SellPrice, g.TxnDate
    FROM @Ids i JOIN dbo.z_tb_StockLedger g ON g.LedgerId = i.LedgerId
    WHERE g.LocationId = @LocationId AND g.Qty <> 0
    ORDER BY g.LedgerId;

    INSERT @bal (ItemId, Qty)
    SELECT r.ItemId, CASE WHEN @FromZero = 1 THEN 0 ELSE ISNULL(MAX(b.Qty), 0) END
    FROM @rows r
    LEFT JOIN dbo.z_tb_StockBalance b WITH (UPDLOCK, HOLDLOCK)   -- one poster per item at a time (two tills at once)
           ON b.LocationId = @LocationId AND b.ItemId = r.ItemId
    GROUP BY r.ItemId;

    SELECT @Rn = 1, @Max = ISNULL(MAX(Rn), 0) FROM @rows;
    WHILE @Rn <= @Max
    BEGIN
        SELECT @LedgerId = LedgerId, @ItemId = ItemId, @TxnType = TxnType, @DocNo = DocNo, @Qty = Qty,
               @Cost = NULLIF(CostPrice, 0), @Sell = SellPrice, @TxnDate = TxnDate
        FROM @rows WHERE Rn = @Rn;
        SELECT @B = Qty FROM @bal WHERE ItemId = @ItemId;
        SET @Main = NULL;
        SELECT @Main = RetailPrice FROM dbo.z_tb_ItemDet WHERE ItemId = @ItemId AND LocationId = @LocationId;

        IF @Qty > 0
        BEGIN
            -- stock below 0 is filled first (those items were sold before they came in)
            SET @Add = CASE WHEN @B + @Qty > 0 THEN @B + @Qty ELSE 0 END - CASE WHEN @B > 0 THEN @B ELSE 0 END;
            IF @Add > 0
            BEGIN
                SET @Price = CASE WHEN @Sell > 0 AND @Sell <> ISNULL(@Main, 0) THEN @Sell END;
                SET @LinkId = NULL;
                IF @Price IS NOT NULL
                    SELECT @LinkId = PriceLinkId FROM dbo.z_tb_ItemPriceLink
                    WHERE ItemId = @ItemId AND LocationId = @LocationId AND RetailPrice = @Price AND Status = 1;
                IF @TxnType <> 1 AND @LinkId IS NULL
                    SET @Price = NULL;   -- only a GRN brings in a new price
                IF @TxnType <> 1 OR @Cost IS NULL
                    -- not a GRN (or a GRN line without a cost): the cost of that price now, else the ledger's (AvgCost)
                    SET @Cost = ISNULL(CASE WHEN @LinkId IS NOT NULL
                                            THEN (SELECT NULLIF(CostPrice, 0) FROM dbo.z_tb_ItemPriceLink WHERE PriceLinkId = @LinkId)
                                            ELSE (SELECT NULLIF(CostPrice, 0) FROM dbo.z_tb_ItemDet
                                                  WHERE ItemId = @ItemId AND LocationId = @LocationId) END, @Cost);

                INSERT dbo.z_tb_StockBatch
                    (LocationId, ItemId, SellPrice, PriceLinkId, CostPrice, InQty, Qty, LedgerId, TxnType, DocNo, InDate)
                VALUES (@LocationId, @ItemId, @Price, @LinkId, @Cost, @Add, @Add, @LedgerId, @TxnType, @DocNo, @TxnDate);
                SET @BatchId = SCOPE_IDENTITY();
                INSERT dbo.z_tb_StockBatchMove (LedgerId, BatchId, Qty) VALUES (@LedgerId, @BatchId, @Add);
                IF @Price IS NOT NULL AND @LinkId IS NULL
                    INSERT @newLink (BatchId) VALUES (@BatchId);
            END
        END
        ELSE
        BEGIN
            SET @Add = -@Qty;   -- still to take
            WHILE @Add > 0
            BEGIN
                SET @BatchId = NULL;
                SELECT TOP 1 @BatchId = BatchId, @Take = Qty
                FROM dbo.z_tb_StockBatch
                WHERE LocationId = @LocationId AND ItemId = @ItemId AND Qty > 0
                ORDER BY CASE WHEN SellPrice = @Sell THEN 0 WHEN SellPrice IS NULL THEN 1 ELSE 2 END, BatchId;
                IF @BatchId IS NULL BREAK;   -- nothing left: the rest takes the stock below 0
                IF @Take > @Add SET @Take = @Add;
                UPDATE dbo.z_tb_StockBatch SET Qty = Qty - @Take, UDate = GETDATE() WHERE BatchId = @BatchId;
                INSERT dbo.z_tb_StockBatchMove (LedgerId, BatchId, Qty) VALUES (@LedgerId, @BatchId, -@Take);
                SET @Add = @Add - @Take;
            END
        END

        UPDATE @bal SET Qty = Qty + @Qty WHERE ItemId = @ItemId;
        SET @Rn = @Rn + 1;
    END

    -- GRN stock at a new price that is still there: its price link (one per price, cost of its oldest batch)
    INSERT @mk (ItemId, Price, BatchId)
    SELECT s.ItemId, s.SellPrice, MIN(s.BatchId)
    FROM @newLink n JOIN dbo.z_tb_StockBatch s ON s.BatchId = n.BatchId
    WHERE s.Qty > 0 AND s.PriceLinkId IS NULL
    GROUP BY s.ItemId, s.SellPrice;

    INSERT dbo.z_tb_ItemPriceLink (ItemId, LocationId, RetailPrice, CostPrice, Remark)
    SELECT m.ItemId, @LocationId, m.Price, s.CostPrice, N'From ' + s.DocNo
    FROM @mk m JOIN dbo.z_tb_StockBatch s ON s.BatchId = m.BatchId
    WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_ItemPriceLink k WITH (UPDLOCK, HOLDLOCK)
                      WHERE k.ItemId = m.ItemId AND k.LocationId = @LocationId AND k.RetailPrice = m.Price AND k.Status = 1);

    UPDATE s SET PriceLinkId = k.PriceLinkId, UDate = GETDATE()
    FROM dbo.z_tb_StockBatch s
    JOIN @mk m ON m.ItemId = s.ItemId AND m.Price = s.SellPrice
    JOIN dbo.z_tb_ItemPriceLink k ON k.ItemId = s.ItemId AND k.LocationId = @LocationId AND k.RetailPrice = s.SellPrice AND k.Status = 1
    WHERE s.LocationId = @LocationId AND s.PriceLinkId IS NULL;

    /* ---- prices follow the batches, items of these rows only ---- */
    DECLARE @it TABLE (ItemId INT PRIMARY KEY);
    INSERT @it (ItemId) SELECT ItemId FROM @bal;

    -- RetailPrice was changed to a link's price: that link goes, its stock is normal-price stock
    UPDATE k SET Status = 0, UDate = GETDATE()
    FROM dbo.z_tb_ItemPriceLink k
    JOIN @it i ON i.ItemId = k.ItemId
    JOIN dbo.z_tb_ItemDet d ON d.ItemId = k.ItemId AND d.LocationId = k.LocationId AND d.RetailPrice = k.RetailPrice
    WHERE k.LocationId = @LocationId AND k.Status = 1
      AND EXISTS (SELECT 1 FROM dbo.z_tb_StockBatch s WHERE s.PriceLinkId = k.PriceLinkId);

    UPDATE s SET SellPrice = NULL, PriceLinkId = NULL, UDate = GETDATE()
    FROM dbo.z_tb_StockBatch s
    JOIN @it i ON i.ItemId = s.ItemId
    JOIN dbo.z_tb_ItemDet d ON d.ItemId = s.ItemId AND d.LocationId = s.LocationId
    WHERE s.LocationId = @LocationId AND s.Qty > 0 AND s.SellPrice = d.RetailPrice;

    -- the link was deleted in Item Entry: its stock is sold at the normal price now
    UPDATE s SET SellPrice = NULL, PriceLinkId = NULL, UDate = GETDATE()
    FROM dbo.z_tb_StockBatch s
    JOIN @it i ON i.ItemId = s.ItemId
    LEFT JOIN dbo.z_tb_ItemPriceLink k ON k.PriceLinkId = s.PriceLinkId AND k.Status = 1
    WHERE s.LocationId = @LocationId AND s.Qty > 0 AND s.SellPrice IS NOT NULL AND k.PriceLinkId IS NULL;

    -- normal-price stock sold out, a link price still has stock: the oldest such price becomes the RetailPrice
    INSERT @up (ItemId, PriceLinkId)
    SELECT s.ItemId, s.PriceLinkId
    FROM dbo.z_tb_StockBatch s
    JOIN (SELECT b.ItemId, MIN(b.BatchId) AS BatchId
          FROM dbo.z_tb_StockBatch b JOIN @it i ON i.ItemId = b.ItemId
          WHERE b.LocationId = @LocationId AND b.Qty > 0
          GROUP BY b.ItemId
          HAVING MAX(CASE WHEN b.SellPrice IS NULL THEN 1 ELSE 0 END) = 0) f ON f.BatchId = s.BatchId;

    UPDATE d SET RetailPrice = k.RetailPrice, WholesalePrice = ISNULL(k.WholesalePrice, d.WholesalePrice), UDate = GETDATE()
    FROM dbo.z_tb_ItemDet d
    JOIN @up u ON u.ItemId = d.ItemId
    JOIN dbo.z_tb_ItemPriceLink k ON k.PriceLinkId = u.PriceLinkId
    WHERE d.LocationId = @LocationId;

    UPDATE k SET Status = 0, UDate = GETDATE()
    FROM dbo.z_tb_ItemPriceLink k JOIN @up u ON u.PriceLinkId = k.PriceLinkId
    WHERE k.Status = 1;

    UPDATE s SET SellPrice = NULL, PriceLinkId = NULL, UDate = GETDATE()
    FROM dbo.z_tb_StockBatch s JOIN @up u ON u.ItemId = s.ItemId AND u.PriceLinkId = s.PriceLinkId
    WHERE s.LocationId = @LocationId AND s.Qty > 0;

    -- a link price sold out: the link goes (links that never had a batch - typed in Item Entry - stay)
    UPDATE k SET Status = 0, UDate = GETDATE()
    FROM dbo.z_tb_ItemPriceLink k
    JOIN @it i ON i.ItemId = k.ItemId
    WHERE k.LocationId = @LocationId AND k.Status = 1
      AND EXISTS (SELECT 1 FROM dbo.z_tb_StockBatch s WHERE s.PriceLinkId = k.PriceLinkId)
      AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_StockBatch s WHERE s.PriceLinkId = k.PriceLinkId AND s.Qty > 0);

    -- the cost the till shows (profit view, bill discount cap) = the oldest batch left at that price
    UPDATE d SET CostPrice = c.CostPrice, UDate = GETDATE()
    FROM dbo.z_tb_ItemDet d
    JOIN (SELECT s.ItemId, s.CostPrice, ROW_NUMBER() OVER (PARTITION BY s.ItemId ORDER BY s.BatchId) AS rn
          FROM dbo.z_tb_StockBatch s JOIN @it i ON i.ItemId = s.ItemId
          WHERE s.LocationId = @LocationId AND s.Qty > 0 AND s.SellPrice IS NULL AND s.CostPrice IS NOT NULL) c
      ON c.ItemId = d.ItemId AND c.rn = 1
    WHERE d.LocationId = @LocationId AND ISNULL(d.CostPrice, -1) <> c.CostPrice;

    UPDATE k SET CostPrice = c.CostPrice, UDate = GETDATE()
    FROM dbo.z_tb_ItemPriceLink k
    JOIN (SELECT s.PriceLinkId, s.CostPrice, ROW_NUMBER() OVER (PARTITION BY s.PriceLinkId ORDER BY s.BatchId) AS rn
          FROM dbo.z_tb_StockBatch s JOIN @it i ON i.ItemId = s.ItemId
          WHERE s.LocationId = @LocationId AND s.Qty > 0 AND s.PriceLinkId IS NOT NULL AND s.CostPrice IS NOT NULL) c
      ON c.PriceLinkId = k.PriceLinkId AND c.rn = 1
    WHERE k.Status = 1 AND ISNULL(k.CostPrice, -1) <> c.CostPrice;
END
GO
-- The ONLY writer of z_tb_StockLedger / z_tb_StockBalance.
-- Skips lines already in the ledger (same TxnType+DocNo+DocLineNo), so callers can safely retry.
CREATE PROCEDURE dbo.z_sp_PostStockMovements
    @LocationId     INT,
    @UserId         VARCHAR(20) = NULL,
    @Moves          dbo.z_tt_StockMovement READONLY,
    @InsertedCount  INT = NULL OUTPUT
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ins TABLE (LedgerId BIGINT, ItemId INT, Qty DECIMAL(18,3), CostPrice DECIMAL(18,2), TxnType INT);
    DECLARE @ids dbo.z_tt_LedgerId;

    BEGIN TRAN;

    INSERT dbo.z_tb_StockLedger
        (LocationId, ItemId, TxnType, DocNo, DocLineNo, TerminalId, ZNo, Qty, CostPrice, SellPrice, TxnDate, UserId)
    OUTPUT inserted.LedgerId, inserted.ItemId, inserted.Qty, inserted.CostPrice, inserted.TxnType INTO @ins
    SELECT @LocationId, m.ItemId, m.TxnType, m.DocNo, m.DocLineNo, m.TerminalId, m.ZNo, m.Qty, m.CostPrice, m.SellPrice, m.TxnDate, @UserId
    FROM @Moves m
    WHERE m.Qty <> 0
      AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_StockLedger g WITH (UPDLOCK, HOLDLOCK)
                      WHERE g.TxnType = m.TxnType AND g.DocNo = m.DocNo AND g.DocLineNo = m.DocLineNo);

    SET @InsertedCount = @@ROWCOUNT;

    -- first movement of an item at this location creates its balance row
    INSERT dbo.z_tb_StockBalance (LocationId, ItemId, Qty)
    SELECT DISTINCT @LocationId, i.ItemId, 0
    FROM @ins i
    WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_StockBalance b WITH (UPDLOCK, HOLDLOCK)
                      WHERE b.LocationId = @LocationId AND b.ItemId = i.ItemId);

    -- FIFO cost batches + the prices that follow them (needs the balance before these rows, so before the UPDATE)
    INSERT @ids (LedgerId) SELECT LedgerId FROM @ins;
    EXEC dbo.z_sp_ApplyStockBatches @LocationId = @LocationId, @Ids = @ids;

    -- Qty = Qty + movement (atomic, so two tills posting at once can't overwrite each other).
    -- AvgCost: weighted average over GRN lines that carry a cost; negative stock is treated as 0.
    UPDATE b SET
        AvgCost = CASE WHEN x.InQty > 0
                       THEN (CASE WHEN b.Qty > 0 THEN b.Qty * ISNULL(b.AvgCost, 0) ELSE 0 END + x.InValue)
                            / (CASE WHEN b.Qty > 0 THEN b.Qty ELSE 0 END + x.InQty)
                       ELSE b.AvgCost END,
        Qty          = b.Qty + x.Qty,
        LastLedgerId = x.LastLedgerId,
        UDate        = GETDATE()
    FROM dbo.z_tb_StockBalance b
    JOIN (SELECT ItemId,
                 SUM(Qty) AS Qty,
                 SUM(CASE WHEN TxnType = 1 AND CostPrice IS NOT NULL THEN Qty ELSE 0 END)             AS InQty,
                 SUM(CASE WHEN TxnType = 1 AND CostPrice IS NOT NULL THEN Qty * CostPrice ELSE 0 END) AS InValue,
                 MAX(LedgerId) AS LastLedgerId
          FROM @ins
          GROUP BY ItemId) x ON x.ItemId = b.ItemId
    WHERE b.LocationId = @LocationId;

    COMMIT;
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
-- Posts a GRN (@Type 1, +Qty) or PRN (@Type 2, -Qty) from z_tb_TempPurchase into stock
-- and marks the summary + lines Status = 2 (posted). Posting twice is refused.
-- Prices: each line's selling price + cost go into its cost batch (z_sp_ApplyStockBatches, StockSystem.md 6.30).
CREATE PROCEDURE dbo.z_sp_PostPurchaseDoc
    @DocNo   VARCHAR(20),
    @Type    INT,
    @UserId  VARCHAR(20) = NULL,
    @PostedLines INT = NULL OUTPUT
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LocationId INT, @Status INT, @PDate DATETIME, @Moves dbo.z_tt_StockMovement;

    SELECT @LocationId = ISNULL(LocationId, 1), @Status = Status, @PDate = PDate
    FROM dbo.z_tb_TempPurchaseSummary
    WHERE GrnNo = @DocNo AND ISNULL(Type, 1) = @Type;

    IF @@ROWCOUNT = 0
        RAISERROR(N'%s', 16, 1, N'Document not found.');
    IF @Status = 2
        RAISERROR(N'%s', 16, 1, N'Document is already posted to stock.');

    INSERT @Moves (TxnType, DocNo, DocLineNo, ItemId, Qty, CostPrice, SellPrice, TerminalId, ZNo, TxnDate)
    SELECT @Type,                                   -- TxnType 1 GRN / 2 PRN
           @DocNo,
           ROW_NUMBER() OVER (ORDER BY Idx),
           ItemId,
           CASE WHEN @Type = 2 THEN -ISNULL(Qty, 0) ELSE ISNULL(Qty, 0) END,
           CostPrice, SellPrice, NULL, NULL,
           ISNULL(@PDate, GETDATE())
    FROM dbo.z_tb_TempPurchase
    WHERE GrnNo = @DocNo AND ISNULL(Qty, 0) <> 0;

    IF NOT EXISTS (SELECT 1 FROM @Moves)
        RAISERROR(N'%s', 16, 1, N'Document has no lines with quantity.');

    BEGIN TRAN;
        EXEC dbo.z_sp_PostStockMovements @LocationId = @LocationId, @UserId = @UserId, @Moves = @Moves,
                                         @InsertedCount = @PostedLines OUTPUT;

        UPDATE dbo.z_tb_TempPurchaseSummary SET Status = 2, UDate = GETDATE()
        WHERE GrnNo = @DocNo AND ISNULL(Type, 1) = @Type;

        UPDATE dbo.z_tb_TempPurchase SET Status = 2, UDate = GETDATE()
        WHERE GrnNo = @DocNo;
    COMMIT;
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
-- Builds the cost batches of a location again from its whole stock ledger and switches them on (StockSystem.md 6.30).
-- Prices follow (links made / deleted, RetailPrice / CostPrice), so run @DryRun = 1 first: it does everything, lists what
-- would change and rolls back. Result sets: 1 summary, 2 items with a new RetailPrice / CostPrice, 3 price links.
CREATE PROCEDURE dbo.z_sp_RebuildStockBatches
    @LocationId INT = 1,
    @DryRun     BIT = 1
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LocaCode VARCHAR(5), @Ids dbo.z_tt_LedgerId;
    DECLARE @itemWas TABLE (ItemId INT PRIMARY KEY, RetailPrice DECIMAL(18,2), CostPrice DECIMAL(18,2));
    DECLARE @linkWas TABLE (PriceLinkId INT PRIMARY KEY, CostPrice DECIMAL(18,2));
    -- table variables keep their rows after a ROLLBACK, so the dry run can still show them
    DECLARE @sum TABLE (LedgerRows INT, Batches INT, OpenBatches INT, OpenQty DECIMAL(18,3), StockQty DECIMAL(18,3), ItemsOff INT);
    DECLARE @itemChg TABLE (ItemId INT PRIMARY KEY, RetailWas DECIMAL(18,2), RetailNow DECIMAL(18,2),
                            CostWas DECIMAL(18,2), CostNow DECIMAL(18,2));
    DECLARE @linkChg TABLE (PriceLinkId INT PRIMARY KEY, ItemId INT, RetailPrice DECIMAL(18,2), Change VARCHAR(10),
                            CostWas DECIMAL(18,2), CostNow DECIMAL(18,2), Remark NVARCHAR(50), OpenQty DECIMAL(18,3));

    SET @LocaCode = RIGHT('00' + CAST(@LocationId AS VARCHAR(5)), 2);
    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_System WHERE LocaId = @LocaCode)
        RAISERROR(N'%s', 16, 1, N'z_tb_System row not found for this location.');

    BEGIN TRAN;
        -- nothing else posts stock here until the rebuild is done
        SELECT @LocaCode = LocaId FROM dbo.z_tb_System WITH (UPDLOCK, HOLDLOCK) WHERE LocaId = @LocaCode;
        SELECT TOP 1 @LocaCode = @LocaCode FROM dbo.z_tb_StockBalance WITH (TABLOCKX, HOLDLOCK);

        INSERT @itemWas SELECT ItemId, RetailPrice, CostPrice FROM dbo.z_tb_ItemDet WHERE LocationId = @LocationId;
        INSERT @linkWas SELECT PriceLinkId, CostPrice FROM dbo.z_tb_ItemPriceLink WHERE LocationId = @LocationId AND Status = 1;
        INSERT @Ids SELECT LedgerId FROM dbo.z_tb_StockLedger WHERE LocationId = @LocationId;

        DELETE m FROM dbo.z_tb_StockBatchMove m JOIN dbo.z_tb_StockBatch s ON s.BatchId = m.BatchId WHERE s.LocationId = @LocationId;
        DELETE dbo.z_tb_StockBatch WHERE LocationId = @LocationId;
        EXEC dbo.z_sp_ApplyStockBatches @LocationId = @LocationId, @Ids = @Ids, @FromZero = 1;
        UPDATE dbo.z_tb_System SET StockBatchAt = GETDATE() WHERE LocaId = @LocaCode;

        INSERT @sum
        SELECT (SELECT COUNT(*) FROM @Ids),
               (SELECT COUNT(*) FROM dbo.z_tb_StockBatch WHERE LocationId = @LocationId),
               (SELECT COUNT(*) FROM dbo.z_tb_StockBatch WHERE LocationId = @LocationId AND Qty > 0),
               (SELECT ISNULL(SUM(Qty), 0) FROM dbo.z_tb_StockBatch WHERE LocationId = @LocationId),
               (SELECT ISNULL(SUM(Qty), 0) FROM dbo.z_tb_StockBalance WHERE LocationId = @LocationId AND Qty > 0),
               -- must be 0: an item's batches = its balance (0 when below 0)
               (SELECT COUNT(*) FROM dbo.z_tb_StockBalance b
                WHERE b.LocationId = @LocationId
                  AND CASE WHEN b.Qty > 0 THEN b.Qty ELSE 0 END
                      <> ISNULL((SELECT SUM(s.Qty) FROM dbo.z_tb_StockBatch s
                                 WHERE s.LocationId = b.LocationId AND s.ItemId = b.ItemId), 0));

        INSERT @itemChg
        SELECT d.ItemId, w.RetailPrice, d.RetailPrice, w.CostPrice, d.CostPrice
        FROM dbo.z_tb_ItemDet d JOIN @itemWas w ON w.ItemId = d.ItemId
        WHERE d.LocationId = @LocationId
          AND (ISNULL(d.RetailPrice, -1) <> ISNULL(w.RetailPrice, -1) OR ISNULL(d.CostPrice, -1) <> ISNULL(w.CostPrice, -1));

        INSERT @linkChg
        SELECT k.PriceLinkId, k.ItemId, k.RetailPrice,
               CASE WHEN w.PriceLinkId IS NULL THEN 'added' WHEN k.Status = 0 THEN 'deleted' ELSE 'cost' END,
               w.CostPrice, k.CostPrice, k.Remark,
               (SELECT SUM(s.Qty) FROM dbo.z_tb_StockBatch s WHERE s.PriceLinkId = k.PriceLinkId)
        FROM dbo.z_tb_ItemPriceLink k
        LEFT JOIN @linkWas w ON w.PriceLinkId = k.PriceLinkId
        WHERE k.LocationId = @LocationId
          AND (w.PriceLinkId IS NULL AND k.Status = 1
               OR w.PriceLinkId IS NOT NULL AND (k.Status = 0 OR ISNULL(k.CostPrice, -1) <> ISNULL(w.CostPrice, -1)));
    IF @DryRun = 1
        ROLLBACK;
    ELSE
        COMMIT;

    SELECT CASE WHEN @DryRun = 1 THEN 'DRY RUN - nothing was changed' ELSE 'Done - batches are on' END AS Result,
           s.*, (SELECT COUNT(*) FROM @itemChg) AS ItemsChanged,
           (SELECT COUNT(*) FROM @linkChg WHERE Change = 'added') AS LinksAdded,
           (SELECT COUNT(*) FROM @linkChg WHERE Change = 'deleted') AS LinksDeleted,
           (SELECT COUNT(*) FROM @linkChg WHERE Change = 'cost') AS LinkCostsChanged
    FROM @sum s;

    SELECT c.ItemId, i.RefCode, i.Barcode, i.Descrip, c.RetailWas, c.RetailNow, c.CostWas, c.CostNow
    FROM @itemChg c LEFT JOIN dbo.z_tb_Item i ON i.ItemId = c.ItemId
    ORDER BY i.Descrip;

    SELECT c.Change, c.PriceLinkId, c.ItemId, i.RefCode, i.Descrip, c.RetailPrice, c.CostWas, c.CostNow, c.OpenQty, c.Remark
    FROM @linkChg c LEFT JOIN dbo.z_tb_Item i ON i.ItemId = c.ItemId
    ORDER BY c.Change, i.Descrip;
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
PRINT 'U026 done: cost batches installed (OFF). Next: EXEC dbo.z_sp_RebuildStockBatches @LocationId = 1, @DryRun = 1;';
GO
