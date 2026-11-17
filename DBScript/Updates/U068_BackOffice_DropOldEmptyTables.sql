/* =============================================================================
   U068_BackOffice_DropOldEmptyTables.sql   (2026-11-17)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again (a second run finds nothing to drop).

   Old-system clean-up, step 5 of 7 (the shop runs fully on the new system; the old data is in a backup):
     - drops every old-system table (name not starting z_ / zf_) that is EMPTY - checked with SELECT on the table
       itself right before it is dropped (171 on the local db). Old tables with rows are left for step 6.
     - a foreign key from another old table to it is dropped first (no new z_ / zf_ table points to an old one;
       if one ever did, that table is skipped and listed).
   Before: a full backup of the db. After U065 / U066 / U067 (no old trigger / view / proc left to need them).

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U068_BackOffice_DropOldEmptyTables.sql
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

DECLARE @Id INT, @Name SYSNAME, @Schema SYSNAME, @Full NVARCHAR(600), @Sql NVARCHAR(MAX), @HasRows BIT,
        @FkName SYSNAME, @FkSchema SYSNAME, @FkTable SYSNAME, @Dropped INT, @Skipped INT;
SET @Dropped = 0;
SET @Skipped = 0;
CREATE TABLE #Skipped (TableName SYSNAME, Reason VARCHAR(100));

DECLARE c CURSOR LOCAL STATIC FOR
    SELECT t.object_id, t.name, s.name
    FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE t.is_ms_shipped = 0 AND t.name NOT LIKE 'z[_]%' AND t.name NOT LIKE 'zf[_]%'
    ORDER BY t.name;
OPEN c;
FETCH NEXT FROM c INTO @Id, @Name, @Schema;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Full = QUOTENAME(@Schema) + N'.' + QUOTENAME(@Name);
    SET @Sql = N'SELECT @r = CASE WHEN EXISTS (SELECT 1 FROM ' + @Full + N') THEN 1 ELSE 0 END;';
    EXEC sp_executesql @Sql, N'@r BIT OUTPUT', @r = @HasRows OUTPUT;

    IF @HasRows = 0
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.foreign_keys fk
                   WHERE fk.referenced_object_id = @Id
                     AND (OBJECT_NAME(fk.parent_object_id) LIKE 'z[_]%' OR OBJECT_NAME(fk.parent_object_id) LIKE 'zf[_]%'))
        BEGIN
            INSERT #Skipped VALUES (@Name, 'a new z_ / zf_ table has a foreign key to it');
            SET @Skipped = @Skipped + 1;
        END
        ELSE
        BEGIN
            -- foreign keys from other old tables to this one
            DECLARE f CURSOR LOCAL STATIC FOR
                SELECT fk.name, SCHEMA_NAME(pt.schema_id), pt.name
                FROM sys.foreign_keys fk JOIN sys.tables pt ON pt.object_id = fk.parent_object_id
                WHERE fk.referenced_object_id = @Id AND fk.parent_object_id <> @Id;
            OPEN f;
            FETCH NEXT FROM f INTO @FkName, @FkSchema, @FkTable;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @Sql = N'ALTER TABLE ' + QUOTENAME(@FkSchema) + N'.' + QUOTENAME(@FkTable)
                         + N' DROP CONSTRAINT ' + QUOTENAME(@FkName) + N';';
                EXEC (@Sql);
                FETCH NEXT FROM f INTO @FkName, @FkSchema, @FkTable;
            END
            CLOSE f;
            DEALLOCATE f;

            BEGIN TRY
                SET @Sql = N'DROP TABLE ' + @Full + N';';
                EXEC (@Sql);
                SET @Dropped = @Dropped + 1;
                PRINT 'Dropped empty table ' + @Schema + '.' + @Name;
            END TRY
            BEGIN CATCH
                INSERT #Skipped VALUES (@Name, LEFT(ERROR_MESSAGE(), 100));
                SET @Skipped = @Skipped + 1;
            END CATCH
        END
    END
    FETCH NEXT FROM c INTO @Id, @Name, @Schema;
END
CLOSE c;
DEALLOCATE c;

PRINT 'U068: ' + CAST(@Dropped AS VARCHAR(10)) + ' empty old table(s) dropped, ' + CAST(@Skipped AS VARCHAR(10)) + ' skipped.';
IF @Skipped > 0 SELECT * FROM #Skipped;
DROP TABLE #Skipped;
GO
SET NOEXEC OFF;
GO
