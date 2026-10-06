/* =============================================================================
   03_BackOffice_PriceLink.sql
   Run on: back office db (easyway), after 01_BackOffice_Stock.sql
   Prefix: z_ (tables z_tb_, procs z_sp_)
   Safe to re-run: the table is created only if missing; procs are dropped and recreated.

   Price links = extra retail prices for the SAME item at one location, e.g. old stock still
   marked 250.00 while new stock is 275.00. The item keeps its normal price (z_tb_ItemDet.RetailPrice);
   each link adds one more price the cashier can pick when the item is scanned.
     - added / deleted from Item Entry (API: api/Itemz/PriceLinks, AddPriceLink, PriceLink/{id})
     - delete = Status 0 (never a hard delete), so tills hear about it on the next download
     - tills download changes (API: GET api/Sync/PriceLinks) and show a "Select price" list
   This replaces the old-system tb_PriceLink for the new item tables (z_tb_Item). tb_PriceLink is untouched.
   See Docs/StockSystem.md.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.z_tb_ItemPriceLink', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.z_tb_ItemPriceLink (
        PriceLinkId     INT            IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_ItemPriceLink PRIMARY KEY,
        ItemId          INT            NOT NULL,   -- z_tb_Item.ItemId
        LocationId      INT            NOT NULL,
        RetailPrice     DECIMAL(18,2)  NOT NULL,   -- the price the cashier charges
        WholesalePrice  DECIMAL(18,2)  NULL,
        CostPrice       DECIMAL(18,2)  NULL,
        Remark          NVARCHAR(50)   NULL,       -- e.g. 'Old stock MRP'
        Status          INT            NOT NULL CONSTRAINT DF_z_tb_ItemPriceLink_Status DEFAULT (1),   -- 1 active, 0 deleted
        UserId          INT            NULL,
        CDate           DATETIME       NOT NULL CONSTRAINT DF_z_tb_ItemPriceLink_CDate DEFAULT (GETDATE()),
        UDate           DATETIME       NOT NULL CONSTRAINT DF_z_tb_ItemPriceLink_UDate DEFAULT (GETDATE())   -- tills sync on this
    );
    CREATE INDEX IX_z_tb_ItemPriceLink_Item ON dbo.z_tb_ItemPriceLink (ItemId, LocationId, Status);
    CREATE INDEX IX_z_tb_ItemPriceLink_UDate ON dbo.z_tb_ItemPriceLink (LocationId, UDate);
    -- one active link per price — the same price twice would show twice on the till
    CREATE UNIQUE INDEX UX_z_tb_ItemPriceLink_Active ON dbo.z_tb_ItemPriceLink (ItemId, LocationId, RetailPrice) WHERE Status = 1;
END
GO

IF OBJECT_ID('dbo.z_sp_AddPriceLink', 'P')         IS NOT NULL DROP PROCEDURE dbo.z_sp_AddPriceLink;
IF OBJECT_ID('dbo.z_sp_DeletePriceLink', 'P')      IS NOT NULL DROP PROCEDURE dbo.z_sp_DeletePriceLink;
IF OBJECT_ID('dbo.z_sp_GetPriceLinksForSync', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_GetPriceLinksForSync;
GO

-- Adds a price link and returns the new row.
CREATE PROCEDURE dbo.z_sp_AddPriceLink
    @ItemId          INT,
    @LocationId      INT,
    @RetailPrice     DECIMAL(18,2),
    @WholesalePrice  DECIMAL(18,2) = NULL,
    @CostPrice       DECIMAL(18,2) = NULL,
    @Remark          NVARCHAR(50)  = NULL,
    @UserId          INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @MainPrice DECIMAL(18,2), @Id INT;

    IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Item WHERE ItemId = @ItemId)
        THROW 50041, 'Item not found.', 1;
    IF @RetailPrice IS NULL OR @RetailPrice <= 0
        THROW 50042, 'Price must be more than 0.', 1;

    SELECT @MainPrice = RetailPrice FROM dbo.z_tb_ItemDet WHERE ItemId = @ItemId AND LocationId = @LocationId;
    IF @RetailPrice = @MainPrice
        THROW 50043, 'This is already the item''s normal retail price.', 1;

    BEGIN TRAN;
        IF EXISTS (SELECT 1 FROM dbo.z_tb_ItemPriceLink WITH (UPDLOCK, HOLDLOCK)
                   WHERE ItemId = @ItemId AND LocationId = @LocationId AND RetailPrice = @RetailPrice AND Status = 1)
            THROW 50044, 'This item already has a price link with this price.', 1;

        INSERT dbo.z_tb_ItemPriceLink (ItemId, LocationId, RetailPrice, WholesalePrice, CostPrice, Remark, UserId)
        VALUES (@ItemId, @LocationId, @RetailPrice, @WholesalePrice, @CostPrice, NULLIF(LTRIM(RTRIM(@Remark)), N''), @UserId);
        SET @Id = SCOPE_IDENTITY();
    COMMIT;

    SELECT PriceLinkId, ItemId, LocationId, RetailPrice, WholesalePrice, CostPrice, Remark, Status, UserId, CDate, UDate
    FROM dbo.z_tb_ItemPriceLink WHERE PriceLinkId = @Id;
END
GO

-- Deletes (Status 0) an active price link. UDate moves so tills remove it on their next download.
CREATE PROCEDURE dbo.z_sp_DeletePriceLink
    @PriceLinkId  INT,
    @UserId       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.z_tb_ItemPriceLink
    SET Status = 0, UDate = GETDATE(), UserId = ISNULL(@UserId, UserId)
    WHERE PriceLinkId = @PriceLinkId AND Status = 1;

    IF @@ROWCOUNT = 0
        THROW 50045, 'Price link not found or already deleted.', 1;
END
GO

-- "Changed since" download for one till. Deleted links are included (Status 0) so the till drops them;
-- a full download (@Since NULL) only needs the active ones.
CREATE PROCEDURE dbo.z_sp_GetPriceLinksForSync
    @TerminalId INT,
    @Since      DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LocationId INT;
    SELECT @LocationId = LocationId FROM dbo.z_tb_Terminal WHERE TerminalId = @TerminalId AND Status = 1;
    IF @LocationId IS NULL
        THROW 50021, 'Terminal is not registered or is disabled.', 1;

    SELECT PriceLinkId, ItemId, RetailPrice, WholesalePrice, Remark, Status, UDate,   -- WholesalePrice: used on wholesale bills
           CostPrice                                                                  -- till profit view (NULL → item cost)
    FROM dbo.z_tb_ItemPriceLink
    WHERE LocationId = @LocationId
      AND (@Since IS NULL AND Status = 1 OR UDate > @Since);
END
GO
