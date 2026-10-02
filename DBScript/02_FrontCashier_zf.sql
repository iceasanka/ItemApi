/* =============================================================================
   02_FrontCashier_zf.sql
   Run on: each CASHIER TILL's local database (e.g. SQL Server Express / LocalDB, db name easyway_front)
   Prefix: zf_ (tables zf_tb_, types zf_tt_, procs zf_sp_)
   Safe to re-run: tables are created only if missing; types and procs are dropped and recreated.

   The till works fully offline:
     - bills from its local copy of items/prices (zf_tb_Item), downloaded from the back office
     - saves invoices locally (Synced = 0), numbered <TerminalCode>-<8 digit seq>, e.g. T01-00000123
     - uploads unsynced invoices whenever the back office is reachable (API: POST api/Sync/Invoices)
     - at day end closes the Z (zf_sp_CloseZ) and submits it (API: POST api/Sync/ZReport)
   The till NEVER changes stock itself and NEVER blocks a sale because of stock.
   See Docs/StockSystem.md for the full flow.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------------------------------------------------------------------------
   1. Tables
   --------------------------------------------------------------------------- */

-- One row (Id = 1). Filled once by zf_sp_SetupTerminal when the till is installed.
IF OBJECT_ID('dbo.zf_tb_Config', 'U') IS NULL
CREATE TABLE dbo.zf_tb_Config (
    Id               INT          NOT NULL CONSTRAINT PK_zf_tb_Config PRIMARY KEY CONSTRAINT CK_zf_tb_Config_One CHECK (Id = 1),
    TerminalId       INT          NOT NULL,   -- must match z_tb_Terminal.TerminalId on the back office
    TerminalCode     VARCHAR(10)  NOT NULL,   -- 'T01'
    LocationId       INT          NOT NULL,
    ApiBaseUrl       VARCHAR(200) NULL,       -- e.g. http://backoffice:5000/api/
    LastInvoiceSeq   INT          NOT NULL CONSTRAINT DF_zf_tb_Config_LastInvoiceSeq DEFAULT (0),
    LastItemSyncAt   DATETIME     NULL,       -- SERVER time of the last item download (next "since")
    LastStockSyncAt  DATETIME     NULL,       -- SERVER time of the last stock download
    CDate            DATETIME     NOT NULL CONSTRAINT DF_zf_tb_Config_CDate DEFAULT (GETDATE()),
    LastPriceLinkSyncAt DATETIME  NULL        -- SERVER time of the last price link download
);
GO

-- added after the first release — tills set up before it get the column here
IF COL_LENGTH('dbo.zf_tb_Config', 'LastPriceLinkSyncAt') IS NULL
    ALTER TABLE dbo.zf_tb_Config ADD LastPriceLinkSyncAt DATETIME NULL;
GO

