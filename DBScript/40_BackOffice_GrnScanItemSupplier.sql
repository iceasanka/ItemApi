/* =============================================================================
   40_BackOffice_GrnScanItemSupplier.sql   (2026-11-16)
   Full script for a back office db (easyway). SQL Server 2008 R2 and newer. Safe to run again.

   What changes (GRN Scan: the item's supplier set from the GRN):
     - new proc z_sp_GrnScanSetItemSupplier @SuppId, @Ids (z_tt_IdList), @Replace
         Make GRN draft with "Set this supplier on the items" ticked: z_tb_Item.SupId = the GRN's supplier for the
         items of the GRN that have no supplier (@Replace 1: also those set to another supplier). UDate = now (as an
         item edit). Returns Filled (had none), Replaced (had another), Other (another supplier, left as it is).
   No table change. Needs U029 (GRN Scan) and the type z_tt_IdList (U016, return list).
   Same as the update: Updates/U062_BackOffice_GrnScanItemSupplier.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i 40_BackOffice_GrnScanItemSupplier.sql
   Then: the new ItemApi and the back office UI. The new ItemApi without it makes the GRN draft and says the item
         suppliers were not set.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO
IF OBJECT_ID(N'dbo.z_tb_Item', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Supplier', 'U') IS NULL OR TYPE_ID(N'dbo.z_tt_IdList') IS NULL
BEGIN
    RAISERROR('z_tb_Item / z_tb_Supplier / z_tt_IdList missing - run the earlier scripts first.', 16, 1);
    SET NOEXEC ON;
END
GO

IF OBJECT_ID(N'dbo.z_sp_GrnScanSetItemSupplier', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_GrnScanSetItemSupplier;
GO

-- GRN Scan, Make GRN draft with "Set this supplier on the items": the items of the GRN get its supplier.
-- An item with no supplier gets it; one with another supplier only when @Replace = 1 (else counted in Other).
-- UDate = now, as an item edit. Returns Filled, Replaced, Other.
CREATE PROCEDURE dbo.z_sp_GrnScanSetItemSupplier
    @SuppId  INT,
    @Ids     dbo.z_tt_IdList READONLY,
    @Replace BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Supplier WHERE SuppId = @SuppId)
    BEGIN
        RAISERROR(N'%s', 16, 1, N'Supplier not found.');
        RETURN;
    END

    DECLARE @Filled INT, @Replaced INT, @Other INT;
    SELECT @Filled   = SUM(CASE WHEN ISNULL(i.SupId, 0) = 0 THEN 1 ELSE 0 END),
           @Replaced = SUM(CASE WHEN ISNULL(i.SupId, 0) NOT IN (0, @SuppId) AND @Replace = 1 THEN 1 ELSE 0 END),
           @Other    = SUM(CASE WHEN ISNULL(i.SupId, 0) NOT IN (0, @SuppId) AND @Replace = 0 THEN 1 ELSE 0 END)
    FROM dbo.z_tb_Item i JOIN @Ids x ON x.Id = i.ItemId;

    UPDATE i SET SupId = @SuppId, UDate = SYSDATETIME()
    FROM dbo.z_tb_Item i JOIN @Ids x ON x.Id = i.ItemId
    WHERE ISNULL(i.SupId, 0) = 0 OR (@Replace = 1 AND i.SupId <> @SuppId);

    SELECT ISNULL(@Filled, 0) AS Filled, ISNULL(@Replaced, 0) AS Replaced, ISNULL(@Other, 0) AS Other;
END
GO

SET NOEXEC OFF;
GO
PRINT '40 done: z_sp_GrnScanSetItemSupplier.';
GO
