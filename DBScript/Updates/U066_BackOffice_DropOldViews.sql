/* =============================================================================
   U066_BackOffice_DropOldViews.sql   (2026-11-17)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again (a second run finds nothing to drop).

   Old-system clean-up, step 3 of 7 (the shop runs fully on the new system; the old data is in a backup):
     - drops EVERY view whose name does not start with z_ / zf_ (vw_Sales, Vw_Stock, VwPosTransact ... - 51 on the
       local db). The new system has no views and none of its procs / functions / app code reads an old view.
       A view another (schema bound) view still needs is tried again in the next pass; one that can never be
       dropped is listed at the end and the rest are still dropped.
   Before: a full backup of the db.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U066_BackOffice_DropOldViews.sql
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

DECLARE @Name SYSNAME, @Schema SYSNAME, @Sql NVARCHAR(MAX), @Dropped INT, @Pass INT, @Progress INT, @Left INT;
SET @Dropped = 0;
SET @Pass = 0;
SET @Progress = 1;

WHILE @Progress = 1 AND @Pass < 20
BEGIN
    SET @Pass = @Pass + 1;
    SET @Progress = 0;
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT v.name, s.name
        FROM sys.views v JOIN sys.schemas s ON s.schema_id = v.schema_id
        WHERE v.is_ms_shipped = 0 AND v.name NOT LIKE 'z[_]%' AND v.name NOT LIKE 'zf[_]%'
        ORDER BY v.name;
    OPEN c;
    FETCH NEXT FROM c INTO @Name, @Schema;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N'DROP VIEW ' + QUOTENAME(@Schema) + N'.' + QUOTENAME(@Name) + N';';
        BEGIN TRY
            EXEC (@Sql);
            SET @Dropped = @Dropped + 1;
            SET @Progress = 1;
            PRINT 'Dropped view ' + @Schema + '.' + @Name;
        END TRY
        BEGIN CATCH
            -- still needed by another view: the next pass tries again
        END CATCH
        FETCH NEXT FROM c INTO @Name, @Schema;
    END
    CLOSE c;
    DEALLOCATE c;
END

SELECT @Left = COUNT(*) FROM sys.views
WHERE is_ms_shipped = 0 AND name NOT LIKE 'z[_]%' AND name NOT LIKE 'zf[_]%';

PRINT 'U066: ' + CAST(@Dropped AS VARCHAR(10)) + ' old view(s) dropped, ' + CAST(@Left AS VARCHAR(10)) + ' could not be dropped.';
IF @Left > 0
    SELECT name AS NotDropped FROM sys.views
    WHERE is_ms_shipped = 0 AND name NOT LIKE 'z[_]%' AND name NOT LIKE 'zf[_]%';
GO
SET NOEXEC OFF;
GO