-- Local copy of items + prices (download only — never edited on the till)
IF OBJECT_ID('dbo.zf_tb_Item', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.zf_tb_Item (
        ItemId          INT            NOT NULL CONSTRAINT PK_zf_tb_Item PRIMARY KEY,
        RefCode         NVARCHAR(50)   NULL,
        Barcode         NVARCHAR(50)   NULL,
        Descrip         NVARCHAR(200)  NULL,
        Inv_Descrip     NVARCHAR(50)   NULL,
        SinhalaDescrip  NVARCHAR(200)  NULL,
        OpenPrice       BIT            NOT NULL CONSTRAINT DF_zf_tb_Item_OpenPrice DEFAULT (0),
        MaxPrice        DECIMAL(18,2)  NULL,
        RetailPrice     DECIMAL(18,2)  NULL,
        WholesalePrice  DECIMAL(18,2)  NULL,
        SpecialPrice    DECIMAL(18,2)  NULL,
        IsSaleLocked    BIT            NOT NULL CONSTRAINT DF_zf_tb_Item_IsSaleLocked DEFAULT (0),
        NoDiscount      BIT            NOT NULL CONSTRAINT DF_zf_tb_Item_NoDiscount DEFAULT (0),
        DiscountAmount  DECIMAL(18,2)  NULL,
        DiscountPercent DECIMAL(18,2)  NULL,
        QtyLevel2       DECIMAL(18,3)  NULL,
        PriceLevel2     DECIMAL(18,2)  NULL,
        QtyLevel3       DECIMAL(18,3)  NULL,
        PriceLevel3     DECIMAL(18,2)  NULL,
        QtyLevel4       DECIMAL(18,3)  NULL,
        PriceLevel4     DECIMAL(18,2)  NULL,
        Status          INT            NOT NULL,
        UDate           DATETIME2      NULL   -- datetime2: back office items can carry 0001-01-01
    );
    CREATE INDEX IX_zf_tb_Item_Barcode ON dbo.zf_tb_Item (Barcode);
    CREATE INDEX IX_zf_tb_Item_RefCode ON dbo.zf_tb_Item (RefCode);
END
GO

-- Back-office stock balance copy — display only
IF OBJECT_ID('dbo.zf_tb_StockBalance', 'U') IS NULL
CREATE TABLE dbo.zf_tb_StockBalance (
    ItemId  INT           NOT NULL CONSTRAINT PK_zf_tb_StockBalance PRIMARY KEY,
    Qty     DECIMAL(18,3) NOT NULL,
    UDate   DATETIME      NULL
);
GO

-- Local copy of the item's extra prices (z_tb_ItemPriceLink, download only). Status 0 = deleted on the back office.
IF OBJECT_ID('dbo.zf_tb_ItemPriceLink', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.zf_tb_ItemPriceLink (
        PriceLinkId  INT            NOT NULL CONSTRAINT PK_zf_tb_ItemPriceLink PRIMARY KEY,
        ItemId       INT            NOT NULL,
        RetailPrice  DECIMAL(18,2)  NOT NULL,
        Remark       NVARCHAR(50)   NULL,
        Status       INT            NOT NULL,
        UDate        DATETIME       NULL
    );
    CREATE INDEX IX_zf_tb_ItemPriceLink_Item ON dbo.zf_tb_ItemPriceLink (ItemId, Status);
END
GO

IF OBJECT_ID('dbo.zf_tb_Invoice', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.zf_tb_Invoice (
        InvoiceNo    VARCHAR(30)   NOT NULL CONSTRAINT PK_zf_tb_Invoice PRIMARY KEY,   -- T01-00000123
        InvoiceSeq   INT           NOT NULL,
        ZNo          INT           NOT NULL,
        InvType      INT           NOT NULL,   -- 1 sale, 2 refund
        InvDate      DATETIME      NOT NULL,
        CashierId    VARCHAR(20)   NULL,
        GrossAmount  DECIMAL(18,2) NOT NULL,   -- SUM(Qty * UnitPrice)
        Discount     DECIMAL(18,2) NOT NULL,   -- bill-level discount
        NetAmount    DECIMAL(18,2) NOT NULL,   -- SUM(line Amount) - Discount
        Status       INT           NOT NULL,   -- 1 completed, 9 voided (only before upload)
        Synced       BIT           NOT NULL CONSTRAINT DF_zf_tb_Invoice_Synced DEFAULT (0),
        SyncedAt     DATETIME      NULL,
        CONSTRAINT UQ_zf_tb_Invoice_Seq UNIQUE (InvoiceSeq)
    );
    CREATE INDEX IX_zf_tb_Invoice_Unsynced ON dbo.zf_tb_Invoice (Synced, InvoiceSeq);
    CREATE INDEX IX_zf_tb_Invoice_Z        ON dbo.zf_tb_Invoice (ZNo);
END
GO

IF OBJECT_ID('dbo.zf_tb_InvoiceItem', 'U') IS NULL
CREATE TABLE dbo.zf_tb_InvoiceItem (
    InvoiceNo  VARCHAR(30)   NOT NULL,
    LineNum    INT           NOT NULL,
    ItemId     INT           NOT NULL,
    Qty        DECIMAL(18,3) NOT NULL,   -- positive; InvType gives direction
    UnitPrice  DECIMAL(18,2) NOT NULL,   -- price actually charged
    Discount   DECIMAL(18,2) NOT NULL,   -- line discount
    Amount     DECIMAL(18,2) NOT NULL,   -- Qty * UnitPrice - Discount
    CONSTRAINT PK_zf_tb_InvoiceItem PRIMARY KEY (InvoiceNo, LineNum)
);
GO

IF OBJECT_ID('dbo.zf_tb_InvoicePayment', 'U') IS NULL
CREATE TABLE dbo.zf_tb_InvoicePayment (
    InvoiceNo  VARCHAR(30)   NOT NULL,
    LineNum    INT           NOT NULL,
    PayType    INT           NOT NULL,   -- 1 cash, 2 card, 3 credit, 4 voucher
    Amount     DECIMAL(18,2) NOT NULL,   -- amount applied to the bill (cash tendered minus change)
    RefNo      VARCHAR(30)   NULL,
    CONSTRAINT PK_zf_tb_InvoicePayment PRIMARY KEY (InvoiceNo, LineNum)
);
GO

-- One Z per cashier shift/day. Status 0 open, 1 closed, 2 submitted, 3 reconciled, 4 mismatch
IF OBJECT_ID('dbo.zf_tb_ZReport', 'U') IS NULL
CREATE TABLE dbo.zf_tb_ZReport (
    ZNo           INT           NOT NULL CONSTRAINT PK_zf_tb_ZReport PRIMARY KEY,
    BusinessDate  DATE          NOT NULL,
    CashierId     VARCHAR(20)   NULL,
    OpenedAt      DATETIME      NOT NULL,
    ClosedAt      DATETIME      NULL,
    FromSeq       INT           NULL,
    ToSeq         INT           NULL,
    InvoiceCount  INT           NULL,
    LineCount     INT           NULL,
    TotalQty      DECIMAL(18,3) NULL,
    SalesAmount   DECIMAL(18,2) NULL,
    RefundAmount  DECIMAL(18,2) NULL,
    NetSales      DECIMAL(18,2) NULL,
    CashAmount    DECIMAL(18,2) NULL,
    CardAmount    DECIMAL(18,2) NULL,
    OtherAmount   DECIMAL(18,2) NULL,
    Status        INT           NOT NULL,
    ServerNote    VARCHAR(500)  NULL,   -- z_tb_ZReport.MismatchNote from the back office
    SubmittedAt   DATETIME      NULL
);
GO

IF OBJECT_ID('dbo.zf_tb_ZReportItem', 'U') IS NULL
CREATE TABLE dbo.zf_tb_ZReportItem (
    ZNo     INT           NOT NULL,
    ItemId  INT           NOT NULL,
    Qty     DECIMAL(18,3) NOT NULL,   -- sold - refunded
    Amount  DECIMAL(18,2) NOT NULL,
    CONSTRAINT PK_zf_tb_ZReportItem PRIMARY KEY (ZNo, ItemId)
);
GO

/* ---------------------------------------------------------------------------
   2. Drop procs, then types
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.zf_sp_SetupTerminal', 'P')        IS NOT NULL DROP PROCEDURE dbo.zf_sp_SetupTerminal;
IF OBJECT_ID('dbo.zf_sp_OpenZ', 'P')                IS NOT NULL DROP PROCEDURE dbo.zf_sp_OpenZ;
IF OBJECT_ID('dbo.zf_sp_SaveInvoice', 'P')          IS NOT NULL DROP PROCEDURE dbo.zf_sp_SaveInvoice;
IF OBJECT_ID('dbo.zf_sp_VoidInvoice', 'P')          IS NOT NULL DROP PROCEDURE dbo.zf_sp_VoidInvoice;
IF OBJECT_ID('dbo.zf_sp_FindItem', 'P')             IS NOT NULL DROP PROCEDURE dbo.zf_sp_FindItem;
IF OBJECT_ID('dbo.zf_sp_GetUnsyncedInvoices', 'P')  IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetUnsyncedInvoices;
IF OBJECT_ID('dbo.zf_sp_GetInvoicesByNo', 'P')      IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetInvoicesByNo;
IF OBJECT_ID('dbo.zf_sp_MarkInvoicesSynced', 'P')   IS NOT NULL DROP PROCEDURE dbo.zf_sp_MarkInvoicesSynced;
IF OBJECT_ID('dbo.zf_sp_CloseZ', 'P')               IS NOT NULL DROP PROCEDURE dbo.zf_sp_CloseZ;
IF OBJECT_ID('dbo.zf_sp_GetZForSubmit', 'P')        IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetZForSubmit;
IF OBJECT_ID('dbo.zf_sp_SetZStatus', 'P')           IS NOT NULL DROP PROCEDURE dbo.zf_sp_SetZStatus;
IF OBJECT_ID('dbo.zf_sp_UpsertItems', 'P')          IS NOT NULL DROP PROCEDURE dbo.zf_sp_UpsertItems;
IF OBJECT_ID('dbo.zf_sp_UpsertStockBalance', 'P')   IS NOT NULL DROP PROCEDURE dbo.zf_sp_UpsertStockBalance;
IF OBJECT_ID('dbo.zf_sp_UpsertPriceLinks', 'P')     IS NOT NULL DROP PROCEDURE dbo.zf_sp_UpsertPriceLinks;
GO
IF TYPE_ID('dbo.zf_tt_InvoiceItem')    IS NOT NULL DROP TYPE dbo.zf_tt_InvoiceItem;
IF TYPE_ID('dbo.zf_tt_InvoicePayment') IS NOT NULL DROP TYPE dbo.zf_tt_InvoicePayment;
IF TYPE_ID('dbo.zf_tt_InvoiceNo')      IS NOT NULL DROP TYPE dbo.zf_tt_InvoiceNo;
IF TYPE_ID('dbo.zf_tt_Item')           IS NOT NULL DROP TYPE dbo.zf_tt_Item;
IF TYPE_ID('dbo.zf_tt_StockBalance')   IS NOT NULL DROP TYPE dbo.zf_tt_StockBalance;
IF TYPE_ID('dbo.zf_tt_PriceLink')      IS NOT NULL DROP TYPE dbo.zf_tt_PriceLink;
GO

/* ---------------------------------------------------------------------------
   3. Table types
   --------------------------------------------------------------------------- */
CREATE TYPE dbo.zf_tt_InvoiceItem AS TABLE (
    LineNum    INT           NOT NULL PRIMARY KEY,
    ItemId     INT           NOT NULL,
    Qty        DECIMAL(18,3) NOT NULL,
    UnitPrice  DECIMAL(18,2) NOT NULL,
    Discount   DECIMAL(18,2) NOT NULL,
    Amount     DECIMAL(18,2) NOT NULL
);
GO
CREATE TYPE dbo.zf_tt_InvoicePayment AS TABLE (
    LineNum  INT           NOT NULL PRIMARY KEY,
    PayType  INT           NOT NULL,
    Amount   DECIMAL(18,2) NOT NULL,
    RefNo    VARCHAR(30)   NULL
);
GO
CREATE TYPE dbo.zf_tt_InvoiceNo AS TABLE (
    InvoiceNo VARCHAR(30) NOT NULL PRIMARY KEY
);
GO
-- same columns/order as the back-office z_sp_GetItemsForSync result (API: GET api/Sync/Items)
CREATE TYPE dbo.zf_tt_Item AS TABLE (
    ItemId          INT            NOT NULL PRIMARY KEY,
    RefCode         NVARCHAR(50)   NULL,
    Barcode         NVARCHAR(50)   NULL,
    Descrip         NVARCHAR(200)  NULL,
    Inv_Descrip     NVARCHAR(50)   NULL,
    SinhalaDescrip  NVARCHAR(200)  NULL,
    OpenPrice       BIT            NOT NULL,
    MaxPrice        DECIMAL(18,2)  NULL,
    RetailPrice     DECIMAL(18,2)  NULL,
    WholesalePrice  DECIMAL(18,2)  NULL,
    SpecialPrice    DECIMAL(18,2)  NULL,
    IsSaleLocked    BIT            NOT NULL,
    NoDiscount      BIT            NOT NULL,
    DiscountAmount  DECIMAL(18,2)  NULL,
    DiscountPercent DECIMAL(18,2)  NULL,
    QtyLevel2       DECIMAL(18,3)  NULL,
    PriceLevel2     DECIMAL(18,2)  NULL,
    QtyLevel3       DECIMAL(18,3)  NULL,
    PriceLevel3     DECIMAL(18,2)  NULL,
    QtyLevel4       DECIMAL(18,3)  NULL,
    PriceLevel4     DECIMAL(18,2)  NULL,
    Status          INT            NOT NULL,
    UDate           DATETIME2      NULL
);
GO
CREATE TYPE dbo.zf_tt_StockBalance AS TABLE (
    ItemId  INT           NOT NULL PRIMARY KEY,
    Qty     DECIMAL(18,3) NOT NULL,
    UDate   DATETIME      NULL
);
GO
-- same columns/order as the back-office z_sp_GetPriceLinksForSync result (API: GET api/Sync/PriceLinks)
CREATE TYPE dbo.zf_tt_PriceLink AS TABLE (
    PriceLinkId  INT            NOT NULL PRIMARY KEY,
    ItemId       INT            NOT NULL,
    RetailPrice  DECIMAL(18,2)  NOT NULL,
    Remark       NVARCHAR(50)   NULL,
    Status       INT            NOT NULL,
    UDate        DATETIME       NULL
);
GO

/* ---------------------------------------------------------------------------
   4. Procs
   --------------------------------------------------------------------------- */

-- One-time till setup. Register the same TerminalId/TerminalCode on the back office
-- (API: POST api/Sync/Terminal) before the first upload.
CREATE PROCEDURE dbo.zf_sp_SetupTerminal
    @TerminalId    INT,
    @TerminalCode  VARCHAR(10),
    @LocationId    INT,
    @ApiBaseUrl    VARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM dbo.zf_tb_Config)
        UPDATE dbo.zf_tb_Config
        SET TerminalId = @TerminalId, TerminalCode = @TerminalCode, LocationId = @LocationId, ApiBaseUrl = @ApiBaseUrl
        WHERE Id = 1;
    ELSE
        INSERT dbo.zf_tb_Config (Id, TerminalId, TerminalCode, LocationId, ApiBaseUrl)
        VALUES (1, @TerminalId, @TerminalCode, @LocationId, @ApiBaseUrl);
END
GO

-- Returns the open Z, opening a new one if there is none (called at cashier sign-on and by SaveInvoice).
CREATE PROCEDURE dbo.zf_sp_OpenZ
    @CashierId VARCHAR(20) = NULL,
    @ZNo       INT = NULL OUTPUT,
    @Silent    BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;
        SELECT @ZNo = ZNo FROM dbo.zf_tb_ZReport WITH (UPDLOCK, HOLDLOCK) WHERE Status = 0;

        IF @ZNo IS NULL
        BEGIN
            SELECT @ZNo = ISNULL(MAX(ZNo), 0) + 1 FROM dbo.zf_tb_ZReport WITH (UPDLOCK, HOLDLOCK);
            INSERT dbo.zf_tb_ZReport (ZNo, BusinessDate, CashierId, OpenedAt, Status)
            VALUES (@ZNo, CAST(GETDATE() AS DATE), @CashierId, GETDATE(), 0);
        END
    COMMIT;

    IF @Silent = 0
        SELECT ZNo, BusinessDate, CashierId, OpenedAt, Status FROM dbo.zf_tb_ZReport WHERE ZNo = @ZNo;
END
GO

-- Saves a completed bill. Allocates the next invoice number and puts it in the open Z.
-- Line Amount = Qty * UnitPrice - Discount; NetAmount = SUM(Amount) - bill Discount (checked).
-- Sales (InvType 1): each line's UnitPrice must be one the till offers for that item —
--   open price item: any price;
--   otherwise: the quantity price for that Qty (bulk levels, see below), or an active price link.
-- Refunds are not price-checked: they give back what was charged, which may be an older price.
CREATE PROCEDURE dbo.zf_sp_SaveInvoice
    @InvType      INT = 1,            -- 1 sale, 2 refund
    @CashierId    VARCHAR(20) = NULL,
    @Discount     DECIMAL(18,2) = 0,  -- bill-level discount
    @Items        dbo.zf_tt_InvoiceItem READONLY,
    @Payments     dbo.zf_tt_InvoicePayment READONLY,
    @InvoiceNo    VARCHAR(30) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Seq INT, @TerminalCode VARCHAR(10), @ZNo INT, @Gross DECIMAL(18,2), @Net DECIMAL(18,2);

    IF @InvType NOT IN (1, 2)
        THROW 51001, 'InvType must be 1 (sale) or 2 (refund).', 1;
    IF NOT EXISTS (SELECT 1 FROM @Items)
        THROW 51002, 'Bill has no items.', 1;
    IF EXISTS (SELECT 1 FROM @Items WHERE Qty <= 0)
        THROW 51003, 'Item quantity must be positive (use InvType 2 for refunds).', 1;
    IF EXISTS (SELECT 1 FROM @Items WHERE Amount <> ROUND(Qty * UnitPrice, 2) - Discount)
        THROW 51004, 'Line Amount must equal Qty * UnitPrice - Discount.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Config)
        THROW 51005, 'Till is not set up (run zf_sp_SetupTerminal).', 1;

    SELECT @Gross = SUM(ROUND(Qty * UnitPrice, 2)), @Net = SUM(Amount) - @Discount FROM @Items;

    IF ISNULL((SELECT SUM(Amount) FROM @Payments), 0) <> @Net
        THROW 51006, 'Payments must add up to the bill net amount.', 1;

    IF @InvType = 1
    BEGIN
        DECLARE @BadItem NVARCHAR(200), @Msg NVARCHAR(400);

        SELECT TOP 1 @BadItem = CAST(l.ItemId AS NVARCHAR(20))
        FROM @Items l WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Item i WHERE i.ItemId = l.ItemId);
        IF @BadItem IS NOT NULL
        BEGIN
            SET @Msg = N'Item ' + @BadItem + N' is not on this till. Scan it again.';
            THROW 51007, @Msg, 1;
        END

        -- Quantity price: the level with the highest MinQty that Qty reaches (MinQty and Price both > 0);
        -- none reached → RetailPrice. The billing page uses the SAME rule — change both together.
        SELECT TOP 1 @BadItem = ISNULL(i.Inv_Descrip, i.Descrip)
        FROM @Items l
        JOIN dbo.zf_tb_Item i ON i.ItemId = l.ItemId
        OUTER APPLY (
            SELECT TOP 1 v.Price
            FROM (VALUES (i.QtyLevel2, i.PriceLevel2), (i.QtyLevel3, i.PriceLevel3), (i.QtyLevel4, i.PriceLevel4)) v (MinQty, Price)
            WHERE v.MinQty > 0 AND v.Price > 0 AND l.Qty >= v.MinQty
            ORDER BY v.MinQty DESC
        ) q
        WHERE i.OpenPrice = 0
          AND l.UnitPrice <> ISNULL(q.Price, i.RetailPrice)
          AND NOT EXISTS (SELECT 1 FROM dbo.zf_tb_ItemPriceLink p
                          WHERE p.ItemId = l.ItemId AND p.Status = 1 AND p.RetailPrice = l.UnitPrice);
        IF @BadItem IS NOT NULL
        BEGIN
            SET @Msg = N'Price of ' + @BadItem + N' has changed. Remove the line and scan it again.';
            THROW 51008, @Msg, 1;
        END
    END

    BEGIN TRAN;
        EXEC dbo.zf_sp_OpenZ @CashierId = @CashierId, @ZNo = @ZNo OUTPUT, @Silent = 1;

        UPDATE dbo.zf_tb_Config
        SET @Seq = LastInvoiceSeq = LastInvoiceSeq + 1, @TerminalCode = TerminalCode
        WHERE Id = 1;

        SET @InvoiceNo = @TerminalCode + '-' + RIGHT('00000000' + CAST(@Seq AS VARCHAR(10)), 8);

        INSERT dbo.zf_tb_Invoice (InvoiceNo, InvoiceSeq, ZNo, InvType, InvDate, CashierId, GrossAmount, Discount, NetAmount, Status)
        VALUES (@InvoiceNo, @Seq, @ZNo, @InvType, GETDATE(), @CashierId, @Gross, @Discount, @Net, 1);

        INSERT dbo.zf_tb_InvoiceItem (InvoiceNo, LineNum, ItemId, Qty, UnitPrice, Discount, Amount)
        SELECT @InvoiceNo, LineNum, ItemId, Qty, UnitPrice, Discount, Amount FROM @Items;

        INSERT dbo.zf_tb_InvoicePayment (InvoiceNo, LineNum, PayType, Amount, RefNo)
        SELECT @InvoiceNo, LineNum, PayType, Amount, RefNo FROM @Payments;

        UPDATE dbo.zf_tb_ZReport SET FromSeq = ISNULL(FromSeq, @Seq), ToSeq = @Seq WHERE ZNo = @ZNo;
    COMMIT;
END
GO

-- Voids a bill that has NOT been uploaded yet and is in the open Z. After upload, do a refund instead.
CREATE PROCEDURE dbo.zf_sp_VoidInvoice
    @InvoiceNo VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE i SET Status = 9
    FROM dbo.zf_tb_Invoice i
    JOIN dbo.zf_tb_ZReport z ON z.ZNo = i.ZNo AND z.Status = 0
    WHERE i.InvoiceNo = @InvoiceNo AND i.Synced = 0 AND i.Status = 1;

    IF @@ROWCOUNT = 0
        THROW 51011, 'Only an unsent bill in the open Z can be voided. Use a refund.', 1;
END
GO

-- Barcode, then RefCode. 2 result sets: the item (with the last known stock, for display),
-- then its active price links (empty = sell at the normal / quantity price, no price choice).
CREATE PROCEDURE dbo.zf_sp_FindItem
    @Code NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ItemId INT;

    SELECT TOP 1 @ItemId = i.ItemId
    FROM dbo.zf_tb_Item i
    WHERE (i.Barcode = @Code OR i.RefCode = @Code) AND i.Status = 1
    ORDER BY CASE WHEN i.Barcode = @Code THEN 0 ELSE 1 END;

    SELECT i.*, s.Qty AS StockQty
    FROM dbo.zf_tb_Item i
    LEFT JOIN dbo.zf_tb_StockBalance s ON s.ItemId = i.ItemId
    WHERE i.ItemId = @ItemId;

    SELECT PriceLinkId, RetailPrice, Remark
    FROM dbo.zf_tb_ItemPriceLink
    WHERE ItemId = @ItemId AND Status = 1
    ORDER BY RetailPrice;
END
GO

-- Specific bills (used to resend the ones the back office reports missing for a Z).
CREATE PROCEDURE dbo.zf_sp_GetInvoicesByNo
    @InvoiceNos dbo.zf_tt_InvoiceNo READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SELECT i.InvoiceNo, i.InvoiceSeq, i.ZNo, i.InvType, i.InvDate, i.CashierId, i.GrossAmount, i.Discount, i.NetAmount, i.Status
    FROM dbo.zf_tb_Invoice i JOIN @InvoiceNos n ON n.InvoiceNo = i.InvoiceNo ORDER BY i.InvoiceSeq;

    SELECT it.InvoiceNo, it.LineNum, it.ItemId, it.Qty, it.UnitPrice, it.Discount, it.Amount
    FROM dbo.zf_tb_InvoiceItem it JOIN @InvoiceNos n ON n.InvoiceNo = it.InvoiceNo;

    SELECT p.InvoiceNo, p.LineNum, p.PayType, p.Amount, p.RefNo
    FROM dbo.zf_tb_InvoicePayment p JOIN @InvoiceNos n ON n.InvoiceNo = p.InvoiceNo;
END
GO

-- Oldest unsent bills, in 3 result sets (headers, items, payments) — the body of POST api/Sync/Invoices.
CREATE PROCEDURE dbo.zf_sp_GetUnsyncedInvoices
    @Top INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @n dbo.zf_tt_InvoiceNo;
    INSERT @n SELECT TOP (@Top) InvoiceNo FROM dbo.zf_tb_Invoice WHERE Synced = 0 ORDER BY InvoiceSeq;
    EXEC dbo.zf_sp_GetInvoicesByNo @InvoiceNos = @n;
END
GO

-- Call with every InvoiceNo the back office answered for ('Inserted' AND 'Duplicate').
CREATE PROCEDURE dbo.zf_sp_MarkInvoicesSynced
    @InvoiceNos dbo.zf_tt_InvoiceNo READONLY
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE i SET Synced = 1, SyncedAt = GETDATE()
    FROM dbo.zf_tb_Invoice i JOIN @InvoiceNos n ON n.InvoiceNo = i.InvoiceNo;
END
GO

-- Cashier day end: totals the open Z from the local bills and closes it. The next bill opens a new Z.
CREATE PROCEDURE dbo.zf_sp_CloseZ
    @CashierId VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ZNo INT;

    BEGIN TRAN;
        SELECT @ZNo = ZNo FROM dbo.zf_tb_ZReport WITH (UPDLOCK, HOLDLOCK) WHERE Status = 0;
        IF @ZNo IS NULL
            THROW 51021, 'There is no open Z to close.', 1;

        DELETE dbo.zf_tb_ZReportItem WHERE ZNo = @ZNo;
        INSERT dbo.zf_tb_ZReportItem (ZNo, ItemId, Qty, Amount)
        SELECT @ZNo, it.ItemId,
               SUM(CASE WHEN i.InvType = 2 THEN -it.Qty ELSE it.Qty END),
               SUM(CASE WHEN i.InvType = 2 THEN -it.Amount ELSE it.Amount END)
        FROM dbo.zf_tb_Invoice i
        JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = i.InvoiceNo
        WHERE i.ZNo = @ZNo AND i.Status <> 9
        GROUP BY it.ItemId;

        -- rules here must match z_sp_ReconcileZReport on the back office
        UPDATE z SET
            ClosedAt     = GETDATE(),
            CashierId    = ISNULL(@CashierId, z.CashierId),
            InvoiceCount = (SELECT COUNT(*) FROM dbo.zf_tb_Invoice WHERE ZNo = @ZNo),
            LineCount    = (SELECT COUNT(*) FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = i.InvoiceNo
                            WHERE i.ZNo = @ZNo AND i.Status <> 9),
            TotalQty     = ISNULL((SELECT SUM(Qty) FROM dbo.zf_tb_ZReportItem WHERE ZNo = @ZNo), 0),
            SalesAmount  = ISNULL((SELECT SUM(NetAmount) FROM dbo.zf_tb_Invoice WHERE ZNo = @ZNo AND Status <> 9 AND InvType = 1), 0),
            RefundAmount = ISNULL((SELECT SUM(NetAmount) FROM dbo.zf_tb_Invoice WHERE ZNo = @ZNo AND Status <> 9 AND InvType = 2), 0),
            CashAmount   = ISNULL((SELECT SUM(CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END)
                                   FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                                   WHERE i.ZNo = @ZNo AND i.Status <> 9 AND p.PayType = 1), 0),
            CardAmount   = ISNULL((SELECT SUM(CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END)
                                   FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                                   WHERE i.ZNo = @ZNo AND i.Status <> 9 AND p.PayType = 2), 0),
            OtherAmount  = ISNULL((SELECT SUM(CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END)
                                   FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                                   WHERE i.ZNo = @ZNo AND i.Status <> 9 AND p.PayType NOT IN (1, 2)), 0),
            Status       = 1
        FROM dbo.zf_tb_ZReport z
        WHERE z.ZNo = @ZNo;

        UPDATE dbo.zf_tb_ZReport SET NetSales = SalesAmount - RefundAmount WHERE ZNo = @ZNo;
    COMMIT;

    SELECT * FROM dbo.zf_tb_ZReport WHERE ZNo = @ZNo;
END
GO

-- Header + items of a closed Z = the body of POST api/Sync/ZReport.
-- @ZNo NULL = oldest closed Z not yet reconciled.
CREATE PROCEDURE dbo.zf_sp_GetZForSubmit
    @ZNo INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @ZNo IS NULL
        SELECT TOP 1 @ZNo = ZNo FROM dbo.zf_tb_ZReport WHERE Status IN (1, 2, 4) ORDER BY ZNo;

    SELECT c.TerminalId, z.ZNo, z.BusinessDate, z.CashierId, z.OpenedAt, z.ClosedAt, z.FromSeq, z.ToSeq,
           z.InvoiceCount, z.LineCount, z.TotalQty, z.SalesAmount, z.RefundAmount, z.NetSales,
           z.CashAmount, z.CardAmount, z.OtherAmount, z.Status
    FROM dbo.zf_tb_ZReport z CROSS JOIN dbo.zf_tb_Config c
    WHERE z.ZNo = @ZNo AND z.Status <> 0;

    SELECT ItemId, Qty, Amount FROM dbo.zf_tb_ZReportItem WHERE ZNo = @ZNo;
END
GO

-- Stores the back office answer: 3 reconciled, 4 mismatch (resend missing bills, then submit again).
CREATE PROCEDURE dbo.zf_sp_SetZStatus
    @ZNo    INT,
    @Status INT,
    @Note   VARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.zf_tb_ZReport SET Status = @Status, ServerNote = @Note, SubmittedAt = GETDATE()
    WHERE ZNo = @ZNo AND Status <> 0;
END
GO

-- Applies an item/price download. @ServerTime = serverTime from GET api/Sync/Items (next "since").
CREATE PROCEDURE dbo.zf_sp_UpsertItems
    @Items       dbo.zf_tt_Item READONLY,
    @ServerTime  DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRAN;
        UPDATE t SET
            RefCode = s.RefCode, Barcode = s.Barcode, Descrip = s.Descrip, Inv_Descrip = s.Inv_Descrip,
            SinhalaDescrip = s.SinhalaDescrip, OpenPrice = s.OpenPrice, MaxPrice = s.MaxPrice,
            RetailPrice = s.RetailPrice, WholesalePrice = s.WholesalePrice, SpecialPrice = s.SpecialPrice,
            IsSaleLocked = s.IsSaleLocked, NoDiscount = s.NoDiscount,
            DiscountAmount = s.DiscountAmount, DiscountPercent = s.DiscountPercent,
            QtyLevel2 = s.QtyLevel2, PriceLevel2 = s.PriceLevel2, QtyLevel3 = s.QtyLevel3, PriceLevel3 = s.PriceLevel3,
            QtyLevel4 = s.QtyLevel4, PriceLevel4 = s.PriceLevel4, Status = s.Status, UDate = s.UDate
        FROM dbo.zf_tb_Item t JOIN @Items s ON s.ItemId = t.ItemId;

        INSERT dbo.zf_tb_Item
        SELECT s.* FROM @Items s WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Item t WHERE t.ItemId = s.ItemId);

        UPDATE dbo.zf_tb_Config SET LastItemSyncAt = @ServerTime WHERE Id = 1;
    COMMIT;
