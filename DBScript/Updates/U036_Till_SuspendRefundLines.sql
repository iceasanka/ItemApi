/* =============================================================================
   U036_Till_SuspendRefundLines.sql   (2026-11-02)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. No table changes; suspended bills, bills, Z reports and logs are not changed.

   What changes (a sale with refund items can be suspended):
     - zf_sp_SuspendBill takes the refund lines of a sale (U027 Refund on) as minus lines (Qty, Discount,
       Amount < 0), the same way zf_sp_SaveDraftBill keeps them. Recall already takes minus lines back as
       refund lines. A refund bill (InvType 2) still has plus lines only; a bill of refund lines only is a
       refund bill (InvType 2), not a sale.
   Same change in the full script: 02_FrontCashier_zf.sql.

   Order, on each till:
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U036_Till_SuspendRefundLines.sql
     2. install the new billing page and TillService (the old ones keep working after the script)
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_SuspendedBill', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_tb_SuspendedBillItem', 'U') IS NULL
   OR TYPE_ID(N'dbo.zf_tt_SuspendedItem') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_SuspendedBill / zf_tt_SuspendedItem not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

IF OBJECT_ID(N'dbo.zf_sp_SuspendBill', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_SuspendBill;
GO
CREATE PROCEDURE dbo.zf_sp_SuspendBill
    @InvType    INT = 1,
    @PriceType  INT = 1,
    @CashierId  VARCHAR(20) = NULL,
    @Discount   DECIMAL(18,2) = 0,
    @Label      NVARCHAR(50) = NULL,
    @Items      dbo.zf_tt_SuspendedItem READONLY,
    @SuspendId  INT = NULL OUTPUT,
    @DiscountPercent DECIMAL(5,2) = NULL
AS
BEGIN
    DECLARE @z_tc INT; SET @z_tc = @@TRANCOUNT;   -- SQL 2008 R2 error handling (RAISERROR in TRY/CATCH)
    BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @InvType NOT IN (1, 2)
        RAISERROR(N'%s', 16, 1, N'InvType must be 1 (sale) or 2 (refund).');
    IF @PriceType NOT IN (1, 2) OR EXISTS (SELECT 1 FROM @Items WHERE PriceType NOT IN (1, 2))
        RAISERROR(N'%s', 16, 1, N'PriceType must be 1 (retail) or 2 (wholesale).');
    IF NOT EXISTS (SELECT 1 FROM @Items)
        RAISERROR(N'%s', 16, 1, N'There is nothing to suspend: the bill has no items.');
    -- refund lines of a sale (U027 Refund on) are minus lines (Qty, Discount, Amount < 0), like the draft bill;
    -- a refund bill (InvType 2) keeps plus lines
    IF EXISTS (SELECT 1 FROM @Items WHERE Qty = 0 OR (Qty < 0 AND @InvType = 2))
        RAISERROR(N'%s', 16, 1, N'Item quantity must not be 0, and must be above 0 on a refund bill (InvType 2).');
    IF NOT EXISTS (SELECT 1 FROM @Items WHERE Qty > 0)
        RAISERROR(N'%s', 16, 1, N'A bill of only refund lines is suspended as a refund bill (InvType 2).');
    IF EXISTS (SELECT 1 FROM @Items WHERE Amount <> ROUND(Qty * UnitPrice, 2) - Discount)
        RAISERROR(N'%s', 16, 1, N'Line Amount must equal Qty * UnitPrice - Discount.');
    IF EXISTS (SELECT 1 FROM @Items WHERE ItemId = 0 AND (LTRIM(RTRIM(ISNULL(LineDescrip, N''))) = N'' OR UnitPrice <= 0))
        RAISERROR(N'%s', 16, 1, N'Other item needs a description and a price above 0.');

    BEGIN TRAN;
        INSERT dbo.zf_tb_SuspendedBill (Label, InvType, PriceType, CashierId, Discount, LineCount, NetAmount, SuspendedAt, Status, DiscountPercent)
        SELECT NULLIF(LTRIM(RTRIM(@Label)), N''), @InvType, @PriceType, @CashierId, @Discount,
               COUNT(*), SUM(Amount) - @Discount, GETDATE(), 1, @DiscountPercent
        FROM @Items;

        SET @SuspendId = SCOPE_IDENTITY();

        INSERT dbo.zf_tb_SuspendedBillItem (SuspendId, LineNum, ItemId, PriceLinkId, PriceType, Qty, UnitPrice, Discount, Amount, LineDescrip)
        SELECT @SuspendId, LineNum, ItemId, PriceLinkId, ISNULL(PriceType, @PriceType), Qty, UnitPrice, Discount, Amount,
               CASE WHEN ItemId = 0 THEN LTRIM(RTRIM(LineDescrip)) END
        FROM @Items;
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
            -- called inside the caller's transaction (suspend + close draft): give its level back, the caller rolls back
            WHILE @@TRANCOUNT > @z_tc AND XACT_STATE() = 1 COMMIT;
        END
        RAISERROR(N'%s', 16, 1, @z_msg);
        RETURN 1;
    END CATCH
END
GO

PRINT 'U036_Till_SuspendRefundLines done.';
GO
