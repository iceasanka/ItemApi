/* =============================================================================
   09_Clean_ItemData.sql
   CLEAN START before going live: deletes ALL items and everything that points at them. Cannot be undone — back up first.
   Part A runs on the back office db (easyway). Part B runs on EACH till's db.

   Part A deletes:
     items          z_tb_Item, z_tb_ItemDet, z_tb_ItemOldCode (old-item transfer links), z_tb_ItemPriceLink,
                    z_tb_ScaleExportItem (scale "last exported" snapshot)
     stock          z_tb_StockLedger, z_tb_StockBalance, z_tb_StockAdjustment(+Item)
     till uploads   z_tb_SalesInvoice(+Item, z_tb_SalesPayment), z_tb_ZReport(+Item)
     documents      z_tb_SalesDoc(+Item) — quotations / invoices; their numbers start again at QT000001 / INV000001
     GRN            z_tb_TempPurchase, z_tb_TempPurchaseSummary (GRN / PRN documents and drafts)
   and resets their id counters, so the first new item is ItemId 1.
   KEPT: users, roles, customers, suppliers, categories, units, locations, terminals, salary, cheques, settings,
   the old tb_* tables. (Run 08 again afterwards to copy the old items back in.)

   Default = REPORT ONLY. Set @Delete = 1 to delete (one transaction: all or nothing).
   easyway is at compatibility level 100 (SQL 2008).
   ============================================================================= */

/* ---------------------------------------------------------------------------
   Part A — back office (easyway)
   --------------------------------------------------------------------------- */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Delete BIT = 0;   -- ← 1 = delete

SELECT 'z_tb_Item' AS TableName, COUNT(*) AS RowsNow FROM dbo.z_tb_Item
UNION ALL SELECT 'z_tb_ItemDet', COUNT(*) FROM dbo.z_tb_ItemDet
UNION ALL SELECT 'z_tb_ItemOldCode', COUNT(*) FROM dbo.z_tb_ItemOldCode
UNION ALL SELECT 'z_tb_ItemPriceLink', COUNT(*) FROM dbo.z_tb_ItemPriceLink
UNION ALL SELECT 'z_tb_ScaleExportItem', COUNT(*) FROM dbo.z_tb_ScaleExportItem
UNION ALL SELECT 'z_tb_StockLedger', COUNT(*) FROM dbo.z_tb_StockLedger
UNION ALL SELECT 'z_tb_StockBalance', COUNT(*) FROM dbo.z_tb_StockBalance
UNION ALL SELECT 'z_tb_StockAdjustment', COUNT(*) FROM dbo.z_tb_StockAdjustment
UNION ALL SELECT 'z_tb_StockAdjustmentItem', COUNT(*) FROM dbo.z_tb_StockAdjustmentItem
UNION ALL SELECT 'z_tb_SalesInvoice', COUNT(*) FROM dbo.z_tb_SalesInvoice
UNION ALL SELECT 'z_tb_SalesInvoiceItem', COUNT(*) FROM dbo.z_tb_SalesInvoiceItem
UNION ALL SELECT 'z_tb_SalesPayment', COUNT(*) FROM dbo.z_tb_SalesPayment
UNION ALL SELECT 'z_tb_ZReport', COUNT(*) FROM dbo.z_tb_ZReport
UNION ALL SELECT 'z_tb_ZReportItem', COUNT(*) FROM dbo.z_tb_ZReportItem
UNION ALL SELECT 'z_tb_SalesDoc', COUNT(*) FROM dbo.z_tb_SalesDoc
UNION ALL SELECT 'z_tb_SalesDocItem', COUNT(*) FROM dbo.z_tb_SalesDocItem
UNION ALL SELECT 'z_tb_TempPurchase', COUNT(*) FROM dbo.z_tb_TempPurchase
UNION ALL SELECT 'z_tb_TempPurchaseSummary', COUNT(*) FROM dbo.z_tb_TempPurchaseSummary;