END
GO

-- Applies a stock download. @ServerTime = serverTime from GET api/Sync/StockBalances.
CREATE PROCEDURE dbo.zf_sp_UpsertStockBalance
    @Rows        dbo.zf_tt_StockBalance READONLY,
    @ServerTime  DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRAN;
        UPDATE t SET Qty = s.Qty, UDate = s.UDate
        FROM dbo.zf_tb_StockBalance t JOIN @Rows s ON s.ItemId = t.ItemId;

        INSERT dbo.zf_tb_StockBalance (ItemId, Qty, UDate)
        SELECT s.ItemId, s.Qty, s.UDate FROM @Rows s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_StockBalance t WHERE t.ItemId = s.ItemId);

        UPDATE dbo.zf_tb_Config SET LastStockSyncAt = @ServerTime WHERE Id = 1;
    COMMIT;
END
GO

-- Applies a price link download. @ServerTime = serverTime from GET api/Sync/PriceLinks.
-- Deleted links arrive with Status 0 and stay as Status 0 (zf_sp_FindItem ignores them).
CREATE PROCEDURE dbo.zf_sp_UpsertPriceLinks
    @Rows        dbo.zf_tt_PriceLink READONLY,
    @ServerTime  DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRAN;
        UPDATE t SET ItemId = s.ItemId, RetailPrice = s.RetailPrice, Remark = s.Remark, Status = s.Status, UDate = s.UDate
        FROM dbo.zf_tb_ItemPriceLink t JOIN @Rows s ON s.PriceLinkId = t.PriceLinkId;

        INSERT dbo.zf_tb_ItemPriceLink (PriceLinkId, ItemId, RetailPrice, Remark, Status, UDate)
        SELECT s.PriceLinkId, s.ItemId, s.RetailPrice, s.Remark, s.Status, s.UDate FROM @Rows s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_ItemPriceLink t WHERE t.PriceLinkId = s.PriceLinkId);

        UPDATE dbo.zf_tb_Config SET LastPriceLinkSyncAt = @ServerTime WHERE Id = 1;
    COMMIT;
END
GO
