/* =============================================================================
   41_BackOffice_OrderLists.sql   (2026-11-17)
   Full script for a back office db (easyway). SQL Server 2008 R2 and newer. Safe to run again.

   What changes (Tools > Order Lists):
     Order lists (Kind 1): the items we order from another shop (Nandana, Serina, Naginda at first - names can be
     changed). Printed (thermal or A4) with a blank qty column to write the order qty by hand.
     Code lists (Kind 2): item names with their ref codes, printed on A4 in two columns - Scale (on the wall by the
     scale) and Cashier (by the till) at first.
     The lists are kept until changed; no history, nothing is ordered through the system.
     - new tables  z_tb_OrderList      (a list: kind, name, order on the page, Sinhala names on / off)
                   z_tb_OrderListLine  (a line: one of our items - under its own name or a name typed for the list
                                        - or a text for something not in our items; a note)
     - new procs   z_sp_OrderListGet          every list with its lines (one row per line; a list with none: one row)
                   z_sp_OrderListSave         new list / rename
                   z_sp_OrderListDelete       a list and its lines
                   z_sp_OrderListAddLine      an item (once a list) or a text, at the end
                   z_sp_OrderListUpdateLine   the name on the list and the note
                   z_sp_OrderListRemoveLine
                   z_sp_OrderListMoveLine     one up / down
                   z_sp_OrderListSortByName   the whole list A-Z, or by ref code
                   z_sp_OrderListSetSinhala   a list prints the Sinhala names (else the English one)
     - the lists Nandana, Serina, Naginda (order) and Scale, Cashier (code) when there is no list yet; a db where
       the first U063 was run gets the column Kind and the two code lists
   Needs z_tb_Item. Same as the update: Updates/U063_BackOffice_OrderLists.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i 41_BackOffice_OrderLists.sql
   Then: the new ItemApi (api/OrderList) and the back office UI (Tools > Order Lists).
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
IF OBJECT_ID(N'dbo.z_tb_Item', 'U') IS NULL
BEGIN
    RAISERROR('z_tb_Item missing - run the earlier scripts first.', 16, 1);
    SET NOEXEC ON;
END
GO

-- --- tables ---

IF OBJECT_ID(N'dbo.z_tb_OrderList', 'U') IS NULL
CREATE TABLE dbo.z_tb_OrderList (
    ListId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_OrderList PRIMARY KEY,
    Kind      TINYINT       NOT NULL CONSTRAINT DF_z_tb_OrderList_Kind DEFAULT (1),   -- 1 order list, 2 code list
    Sinhala   BIT           NOT NULL CONSTRAINT DF_z_tb_OrderList_Sinhala DEFAULT (0), -- 1 = print the items' Sinhala names
    Name      NVARCHAR(50)  NOT NULL,
    SortNo    INT           NOT NULL CONSTRAINT DF_z_tb_OrderList_SortNo DEFAULT (0),
    CreatedAt DATETIME      NOT NULL CONSTRAINT DF_z_tb_OrderList_CreatedAt DEFAULT (GETDATE()),
    UpdatedAt DATETIME      NULL
);
GO
IF OBJECT_ID(N'dbo.z_tb_OrderListLine', 'U') IS NULL
CREATE TABLE dbo.z_tb_OrderListLine (
    LineId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_OrderListLine PRIMARY KEY,
    ListId    INT           NOT NULL CONSTRAINT FK_z_tb_OrderListLine_List REFERENCES dbo.z_tb_OrderList (ListId),
    ItemId    INT           NULL,           -- one of our items (z_tb_Item), or NULL = a text line
    LineText  NVARCHAR(100) NULL,           -- the text of a text line; on an item line the name typed for the list
                                            -- (NULL = the item's own name)
    Note      NVARCHAR(50)  NULL,           -- printed after the name (pack, brand ...)
    SortNo    INT           NOT NULL CONSTRAINT DF_z_tb_OrderListLine_SortNo DEFAULT (0),
    CreatedAt DATETIME      NOT NULL CONSTRAINT DF_z_tb_OrderListLine_CreatedAt DEFAULT (GETDATE())
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_z_tb_OrderListLine_List' AND object_id = OBJECT_ID(N'dbo.z_tb_OrderListLine'))
    CREATE INDEX IX_z_tb_OrderListLine_List ON dbo.z_tb_OrderListLine (ListId, SortNo);
GO

-- a db where the first U063 (order lists only) was run: Kind added, and the two code lists made then (once)
IF COL_LENGTH(N'dbo.z_tb_OrderList', N'Kind') IS NULL
BEGIN
    ALTER TABLE dbo.z_tb_OrderList ADD Kind TINYINT NOT NULL CONSTRAINT DF_z_tb_OrderList_Kind DEFAULT (1);
    EXEC (N'INSERT dbo.z_tb_OrderList (Kind, Name, SortNo) VALUES (2, N''Scale'', 1), (2, N''Cashier'', 2);');
END
GO
IF COL_LENGTH(N'dbo.z_tb_OrderList', N'Sinhala') IS NULL
    ALTER TABLE dbo.z_tb_OrderList ADD Sinhala BIT NOT NULL CONSTRAINT DF_z_tb_OrderList_Sinhala DEFAULT (0);
GO

-- the lists at first (only on a db with no list yet; renamed / deleted ones are not made again):
-- order lists Nandana, Serina, Naginda; code lists Scale (on the wall by the scale), Cashier (by the till)
IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_OrderList)
    INSERT dbo.z_tb_OrderList (Kind, Name, SortNo)
    VALUES (1, N'Nandana', 1), (1, N'Serina', 2), (1, N'Naginda', 3), (2, N'Scale', 1), (2, N'Cashier', 2);
GO

-- --- procs ---

IF OBJECT_ID(N'dbo.z_sp_OrderListGet', 'P')        IS NOT NULL DROP PROCEDURE dbo.z_sp_OrderListGet;
IF OBJECT_ID(N'dbo.z_sp_OrderListSave', 'P')       IS NOT NULL DROP PROCEDURE dbo.z_sp_OrderListSave;
IF OBJECT_ID(N'dbo.z_sp_OrderListDelete', 'P')     IS NOT NULL DROP PROCEDURE dbo.z_sp_OrderListDelete;
IF OBJECT_ID(N'dbo.z_sp_OrderListAddLine', 'P')    IS NOT NULL DROP PROCEDURE dbo.z_sp_OrderListAddLine;
IF OBJECT_ID(N'dbo.z_sp_OrderListUpdateLine', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_OrderListUpdateLine;
IF OBJECT_ID(N'dbo.z_sp_OrderListRemoveLine', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_OrderListRemoveLine;
IF OBJECT_ID(N'dbo.z_sp_OrderListMoveLine', 'P')   IS NOT NULL DROP PROCEDURE dbo.z_sp_OrderListMoveLine;
IF OBJECT_ID(N'dbo.z_sp_OrderListSortByName', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_OrderListSortByName;
IF OBJECT_ID(N'dbo.z_sp_OrderListSetSinhala', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_OrderListSetSinhala;
GO

-- Every list with its lines, in page order. LineId NULL = a list with no line yet. Descrip = the name printed: the
-- name typed for the list, else the item's name now (a text line: its text); ItemDescrip = the item's own name;
-- ItemSinhala = its Sinhala name (printed instead when the list's Sinhala is on and no name was typed).
-- ItemStatus 0 = the item was deactivated (still printed).
CREATE PROCEDURE dbo.z_sp_OrderListGet
AS
BEGIN
    SET NOCOUNT ON;
    SELECT l.ListId, l.Kind, l.Sinhala, l.Name AS ListName, l.SortNo AS ListSortNo,
           x.LineId, x.ItemId, COALESCE(x.LineText, i.Descrip, N'') AS Descrip, i.Descrip AS ItemDescrip,
           NULLIF(LTRIM(RTRIM(i.SinhalaDescrip)), N'') AS ItemSinhala,
           i.RefCode, i.Barcode, i.Status AS ItemStatus,
           x.Note, x.SortNo
    FROM dbo.z_tb_OrderList l
    LEFT JOIN dbo.z_tb_OrderListLine x ON x.ListId = l.ListId
    LEFT JOIN dbo.z_tb_Item i ON i.ItemId = x.ItemId
    ORDER BY l.Kind, l.SortNo, l.ListId, x.SortNo, x.LineId;
END
GO

-- @ListId NULL / 0 = a new list of @Kind (1 order list, 2 code list; at the end); else rename it. Returns ListId.
CREATE PROCEDURE dbo.z_sp_OrderListSave
    @ListId INT = NULL,
    @Name   NVARCHAR(50),
    @Kind   TINYINT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET @Name = LTRIM(RTRIM(@Name));
    IF ISNULL(@Name, N'') = N''
    BEGIN
        RAISERROR(N'%s', 16, 1, N'Type the list name.');
        RETURN;
    END
    IF ISNULL(@ListId, 0) > 0
        SELECT @Kind = Kind FROM dbo.z_tb_OrderList WHERE ListId = @ListId;
    IF @Kind NOT IN (1, 2) SET @Kind = 1;
    IF EXISTS (SELECT 1 FROM dbo.z_tb_OrderList WHERE Kind = @Kind AND Name = @Name AND ListId <> ISNULL(@ListId, 0))
    BEGIN
        RAISERROR(N'%s', 16, 1, N'There is already a list with this name.');
        RETURN;
    END
    IF ISNULL(@ListId, 0) = 0
    BEGIN
        INSERT dbo.z_tb_OrderList (Kind, Name, SortNo)
        SELECT @Kind, @Name, ISNULL(MAX(SortNo), 0) + 1 FROM dbo.z_tb_OrderList WHERE Kind = @Kind;
        SELECT CAST(SCOPE_IDENTITY() AS INT) AS ListId;
        RETURN;
    END
    UPDATE dbo.z_tb_OrderList SET Name = @Name, UpdatedAt = GETDATE() WHERE ListId = @ListId;
    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR(N'%s', 16, 1, N'The list is not there any more.');
        RETURN;
    END
    SELECT @ListId AS ListId;
END
GO

CREATE PROCEDURE dbo.z_sp_OrderListDelete
    @ListId INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRAN;
    DELETE dbo.z_tb_OrderListLine WHERE ListId = @ListId;
    DELETE dbo.z_tb_OrderList WHERE ListId = @ListId;
    COMMIT;
END
GO

-- One of our items (@ItemId; once a list) or a text (@Text, for something not in our items), at the end of the list.
-- Returns LineId.
CREATE PROCEDURE dbo.z_sp_OrderListAddLine
    @ListId INT,
    @ItemId INT = NULL,
    @Text   NVARCHAR(100) = NULL,
    @Note   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Text = NULLIF(LTRIM(RTRIM(@Text)), N'');
    SET @Note = NULLIF(LTRIM(RTRIM(@Note)), N'');
    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_OrderList WHERE ListId = @ListId)
    BEGIN
        RAISERROR(N'%s', 16, 1, N'The list is not there any more.');
        RETURN;
    END
    IF ISNULL(@ItemId, 0) > 0
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Item WHERE ItemId = @ItemId)
        BEGIN
            RAISERROR(N'%s', 16, 1, N'Item not found.');
            RETURN;
        END
        IF EXISTS (SELECT 1 FROM dbo.z_tb_OrderListLine WHERE ListId = @ListId AND ItemId = @ItemId)
        BEGIN
            RAISERROR(N'%s', 16, 1, N'The item is already on this list.');
            RETURN;
        END
        SET @Text = NULL;
    END
    ELSE
    BEGIN
        SET @ItemId = NULL;
        IF @Text IS NULL
        BEGIN
            RAISERROR(N'%s', 16, 1, N'Pick an item or type a name.');
            RETURN;
        END
    END
    INSERT dbo.z_tb_OrderListLine (ListId, ItemId, LineText, Note, SortNo)
    SELECT @ListId, @ItemId, @Text, @Note, ISNULL(MAX(SortNo), 0) + 1 FROM dbo.z_tb_OrderListLine WHERE ListId = @ListId;
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS LineId;
END
GO

-- The name on the list and the note (both sent every time). An item line: @Text = the name printed for it; empty or
-- the item's own name = the item's name (follows a rename of the item). A text line: empty keeps its text.
CREATE PROCEDURE dbo.z_sp_OrderListUpdateLine
    @LineId INT,
    @Text   NVARCHAR(100) = NULL,
    @Note   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Text = NULLIF(LTRIM(RTRIM(@Text)), N'');
    UPDATE x
    SET Note = NULLIF(LTRIM(RTRIM(@Note)), N''),
        LineText = CASE WHEN x.ItemId IS NULL THEN ISNULL(@Text, x.LineText)
                        WHEN @Text = i.Descrip THEN NULL
                        ELSE @Text END
    FROM dbo.z_tb_OrderListLine x
    LEFT JOIN dbo.z_tb_Item i ON i.ItemId = x.ItemId
    WHERE x.LineId = @LineId;
END
GO

CREATE PROCEDURE dbo.z_sp_OrderListRemoveLine
    @LineId INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE dbo.z_tb_OrderListLine WHERE LineId = @LineId;
END
GO

-- swaps the line with the one above (@Up 1) / below (@Up 0) on its list
CREATE PROCEDURE dbo.z_sp_OrderListMoveLine
    @LineId INT,
    @Up     BIT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ListId INT, @Sort INT, @OtherId INT, @OtherSort INT;
    SELECT @ListId = ListId, @Sort = SortNo FROM dbo.z_tb_OrderListLine WHERE LineId = @LineId;
    IF @ListId IS NULL RETURN;
    -- equal sort numbers (lines added at once) are made distinct first
    IF EXISTS (SELECT 1 FROM dbo.z_tb_OrderListLine WHERE ListId = @ListId GROUP BY SortNo HAVING COUNT(*) > 1)
    BEGIN
        UPDATE x SET SortNo = r.n
        FROM dbo.z_tb_OrderListLine x
        JOIN (SELECT LineId, ROW_NUMBER() OVER (ORDER BY SortNo, LineId) AS n FROM dbo.z_tb_OrderListLine WHERE ListId = @ListId) r
          ON r.LineId = x.LineId;
        SELECT @Sort = SortNo FROM dbo.z_tb_OrderListLine WHERE LineId = @LineId;
    END
    IF @Up = 1
        SELECT TOP 1 @OtherId = LineId, @OtherSort = SortNo FROM dbo.z_tb_OrderListLine
        WHERE ListId = @ListId AND SortNo < @Sort ORDER BY SortNo DESC;
    ELSE
        SELECT TOP 1 @OtherId = LineId, @OtherSort = SortNo FROM dbo.z_tb_OrderListLine
        WHERE ListId = @ListId AND SortNo > @Sort ORDER BY SortNo;
    IF @OtherId IS NULL RETURN;   -- already first / last
    BEGIN TRAN;
    UPDATE dbo.z_tb_OrderListLine SET SortNo = @OtherSort WHERE LineId = @LineId;
    UPDATE dbo.z_tb_OrderListLine SET SortNo = @Sort WHERE LineId = @OtherId;
    COMMIT;
END
GO

-- the whole list in name order (A-Z)
-- @ByCode 1 = by ref code instead (shorter codes first, so 999 before 1000; lines with no code at the end)
CREATE PROCEDURE dbo.z_sp_OrderListSortByName
    @ListId INT,
    @ByCode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE x SET SortNo = r.n
    FROM dbo.z_tb_OrderListLine x
    JOIN (SELECT l.LineId, ROW_NUMBER() OVER (ORDER BY
                 CASE WHEN @ByCode = 1 AND ISNULL(i.RefCode, N'') = N'' THEN 1 ELSE 0 END,
                 CASE WHEN @ByCode = 1 THEN LEN(i.RefCode) END,
                 CASE WHEN @ByCode = 1 THEN i.RefCode END,
                 COALESCE(l.LineText, i.Descrip, N''), l.LineId) AS n
          FROM dbo.z_tb_OrderListLine l LEFT JOIN dbo.z_tb_Item i ON i.ItemId = l.ItemId
          WHERE l.ListId = @ListId) r ON r.LineId = x.LineId;
END
GO

-- a list prints the items' Sinhala names (an item with none: its English name; a name typed for the list wins)
CREATE PROCEDURE dbo.z_sp_OrderListSetSinhala
    @ListId  INT,
    @Sinhala BIT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.z_tb_OrderList SET Sinhala = ISNULL(@Sinhala, 0), UpdatedAt = GETDATE() WHERE ListId = @ListId;
END
GO

SET NOEXEC OFF;
GO
PRINT '41 done: z_tb_OrderList, z_tb_OrderListLine, z_sp_OrderList* (Tools > Order Lists).';
GO
