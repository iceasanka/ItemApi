/* =============================================================================
   U069_BackOffice_DropOldTables.sql   (2026-11-17)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again (a second run finds nothing to drop).

   Old-system clean-up, step 6 of 7 (the shop runs fully on the new system; the old data is in a backup):
     - drops EVERY remaining old-system table - name not starting z_ / zf_ - WITH its data (177 on the local db,
       about 3.7 GB): old sales / POS / payments (tbPostransact*, tbPospayment*, tb_InvSumm / tb_InvDet,
       tb_Payment ...), old stock / purchasing (tb_Stock, tb_Pur*, tb_StAdj*, tb_MastLog, tb_PriceChange ...),
       old items / suppliers / customers / setup (tb_Item, tb_ItemDet, tb_ItemDet_Rpl, tb_Supplier, tb_Customer,
       tb_Users ...) and the rest (tb_Temp*, tbx_* report tables, App*Sales of the old phone app,
       __MigrationHistory ...). The new system reads none of them (no proc, function or app code).
     - foreign keys between old tables are dropped first. A table a new z_ / zf_ table has a foreign key to is
       skipped and listed (none on the local db).
   THE DATA IS GONE AFTER THIS - take a full backup first and keep it.
   After U065 - U068 and the new ItemApi of 2026-11-17 (old routes removed).

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U069_BackOffice_DropOldTables.sql
   Then: shrink the db file to give the space back (step 7).
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

DECLARE @Id INT, @Name SYSNAME, @Schema SYSNAME, @Sql NVARCHAR(MAX),
        @FkName SYSNAME, @FkSchema SYSNAME, @FkTable SYSNAME, @Dropped INT, @Skipped INT;
SET @Dropped = 0;
SET @Skipped = 0;
CREATE TABLE #Skipped (TableName SYSNAME, Reason NVARCHAR(200));

-- 1. foreign keys from old tables (to anything) and to old tables from old tables
DECLARE f CURSOR LOCAL STATIC FOR
    SELECT fk.name, SCHEMA_NAME(pt.schema_id), pt.name
    FROM sys.foreign_keys fk
    JOIN sys.tables pt ON pt.object_id = fk.parent_object_id
    WHERE pt.is_ms_shipped = 0 AND pt.name NOT LIKE 'z[_]%' AND pt.name NOT LIKE 'zf[_]%';
OPEN f;
FETCH NEXT FROM f INTO @FkName, @FkSchema, @FkTable;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql = N'ALTER TABLE ' + QUOTENAME(@FkSchema) + N'.' + QUOTENAME(@FkTable) + N' DROP CONSTRAINT ' + QUOTENAME(@FkName) + N';';
    EXEC (@Sql);
    FETCH NEXT FROM f INTO @FkName, @FkSchema, @FkTable;
END
CLOSE f;
DEALLOCATE f;

-- 2. the old tables
DECLARE c CURSOR LOCAL STATIC FOR
    SELECT t.object_id, t.name, s.name
    FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE t.is_ms_shipped = 0 AND t.name NOT LIKE 'z[_]%' AND t.name NOT LIKE 'zf[_]%'
    ORDER BY t.name;
OPEN c;
FETCH NEXT FROM c INTO @Id, @Name, @Schema;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM sys.foreign_keys fk WHERE fk.referenced_object_id = @Id)
    BEGIN
        INSERT #Skipped VALUES (@Name, N'a new z_ / zf_ table has a foreign key to it');
        SET @Skipped = @Skipped + 1;
    END
    ELSE
    BEGIN
        BEGIN TRY
            SET @Sql = N'DROP TABLE ' + QUOTENAME(@Schema) + N'.' + QUOTENAME(@Name) + N';';
            EXEC (@Sql);
            SET @Dropped = @Dropped + 1;
            PRINT 'Dropped table ' + @Schema + '.' + @Name;
        END TRY
        BEGIN CATCH
            INSERT #Skipped VALUES (@Name, LEFT(ERROR_MESSAGE(), 200));
            SET @Skipped = @Skipped + 1;
        END CATCH
    END
    FETCH NEXT FROM c INTO @Id, @Name, @Schema;
END
CLOSE c;
DEALLOCATE c;

PRINT 'U069: ' + CAST(@Dropped AS VARCHAR(10)) + ' old table(s) dropped, ' + CAST(@Skipped AS VARCHAR(10)) + ' skipped.';
IF @Skipped > 0 SELECT * FROM #Skipped;
DROP TABLE #Skipped;
GO
SET NOEXEC OFF;
GO
