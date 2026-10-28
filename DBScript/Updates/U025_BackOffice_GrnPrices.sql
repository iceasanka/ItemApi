/* =============================================================================
   U025_BackOffice_GrnPrices.sql   (2026-10-28)
   Run on: back office db (easyway). SQL Server 2008 R2 and newer. Safe to run again. No table or data change.
   Needs: z_tb_TempPurchase(Summary) / z_tb_ItemDet / z_tb_ItemPriceLink / z_sp_PostStockMovements.
   Same change in the full script: 01_BackOffice_Stock.sql (z_sp_PostPurchaseDoc) - change both together.

   GRN commit now updates prices (StockSystem.md section 6.1). Before, it only moved stock:
     - the item's CostPrice (z_tb_ItemDet) = the GRN cost (the item's last line with a cost > 0)
     - a selling price other than the item's RetailPrice -> a new price link (z_tb_ItemPriceLink) with the GRN cost,
       Remark 'From GRN00000017'. An active link with that price already there gets the new cost.
     - UDate moves, so the tills download the new cost / links on their next sync.
   PRN commit: no price change. GRNs committed before this script are not changed.

   sqlcmd -S <server> -d easyway -E -I -b -i U025_BackOffice_GrnPrices.sql
   No ItemApi / TillService change needed.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_TempPurchaseSummary', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_ItemPriceLink', 'U') IS NULL
   OR OBJECT_ID(N'dbo.z_sp_PostStockMovements', 'P') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_TempPurchaseSummary / z_tb_ItemPriceLink / z_sp_PostStockMovements not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.z_sp_PostPurchaseDoc', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_PostPurchaseDoc;
GO
-- Posts a GRN (@Type 1, +Qty) or PRN (@Type 2, -Qty) from z_tb_TempPurchase into stock
-- and marks the summary + lines Status = 2 (posted). Posting twice is refused.
-- GRN only, prices (StockSystem.md 6.1): the item's CostPrice = the GRN cost (last line of the item, cost > 0);
-- a selling price other than the item's RetailPrice becomes a price link with the GRN cost (an active link with
-- that price already there gets the new cost). UDate moves, so the tills download the new prices.
CREATE PROCEDURE dbo.z_sp_PostPurchaseDoc
    @DocNo   VARCHAR(20),
    @Type    INT,
    @UserId  VARCHAR(20) = NULL,
    @PostedLines INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;
    BEGIN TRY
        DECLARE @LocationId INT, @Status INT, @PDate DATETIME, @Moves dbo.z_tt_StockMovement;
        DECLARE @LinkUserId INT;
        DECLARE @Links TABLE (ItemId INT, SellPrice DECIMAL(18,2), CostPrice DECIMAL(18,2), PRIMARY KEY (ItemId, SellPrice));
        SET @LinkUserId = CASE WHEN LEN(@UserId) BETWEEN 1 AND 9 AND @UserId NOT LIKE '%[^0-9]%' THEN CAST(@UserId AS INT) END;

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

            IF @Type = 1
            BEGIN
                UPDATE d SET CostPrice = p.CostPrice, UDate = GETDATE()
                FROM dbo.z_tb_ItemDet d
                JOIN (SELECT ItemId, CostPrice, ROW_NUMBER() OVER (PARTITION BY ItemId ORDER BY Idx DESC) AS rn
                      FROM dbo.z_tb_TempPurchase
                      WHERE GrnNo = @DocNo AND ISNULL(Qty, 0) <> 0 AND CostPrice > 0) p ON p.ItemId = d.ItemId AND p.rn = 1
                WHERE d.LocationId = @LocationId AND ISNULL(d.CostPrice, -1) <> p.CostPrice;

                INSERT @Links (ItemId, SellPrice, CostPrice)
                SELECT p.ItemId, p.SellPrice, CASE WHEN p.CostPrice > 0 THEN p.CostPrice END
                FROM (SELECT ItemId, SellPrice, CostPrice, ROW_NUMBER() OVER (PARTITION BY ItemId, SellPrice ORDER BY Idx DESC) AS rn
                      FROM dbo.z_tb_TempPurchase
                      WHERE GrnNo = @DocNo AND ISNULL(Qty, 0) <> 0 AND SellPrice > 0) p
                JOIN dbo.z_tb_ItemDet d ON d.ItemId = p.ItemId AND d.LocationId = @LocationId
                WHERE p.rn = 1 AND p.SellPrice <> ISNULL(d.RetailPrice, 0);

                UPDATE k SET CostPrice = l.CostPrice, UDate = GETDATE()
                FROM dbo.z_tb_ItemPriceLink k WITH (UPDLOCK, HOLDLOCK)
                JOIN @Links l ON l.ItemId = k.ItemId AND l.SellPrice = k.RetailPrice
                WHERE k.LocationId = @LocationId AND k.Status = 1 AND l.CostPrice IS NOT NULL
                  AND ISNULL(k.CostPrice, -1) <> l.CostPrice;

                INSERT dbo.z_tb_ItemPriceLink (ItemId, LocationId, RetailPrice, CostPrice, Remark, UserId)
                SELECT l.ItemId, @LocationId, l.SellPrice, l.CostPrice, N'From ' + @DocNo, @LinkUserId
                FROM @Links l
                WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_ItemPriceLink k WITH (UPDLOCK, HOLDLOCK)
                                  WHERE k.ItemId = l.ItemId AND k.LocationId = @LocationId AND k.RetailPrice = l.SellPrice AND k.Status = 1);
            END

            UPDATE dbo.z_tb_TempPurchaseSummary SET Status = 2, UDate = GETDATE()
            WHERE GrnNo = @DocNo AND ISNULL(Type, 1) = @Type;

            UPDATE dbo.z_tb_TempPurchase SET Status = 2, UDate = GETDATE()
            WHERE GrnNo = @DocNo;
        COMMIT;
    END TRY
    BEGIN CATCH
        DECLARE @z_msg NVARCHAR(2048); SET @z_msg = ERROR_MESSAGE();
        IF @z_tc = 0 BEGIN IF XACT_STATE() <> 0 ROLLBACK; END
        ELSE BEGIN WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT; END
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO
PRINT 'U025 done: z_sp_PostPurchaseDoc - GRN commit updates the item cost and adds price links.';
GO
