/* =============================================================================
   U011_Till_SearchByCode.sql   (2026-10-21)
   Update for a till db (z_pos_fnt_db) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Tables, items, bills, Z reports and cash data are not touched.

   What changes (find items by item code in the F1 Search dialog and the scan box):
     - zf_sp_SearchItems gets @Codes BIT = 0. With @Codes = 1 a RefCode or Barcode containing the text matches
       too. Order: exact RefCode, exact Barcode, RefCode starting with the text, Barcode starting with it, name
       starting with it, the rest. Never ItemId. @Codes = 0 (the old TillService) works exactly as before.
   Scan box rule: 1. exact Barcode, 2. exact RefCode (zf_sp_FindItem, unchanged), 3. this search with @Codes = 1.
   F1 Search dialog: this search with @Codes = 1.
   Same change in the full script: 02_FrontCashier_zf.sql.

   No back office script. On each till (the running TillService keeps working after it):
     1. sqlcmd -S .\SQLEXPRESS -d z_pos_fnt_db -E -I -b -i U011_Till_SearchByCode.sql
     2. install the new TillService (GET /items/search?codes=true needs this procedure)
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zf_tb_Item', 'U') IS NULL OR OBJECT_ID(N'dbo.zf_tb_ItemPriceLink', 'U') IS NULL
   OR OBJECT_ID(N'dbo.zf_tb_StockBalance', 'U') IS NULL
BEGIN
    RAISERROR('This is not a till database (zf_tb_Item / zf_tb_ItemPriceLink / zf_tb_StockBalance not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.zf_sp_SearchItems', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_SearchItems;
GO
-- Cashier search by name: every word typed must appear in Descrip or Inv_Descrip (any order, any case),
-- e.g. 'sugar 1kg' finds 'SUGAR WHITE 1KG'. Active items only, names starting with the text first.
-- @Codes = 1 (F1 Search dialog, and the scan box after zf_sp_FindItem found no exact barcode / RefCode): RefCode or
-- Barcode containing the text match too. Order: exact RefCode, exact Barcode, RefCode starting with the text,
-- Barcode starting with it, name starting with it, the rest ('1003' -> 10030, 10034 ...). Never ItemId.
-- Pick a row, then zf_sp_FindItem @ItemId for the full item and its price links.
-- Works on SQL Server 2008 R2 (tills still on 2008): the words are split with a loop, not STRING_SPLIT.
CREATE PROCEDURE dbo.zf_sp_SearchItems
    @Text  NVARCHAR(100),
    @Top   INT = 50,
    @Codes BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- LIKE wildcards typed by the cashier are searched for literally (escaping makes @t up to 3x longer)
    DECLARE @t NVARCHAR(300) = LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(@Text, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]')));
    DECLARE @words TABLE (Word NVARCHAR(300) NOT NULL);

    -- split @t on spaces; several spaces in a row = one
    DECLARE @rest NVARCHAR(300) = @t, @p INT, @w NVARCHAR(300);
    WHILE @rest <> N''
    BEGIN
        SET @rest = LTRIM(@rest);
        SET @p = CHARINDEX(N' ', @rest);
        IF @p = 0 SET @p = LEN(@rest) + 1;
        SET @w = LEFT(@rest, @p - 1);
        IF @w <> N'' INSERT @words (Word) VALUES (@w);
        SET @rest = SUBSTRING(@rest, @p + 1, 300);
    END

    IF NOT EXISTS (SELECT 1 FROM @words)
        SET @Top = 0;   -- nothing typed -> no rows (same columns, so callers always get one shape)

    SELECT TOP (@Top)
           i.ItemId, i.RefCode, i.Barcode, i.Descrip, i.Inv_Descrip,
           ISNULL(i.RetailPrice, 0) AS RetailPrice, i.WholesalePrice, i.OpenPrice, i.IsSaleLocked, s.Qty AS StockQty,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM dbo.zf_tb_ItemPriceLink p WHERE p.ItemId = i.ItemId AND p.Status = 1)
                     THEN 1 ELSE 0 END AS BIT) AS HasPriceLinks
    FROM dbo.zf_tb_Item i
    LEFT JOIN dbo.zf_tb_StockBalance s ON s.ItemId = i.ItemId
    WHERE i.Status = 1
      AND (   NOT EXISTS (SELECT 1 FROM @words w
                          WHERE ISNULL(i.Descrip, N'') NOT LIKE N'%' + w.Word + N'%'
                            AND ISNULL(i.Inv_Descrip, N'') NOT LIKE N'%' + w.Word + N'%')
           OR (@Codes = 1 AND (i.RefCode LIKE N'%' + @t + N'%' OR i.Barcode LIKE N'%' + @t + N'%')))
    ORDER BY CASE WHEN @Codes = 1 AND i.RefCode = LTRIM(RTRIM(@Text)) THEN 0
                  WHEN @Codes = 1 AND i.Barcode = LTRIM(RTRIM(@Text)) THEN 1
                  WHEN @Codes = 1 AND i.RefCode LIKE @t + N'%' THEN 2
                  WHEN @Codes = 1 AND i.Barcode LIKE @t + N'%' THEN 3
                  WHEN i.Descrip LIKE @t + N'%' OR i.Inv_Descrip LIKE @t + N'%' THEN 4 ELSE 5 END, i.Descrip;
END
GO
SET NOEXEC OFF;
GO
PRINT 'U011_Till_SearchByCode done.';
GO
