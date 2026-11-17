/* =============================================================================
   U067_BackOffice_DropOldProcs.sql   (2026-11-17)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again (a second run finds nothing to drop).

   Old-system clean-up, step 4 of 7 (the shop runs fully on the new system; the old data is in a backup):
     - drops EVERY stored procedure and user function whose name does not start with z_ / zf_ (495 procs and 3
       functions on the local db: Fc_UPDATE_MOVEMENT, CapitalizeWords, fn_diagramobjects). No new proc, function or
       app code calls them.
     - drops the finished one-time transfer procs z_sp_TransferOldItems, z_sp_TransferOldItemDiscounts and
       z_sp_TransferOldPriceLinks (U005 / U012 / 08_Transfer_OldItems.sql): they read the old tb_Item / tb_ItemDet /
       tb_PriceLink, which go in a later step. z_sp_TransferPayeesToSuppliers stays (new tables only).
     An object another object still needs (schema bound) is tried again in the next pass; one that can never be
     dropped is listed at the end and the rest are still dropped.
   Before: a full backup of the db.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U067_BackOffice_DropOldProcs.sql
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_Setting', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Item', 'U') IS NULL
BEGIN
    RAISERROR('This is not a back office database of the new system (z_tb_Setting / z_tb_Item not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

DECLARE @Name SYSNAME, @Schema SYSNAME, @Type CHAR(2), @Sql NVARCHAR(MAX),
        @Procs INT, @Funcs INT, @Pass INT, @Progress INT, @Left INT;
SET @Procs = 0;
SET @Funcs = 0;
SET @Pass = 0;
SET @Progress = 1;

WHILE @Progress = 1 AND @Pass < 20
BEGIN
    SET @Pass = @Pass + 1;
    SET @Progress = 0;
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT o.name, s.name, o.type
        FROM sys.objects o JOIN sys.schemas s ON s.schema_id = o.schema_id
        WHERE o.is_ms_shipped = 0 AND o.type IN ('P', 'FN', 'IF', 'TF')
          AND (   (o.name NOT LIKE 'z[_]%' AND o.name NOT LIKE 'zf[_]%')
               OR o.name IN ('z_sp_TransferOldItems', 'z_sp_TransferOldItemDiscounts', 'z_sp_TransferOldPriceLinks'))
        ORDER BY o.type, o.name;
    OPEN c;
    FETCH NEXT FROM c INTO @Name, @Schema, @Type;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = CASE WHEN @Type = 'P' THEN N'DROP PROCEDURE ' ELSE N'DROP FUNCTION ' END
                 + QUOTENAME(@Schema) + N'.' + QUOTENAME(@Name) + N';';
        BEGIN TRY
            EXEC (@Sql);
            IF @Type = 'P' SET @Procs = @Procs + 1; ELSE SET @Funcs = @Funcs + 1;
            SET @Progress = 1;
        END TRY
        BEGIN CATCH
            -- still needed by another object: the next pass tries again
        END CATCH
        FETCH NEXT FROM c INTO @Name, @Schema, @Type;
    END
    CLOSE c;
    DEALLOCATE c;
END

SELECT @Left = COUNT(*) FROM sys.objects
WHERE is_ms_shipped = 0 AND type IN ('P', 'FN', 'IF', 'TF')
  AND (   (name NOT LIKE 'z[_]%' AND name NOT LIKE 'zf[_]%')
       OR name IN ('z_sp_TransferOldItems', 'z_sp_TransferOldItemDiscounts', 'z_sp_TransferOldPriceLinks'));

PRINT 'U067: ' + CAST(@Procs AS VARCHAR(10)) + ' old proc(s) and ' + CAST(@Funcs AS VARCHAR(10))
    + ' old function(s) dropped, ' + CAST(@Left AS VARCHAR(10)) + ' could not be dropped.';
IF @Left > 0
    SELECT name AS NotDropped, type_desc FROM sys.objects
    WHERE is_ms_shipped = 0 AND type IN ('P', 'FN', 'IF', 'TF')
      AND (   (name NOT LIKE 'z[_]%' AND name NOT LIKE 'zf[_]%')
           OR name IN ('z_sp_TransferOldItems', 'z_sp_TransferOldItemDiscounts', 'z_sp_TransferOldPriceLinks'));
GO
SET NOEXEC OFF;
GO