IF @Delete = 1
BEGIN
    BEGIN TRAN;
        -- children first
        DELETE FROM dbo.z_tb_ItemOldCode;
        DELETE FROM dbo.z_tb_ItemPriceLink;
        DELETE FROM dbo.z_tb_ScaleExportItem;
        DELETE FROM dbo.z_tb_StockLedger;
        DELETE FROM dbo.z_tb_StockBalance;
        DELETE FROM dbo.z_tb_StockAdjustmentItem;
        DELETE FROM dbo.z_tb_StockAdjustment;
        DELETE FROM dbo.z_tb_SalesInvoiceItem;
        DELETE FROM dbo.z_tb_SalesPayment;
        DELETE FROM dbo.z_tb_SalesInvoice;
        DELETE FROM dbo.z_tb_ZReportItem;
        DELETE FROM dbo.z_tb_ZReport;
        DELETE FROM dbo.z_tb_SalesDocItem;
        DELETE FROM dbo.z_tb_SalesDoc;
        UPDATE dbo.z_tb_SalesDocCounter SET LastNo = 0;
        DELETE FROM dbo.z_tb_TempPurchase;
        DELETE FROM dbo.z_tb_TempPurchaseSummary;
        DELETE FROM dbo.z_tb_ItemDet;
        DELETE FROM dbo.z_tb_Item;

        -- id counters back to the start (next id = 1). A table whose counter was never used is left alone —
        -- reseeding it to 0 would make its first id 0.
        DECLARE @t SYSNAME, @sql NVARCHAR(400);
        DECLARE c CURSOR LOCAL FAST_FORWARD FOR
            SELECT OBJECT_NAME(ic.object_id) FROM sys.identity_columns ic
            WHERE OBJECT_NAME(ic.object_id) IN ('z_tb_Item', 'z_tb_ItemDet', 'z_tb_ItemPriceLink', 'z_tb_StockLedger',
                    'z_tb_StockAdjustment', 'z_tb_SalesInvoice', 'z_tb_ZReport', 'z_tb_SalesDoc', 'z_tb_SalesDocItem',
                    'z_tb_TempPurchase', 'z_tb_TempPurchaseSummary')
              AND ic.last_value IS NOT NULL;
        OPEN c;
        FETCH NEXT FROM c INTO @t;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @sql = N'DBCC CHECKIDENT (''dbo.' + @t + N''', RESEED, 0) WITH NO_INFOMSGS;';
            EXEC sp_executesql @sql;
            FETCH NEXT FROM c INTO @t;
        END
        CLOSE c; DEALLOCATE c;
    COMMIT;

    SELECT 'DELETED — item tables are empty' AS Result,
           (SELECT COUNT(*) FROM dbo.z_tb_Item) AS Items, (SELECT COUNT(*) FROM dbo.z_tb_ItemDet) AS ItemDets,
           (SELECT COUNT(*) FROM dbo.z_tb_StockLedger) AS LedgerRows, (SELECT COUNT(*) FROM dbo.z_tb_SalesInvoice) AS TillBills;
END
ELSE
    SELECT 'REPORT ONLY — nothing deleted. Set @Delete = 1 to delete.' AS Result;
GO

/* ---------------------------------------------------------------------------
   Part B — run on EACH till's db (zf_) AFTER Part A, with TillService stopped.
   Tills never hear about deletes, so their downloaded copies must be cleared; the next download fills them again.
   Bills already on the till are kept. Uncomment to use:

   SET NOCOUNT ON;
   DELETE FROM dbo.zf_tb_ItemPriceLink;
   DELETE FROM dbo.zf_tb_StockBalance;
   DELETE FROM dbo.zf_tb_Item;
   UPDATE dbo.zf_tb_Config SET LastItemSyncAt = NULL, LastPriceLinkSyncAt = NULL, LastStockSyncAt = NULL WHERE Id = 1;
   --------------------------------------------------------------------------- */
