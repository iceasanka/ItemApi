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
        PriceLinkId     INT            NOT NULL CONSTRAINT PK_zf_tb_ItemPriceLink PRIMARY KEY,
        ItemId          INT            NOT NULL,
        RetailPrice     DECIMAL(18,2)  NOT NULL,
        Remark          NVARCHAR(50)   NULL,
        Status          INT            NOT NULL,
        UDate           DATETIME       NULL,
        WholesalePrice  DECIMAL(18,2)  NULL      -- used on wholesale bills; NULL → RetailPrice
    );
    CREATE INDEX IX_zf_tb_ItemPriceLink_Item ON dbo.zf_tb_ItemPriceLink (ItemId, Status);
END
GO

-- added with wholesale bills. Links already on the till have no wholesale price yet → download them all again.
IF COL_LENGTH('dbo.zf_tb_ItemPriceLink', 'WholesalePrice') IS NULL
BEGIN
    ALTER TABLE dbo.zf_tb_ItemPriceLink ADD WholesalePrice DECIMAL(18,2) NULL;
    UPDATE dbo.zf_tb_Config SET LastPriceLinkSyncAt = NULL;
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
        PriceType    INT           NOT NULL CONSTRAINT DF_zf_tb_Invoice_PriceType DEFAULT (1),   -- 1 retail, 2 = has wholesale line(s); each line has its own
        CONSTRAINT UQ_zf_tb_Invoice_Seq UNIQUE (InvoiceSeq)
    );
    CREATE INDEX IX_zf_tb_Invoice_Unsynced ON dbo.zf_tb_Invoice (Synced, InvoiceSeq);
    CREATE INDEX IX_zf_tb_Invoice_Z        ON dbo.zf_tb_Invoice (ZNo);
END
GO

IF COL_LENGTH('dbo.zf_tb_Invoice', 'PriceType') IS NULL
    ALTER TABLE dbo.zf_tb_Invoice ADD PriceType INT NOT NULL CONSTRAINT DF_zf_tb_Invoice_PriceType DEFAULT (1);
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
    LineDescrip NVARCHAR(50) NULL,       -- "other item" (ItemId 0, not in the item list): what the cashier typed
    PriceType  INT           NOT NULL CONSTRAINT DF_zf_tb_InvoiceItem_PriceType DEFAULT (1),   -- 1 retail, 2 wholesale price on this line
    CONSTRAINT PK_zf_tb_InvoiceItem PRIMARY KEY (InvoiceNo, LineNum)
);
GO

-- added with "other item" lines — tills set up before get the column here
IF COL_LENGTH('dbo.zf_tb_InvoiceItem', 'LineDescrip') IS NULL
    ALTER TABLE dbo.zf_tb_InvoiceItem ADD LineDescrip NVARCHAR(50) NULL;
GO

-- added with per-line wholesale (a retail bill can have wholesale lines and the other way round)
IF COL_LENGTH('dbo.zf_tb_InvoiceItem', 'PriceType') IS NULL
    ALTER TABLE dbo.zf_tb_InvoiceItem ADD PriceType INT NOT NULL CONSTRAINT DF_zf_tb_InvoiceItem_PriceType DEFAULT (1);
GO

IF OBJECT_ID('dbo.zf_tb_InvoicePayment', 'U') IS NULL
CREATE TABLE dbo.zf_tb_InvoicePayment (
    InvoiceNo  VARCHAR(30)   NOT NULL,
    LineNum    INT           NOT NULL,
    PayType    INT           NOT NULL,   -- 1 cash, 2 card, 3 credit, 4 voucher, 5 bank transfer, 6 cheque
    Amount     DECIMAL(18,2) NOT NULL,   -- amount applied to the bill (cash tendered minus change)
    RefNo      VARCHAR(30)   NULL,
    CONSTRAINT PK_zf_tb_InvoicePayment PRIMARY KEY (InvoiceNo, LineNum)
);
GO

-- Suspended (parked) bills: a bill the cashier puts aside before payment and recalls later — any time,
-- also after a restart or a day end. Not an invoice: no number, no Z, never uploaded, no stock.
-- Status 1 suspended, 2 recalled (back on the billing screen), 9 cancelled. Rows are kept for audit.
IF OBJECT_ID('dbo.zf_tb_SuspendedBill', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.zf_tb_SuspendedBill (
        SuspendId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_zf_tb_SuspendedBill PRIMARY KEY,   -- shown as #12
        Label        NVARCHAR(50)  NULL,       -- what the cashier typed, e.g. customer name
        InvType      INT           NOT NULL,   -- 1 sale, 2 refund
        PriceType    INT           NOT NULL,   -- the page's default mode for new lines (1 retail, 2 wholesale)
        CashierId    VARCHAR(20)   NULL,
        Discount     DECIMAL(18,2) NOT NULL,   -- bill-level discount
        LineCount    INT           NOT NULL,
        NetAmount    DECIMAL(18,2) NOT NULL,   -- SUM(line Amount) - Discount, at the prices when suspended
        SuspendedAt  DATETIME      NOT NULL,
        Status       INT           NOT NULL,
        ClosedAt     DATETIME      NULL,       -- recalled / cancelled at
        ClosedBy     VARCHAR(20)   NULL
    );
    CREATE INDEX IX_zf_tb_SuspendedBill_Status ON dbo.zf_tb_SuspendedBill (Status, SuspendId);
END
GO

IF OBJECT_ID('dbo.zf_tb_SuspendedBillItem', 'U') IS NULL
CREATE TABLE dbo.zf_tb_SuspendedBillItem (
    SuspendId   INT           NOT NULL,
    LineNum     INT           NOT NULL,
    ItemId      INT           NOT NULL,   -- 0 = other item
    PriceLinkId INT           NULL,       -- the price link the cashier picked, NULL = normal / quantity price
    PriceType   INT           NOT NULL,   -- 1 retail, 2 wholesale
    Qty         DECIMAL(18,3) NOT NULL,
    UnitPrice   DECIMAL(18,2) NOT NULL,   -- price when suspended (the page re-prices real items on recall)
    Discount    DECIMAL(18,2) NOT NULL,
    Amount      DECIMAL(18,2) NOT NULL,
    LineDescrip NVARCHAR(50)  NULL,       -- other item only
    CONSTRAINT PK_zf_tb_SuspendedBillItem PRIMARY KEY (SuspendId, LineNum)
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

-- Added with printed receipts, profit view, bill discount % and the cash drawer (2026-10-06).
-- Cost prices: items and price links already on the till have none yet → download them all again.
IF COL_LENGTH('dbo.zf_tb_Item', 'CostPrice') IS NULL
BEGIN
    ALTER TABLE dbo.zf_tb_Item ADD CostPrice DECIMAL(18,2) NULL;   -- z_tb_ItemDet.CostPrice; never shown without the supervisor PIN
    UPDATE dbo.zf_tb_Config SET LastItemSyncAt = NULL;
END
GO
IF COL_LENGTH('dbo.zf_tb_ItemPriceLink', 'CostPrice') IS NULL
BEGIN
    ALTER TABLE dbo.zf_tb_ItemPriceLink ADD CostPrice DECIMAL(18,2) NULL;   -- NULL → the item's CostPrice
    UPDATE dbo.zf_tb_Config SET LastPriceLinkSyncAt = NULL;
END
GO
IF COL_LENGTH('dbo.zf_tb_Invoice', 'DiscountPercent') IS NULL
    ALTER TABLE dbo.zf_tb_Invoice ADD DiscountPercent DECIMAL(5,2) NULL;   -- bill discount given as %, for the receipt
GO
-- added with scale sticker barcodes. Items already on the till have no unit yet → download them all again.
IF COL_LENGTH('dbo.zf_tb_Item', 'UnitCode') IS NULL
BEGIN
    ALTER TABLE dbo.zf_tb_Item ADD UnitCode VARCHAR(5) NULL;               -- z_tb_Unit.UnitCode; KGS = scale item
    UPDATE dbo.zf_tb_Config SET LastItemSyncAt = NULL;
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_zf_tb_Invoice_Date' AND object_id = OBJECT_ID('dbo.zf_tb_Invoice'))
    CREATE INDEX IX_zf_tb_Invoice_Date ON dbo.zf_tb_Invoice (InvDate);   -- reprint: bills of a day
GO
IF COL_LENGTH('dbo.zf_tb_InvoiceItem', 'PriceLinkId') IS NULL
    ALTER TABLE dbo.zf_tb_InvoiceItem ADD PriceLinkId INT NULL;            -- the price link the cashier picked
GO
IF COL_LENGTH('dbo.zf_tb_InvoiceItem', 'UnitCost') IS NULL
    ALTER TABLE dbo.zf_tb_InvoiceItem ADD UnitCost DECIMAL(18,2) NULL;     -- cost when sold (zf_fn_BillLineCost), NULL = unknown
GO
IF COL_LENGTH('dbo.zf_tb_InvoiceItem', 'MktPrice') IS NULL
    ALTER TABLE dbo.zf_tb_InvoiceItem ADD MktPrice DECIMAL(18,2) NULL;     -- item MaxPrice (MRP) when sold, printed as MktPrice
GO
IF COL_LENGTH('dbo.zf_tb_InvoicePayment', 'Tendered') IS NULL
    ALTER TABLE dbo.zf_tb_InvoicePayment ADD Tendered DECIMAL(18,2) NULL;  -- cash handed over (Amount + change), for the receipt
GO
IF COL_LENGTH('dbo.zf_tb_SuspendedBill', 'DiscountPercent') IS NULL
    ALTER TABLE dbo.zf_tb_SuspendedBill ADD DiscountPercent DECIMAL(5,2) NULL;
GO

-- Every time the cash drawer is opened: Kind 1 = after a bill paid (partly) in cash, 2 = No Sale (supervisor PIN),
-- 3 = opening cash, 4 = paid in, 5 = paid out (zf_tb_CashMovement).
IF OBJECT_ID('dbo.zf_tb_DrawerLog', 'U') IS NULL
CREATE TABLE dbo.zf_tb_DrawerLog (
    DrawerLogId  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_zf_tb_DrawerLog PRIMARY KEY,
    OpenedAt     DATETIME      NOT NULL CONSTRAINT DF_zf_tb_DrawerLog_OpenedAt DEFAULT (GETDATE()),
    Kind         INT           NOT NULL,
    InvoiceNo    VARCHAR(30)   NULL,
    CashierId    VARCHAR(20)   NULL,
    Reason       NVARCHAR(100) NULL,
    Opened       BIT           NOT NULL   -- 0 = the printer did not take the command (offline, no paper …)
);
GO

-- Cash put into / taken out of the drawer without a sale, per Z (shift). Added 2026-10-06.
--   Kind 1 opening cash (the float given to the till before it opens; one per Z),
--        2 paid in (money added), 3 paid out (money removed, e.g. paying a supplier — reason required).
--   Status 1 active, 9 replaced (opening cash typed again before the first bill of the Z). Rows are never deleted.
-- The Z's expected cash = opening + cash sales − cash refunds + paid in − paid out. Closing the Z ends its float:
-- the next Z starts with no opening cash until one is entered.
IF OBJECT_ID('dbo.zf_tb_CashMovement', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.zf_tb_CashMovement (
        MoveId     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_zf_tb_CashMovement PRIMARY KEY,
        ZNo        INT           NOT NULL,
        Kind       INT           NOT NULL,
        Amount     DECIMAL(18,2) NOT NULL,   -- always > 0; Kind gives the direction
        Reason     NVARCHAR(100) NULL,
        CashierId  VARCHAR(20)   NULL,
        CreatedAt  DATETIME      NOT NULL CONSTRAINT DF_zf_tb_CashMovement_CreatedAt DEFAULT (GETDATE()),
        Status     INT           NOT NULL CONSTRAINT DF_zf_tb_CashMovement_Status DEFAULT (1)
    );
    CREATE INDEX IX_zf_tb_CashMovement_Z ON dbo.zf_tb_CashMovement (ZNo, Status);
END
GO

-- Z cash totals (filled by zf_sp_CloseZ)
IF COL_LENGTH('dbo.zf_tb_ZReport', 'OpeningCash') IS NULL
    ALTER TABLE dbo.zf_tb_ZReport ADD OpeningCash  DECIMAL(18,2) NULL,
                                      PaidIn       DECIMAL(18,2) NULL,
                                      PaidOut      DECIMAL(18,2) NULL,
                                      ExpectedCash DECIMAL(18,2) NULL;   -- opening + CashAmount + paid in − paid out
GO

-- Bank transfer (PayType 5) and cheque (PayType 6) as their own Z totals (2026-10-12, filled by zf_sp_CloseZ).
-- Both are PART OF OtherAmount (= everything that is not cash or card), which keeps its meaning.
-- NULL = Z closed before this change (not split).
IF COL_LENGTH('dbo.zf_tb_ZReport', 'BankAmount') IS NULL
    ALTER TABLE dbo.zf_tb_ZReport ADD BankAmount   DECIMAL(18,2) NULL,
                                      ChequeAmount DECIMAL(18,2) NULL;
GO

-- Refund against the original bill (2026-10-13, zf_sp_SaveBillRefund): the refund bill points at the bill and the
-- line it gives back, so the till can add up what was already refunded. NULL = a refund without a bill / a sale.
IF COL_LENGTH('dbo.zf_tb_Invoice', 'RefInvoiceNo') IS NULL
    ALTER TABLE dbo.zf_tb_Invoice ADD RefInvoiceNo VARCHAR(30) NULL;       -- refund bills: the sale bill refunded
GO
IF COL_LENGTH('dbo.zf_tb_InvoiceItem', 'RefLineNum') IS NULL
    ALTER TABLE dbo.zf_tb_InvoiceItem ADD RefLineNum INT NULL;             -- LineNum on that sale bill
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_zf_tb_Invoice_Ref' AND object_id = OBJECT_ID('dbo.zf_tb_Invoice'))
    CREATE INDEX IX_zf_tb_Invoice_Ref ON dbo.zf_tb_Invoice (RefInvoiceNo);
GO

/* ---------------------------------------------------------------------------
   2. Drop procs, then types
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.zf_sp_SetupTerminal', 'P')        IS NOT NULL DROP PROCEDURE dbo.zf_sp_SetupTerminal;
IF OBJECT_ID('dbo.zf_sp_OpenZ', 'P')                IS NOT NULL DROP PROCEDURE dbo.zf_sp_OpenZ;
IF OBJECT_ID('dbo.zf_sp_SaveInvoice', 'P')          IS NOT NULL DROP PROCEDURE dbo.zf_sp_SaveInvoice;
IF OBJECT_ID('dbo.zf_sp_VoidInvoice', 'P')          IS NOT NULL DROP PROCEDURE dbo.zf_sp_VoidInvoice;
IF OBJECT_ID('dbo.zf_sp_SuspendBill', 'P')          IS NOT NULL DROP PROCEDURE dbo.zf_sp_SuspendBill;
IF OBJECT_ID('dbo.zf_sp_GetSuspendedBills', 'P')    IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetSuspendedBills;
IF OBJECT_ID('dbo.zf_sp_RecallSuspendedBill', 'P')  IS NOT NULL DROP PROCEDURE dbo.zf_sp_RecallSuspendedBill;
IF OBJECT_ID('dbo.zf_sp_CancelSuspendedBill', 'P')  IS NOT NULL DROP PROCEDURE dbo.zf_sp_CancelSuspendedBill;
IF OBJECT_ID('dbo.zf_sp_FindItem', 'P')             IS NOT NULL DROP PROCEDURE dbo.zf_sp_FindItem;
IF OBJECT_ID('dbo.zf_sp_SearchItems', 'P')          IS NOT NULL DROP PROCEDURE dbo.zf_sp_SearchItems;
IF OBJECT_ID('dbo.zf_sp_GetUnsyncedInvoices', 'P')  IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetUnsyncedInvoices;
IF OBJECT_ID('dbo.zf_sp_GetInvoicesByNo', 'P')      IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetInvoicesByNo;
IF OBJECT_ID('dbo.zf_sp_MarkInvoicesSynced', 'P')   IS NOT NULL DROP PROCEDURE dbo.zf_sp_MarkInvoicesSynced;
IF OBJECT_ID('dbo.zf_sp_CloseZ', 'P')               IS NOT NULL DROP PROCEDURE dbo.zf_sp_CloseZ;
IF OBJECT_ID('dbo.zf_sp_GetZForSubmit', 'P')        IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetZForSubmit;
IF OBJECT_ID('dbo.zf_sp_SetZStatus', 'P')           IS NOT NULL DROP PROCEDURE dbo.zf_sp_SetZStatus;
IF OBJECT_ID('dbo.zf_sp_UpsertItems', 'P')          IS NOT NULL DROP PROCEDURE dbo.zf_sp_UpsertItems;
IF OBJECT_ID('dbo.zf_sp_UpsertStockBalance', 'P')   IS NOT NULL DROP PROCEDURE dbo.zf_sp_UpsertStockBalance;
IF OBJECT_ID('dbo.zf_sp_UpsertPriceLinks', 'P')     IS NOT NULL DROP PROCEDURE dbo.zf_sp_UpsertPriceLinks;
IF OBJECT_ID('dbo.zf_sp_GetBillProfit', 'P')        IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetBillProfit;
IF OBJECT_ID('dbo.zf_sp_GetInvoicesByDate', 'P')    IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetInvoicesByDate;
IF OBJECT_ID('dbo.zf_sp_GetInvoiceForPrint', 'P')   IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetInvoiceForPrint;
IF OBJECT_ID('dbo.zf_sp_LogDrawer', 'P')            IS NOT NULL DROP PROCEDURE dbo.zf_sp_LogDrawer;
IF OBJECT_ID('dbo.zf_sp_AddCashMovement', 'P')      IS NOT NULL DROP PROCEDURE dbo.zf_sp_AddCashMovement;
IF OBJECT_ID('dbo.zf_sp_GetCashSummary', 'P')       IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetCashSummary;
IF OBJECT_ID('dbo.zf_sp_GetXReport', 'P')           IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetXReport;
IF OBJECT_ID('dbo.zf_sp_GetInvoiceForRefund', 'P')  IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetInvoiceForRefund;
IF OBJECT_ID('dbo.zf_sp_SaveBillRefund', 'P')       IS NOT NULL DROP PROCEDURE dbo.zf_sp_SaveBillRefund;
IF OBJECT_ID('dbo.zf_fn_BillLineCost', 'IF')        IS NOT NULL DROP FUNCTION dbo.zf_fn_BillLineCost;
GO
IF TYPE_ID('dbo.zf_tt_RefundLine')     IS NOT NULL DROP TYPE dbo.zf_tt_RefundLine;
IF TYPE_ID('dbo.zf_tt_InvoiceItem')    IS NOT NULL DROP TYPE dbo.zf_tt_InvoiceItem;
IF TYPE_ID('dbo.zf_tt_InvoicePayment') IS NOT NULL DROP TYPE dbo.zf_tt_InvoicePayment;
IF TYPE_ID('dbo.zf_tt_InvoiceNo')      IS NOT NULL DROP TYPE dbo.zf_tt_InvoiceNo;
IF TYPE_ID('dbo.zf_tt_SuspendedItem')  IS NOT NULL DROP TYPE dbo.zf_tt_SuspendedItem;
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
    Amount     DECIMAL(18,2) NOT NULL,
    LineDescrip NVARCHAR(50) NULL,      -- only for ItemId 0 ("other item")
    PriceType  INT           NULL,       -- 1 retail, 2 wholesale; NULL → the bill's @PriceType
    PriceLinkId INT          NULL        -- the price link the cashier picked (its cost is used for profit)
);
GO
CREATE TYPE dbo.zf_tt_InvoicePayment AS TABLE (
    LineNum  INT           NOT NULL PRIMARY KEY,
    PayType  INT           NOT NULL,
    Amount   DECIMAL(18,2) NOT NULL,
    RefNo    VARCHAR(30)   NULL,
    Tendered DECIMAL(18,2) NULL         -- cash handed over (>= Amount); only for the receipt
);
GO
CREATE TYPE dbo.zf_tt_InvoiceNo AS TABLE (
    InvoiceNo VARCHAR(30) NOT NULL PRIMARY KEY
);
GO
-- lines picked on the refund screen (zf_sp_SaveBillRefund): the till works out price and amount itself
CREATE TYPE dbo.zf_tt_RefundLine AS TABLE (
    RefLineNum INT           NOT NULL PRIMARY KEY,   -- LineNum on the sale bill
    Qty        DECIMAL(18,3) NOT NULL                -- how much of it comes back now
);
GO
CREATE TYPE dbo.zf_tt_SuspendedItem AS TABLE (
    LineNum     INT           NOT NULL PRIMARY KEY,
    ItemId      INT           NOT NULL,
    PriceLinkId INT           NULL,
    PriceType   INT           NULL,      -- NULL → the bill's @PriceType
    Qty         DECIMAL(18,3) NOT NULL,
    UnitPrice   DECIMAL(18,2) NOT NULL,
    Discount    DECIMAL(18,2) NOT NULL,
    Amount      DECIMAL(18,2) NOT NULL,
    LineDescrip NVARCHAR(50)  NULL       -- only for ItemId 0 ("other item")
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
    UDate           DATETIME2      NULL,
    CostPrice       DECIMAL(18,2)  NULL,
    UnitCode        VARCHAR(5)     NULL
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
    PriceLinkId     INT            NOT NULL PRIMARY KEY,
    ItemId          INT            NOT NULL,
    RetailPrice     DECIMAL(18,2)  NOT NULL,
    WholesalePrice  DECIMAL(18,2)  NULL,
    Remark          NVARCHAR(50)   NULL,
    Status          INT            NOT NULL,
    UDate           DATETIME       NULL,
    CostPrice       DECIMAL(18,2)  NULL
);
GO

/* ---------------------------------------------------------------------------
   4. Procs
   --------------------------------------------------------------------------- */

-- Cost and profit of each bill line — the ONE rule used by the profit view (zf_sp_GetBillProfit) and the
-- bill discount cap (zf_sp_SaveInvoice).
--   UnitCost: the picked price link's CostPrice, else the item's CostPrice (0 counts as unknown).
--   Profit = Amount - ROUND(Qty * UnitCost, 2); NULL when the cost is unknown (other items, items without a cost).
--   Unknown-cost lines add nothing to the bill profit, so they never allow a bigger discount.
--   InDiscountBase 0 = a NoDiscount item: a bill discount % is not taken off its amount.
CREATE FUNCTION dbo.zf_fn_BillLineCost (@Items dbo.zf_tt_InvoiceItem READONLY)
RETURNS TABLE
AS RETURN
    SELECT l.LineNum, l.ItemId, l.Qty, l.Amount, uc.UnitCost,
           CAST(ROUND(l.Qty * uc.UnitCost, 2) AS DECIMAL(18,2))            AS Cost,
           CAST(l.Amount - ROUND(l.Qty * uc.UnitCost, 2) AS DECIMAL(18,2)) AS Profit,
           CAST(CASE WHEN ISNULL(i.NoDiscount, 0) = 1 THEN 0 ELSE 1 END AS BIT) AS InDiscountBase,
           CASE WHEN i.MaxPrice > 0 THEN i.MaxPrice END                     AS MktPrice
    FROM @Items l
    LEFT JOIN dbo.zf_tb_Item i          ON i.ItemId = l.ItemId AND l.ItemId <> 0
    LEFT JOIN dbo.zf_tb_ItemPriceLink p ON p.PriceLinkId = l.PriceLinkId AND p.ItemId = l.ItemId
    CROSS APPLY (SELECT CAST(COALESCE(NULLIF(p.CostPrice, 0), NULLIF(i.CostPrice, 0)) AS DECIMAL(18,2)) AS UnitCost) uc;
GO

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
--   otherwise: the quantity price for that Qty (bulk levels, see below), or an active price link's retail price;
--   wholesale LINE (line PriceType 2) also: the item's WholesalePrice (> 0) or a price link's WholesalePrice.
--   A retail line can never be charged a wholesale price. Each line has its own PriceType, so a retail bill
--   can have wholesale lines and the other way round; a line without one takes @PriceType.
--   The bill is stored as PriceType 2 when any line is wholesale (for reports).
-- Refunds are not price-checked: they give back what was charged, which may be an older price.
-- "Other item" lines (ItemId 0, item not in the list): any price above 0 with a typed LineDescrip.
--   They are not price-checked and the back office does not move stock for them.
-- Bill discount (sales): never more than the bill's profit (zf_fn_BillLineCost) — 51012. Given as a % →
--   @DiscountPercent is stored for the receipt and @Discount must be ROUND(base * % / 100, 2), base = the lines
--   that are not NoDiscount items. The billing page uses the SAME rule (GET the cap from POST /bill/profit).
CREATE PROCEDURE dbo.zf_sp_SaveInvoice
    @InvType      INT = 1,            -- 1 sale, 2 refund
    @PriceType    INT = 1,            -- default for lines that don't send their own PriceType (1 retail, 2 wholesale)
    @CashierId    VARCHAR(20) = NULL,
    @Discount     DECIMAL(18,2) = 0,  -- bill-level discount
    @Items        dbo.zf_tt_InvoiceItem READONLY,
    @Payments     dbo.zf_tt_InvoicePayment READONLY,
    @InvoiceNo    VARCHAR(30) = NULL OUTPUT,
    @DiscountPercent DECIMAL(5,2) = NULL   -- bill discount given as %; NULL = typed as an amount (or none)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Seq INT, @TerminalCode VARCHAR(10), @ZNo INT, @Gross DECIMAL(18,2), @Net DECIMAL(18,2), @BillPriceType INT;
    DECLARE @Lines TABLE (LineNum INT PRIMARY KEY, UnitCost DECIMAL(18,2), Profit DECIMAL(18,2), InDiscountBase BIT, Amount DECIMAL(18,2), MktPrice DECIMAL(18,2));

    IF @InvType NOT IN (1, 2)
        THROW 51001, 'InvType must be 1 (sale) or 2 (refund).', 1;
    IF @PriceType NOT IN (1, 2)
        THROW 51009, 'PriceType must be 1 (retail) or 2 (wholesale).', 1;
    IF EXISTS (SELECT 1 FROM @Items WHERE PriceType NOT IN (1, 2))
        THROW 51009, 'Line PriceType must be 1 (retail) or 2 (wholesale).', 1;
    IF NOT EXISTS (SELECT 1 FROM @Items)
        THROW 51002, 'Bill has no items.', 1;
    IF EXISTS (SELECT 1 FROM @Items WHERE Qty <= 0)
        THROW 51003, 'Item quantity must be positive (use InvType 2 for refunds).', 1;
    IF EXISTS (SELECT 1 FROM @Items WHERE Amount <> ROUND(Qty * UnitPrice, 2) - Discount)
        THROW 51004, 'Line Amount must equal Qty * UnitPrice - Discount.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Config)
        THROW 51005, 'Till is not set up (run zf_sp_SetupTerminal).', 1;
    -- "other item" = an item that is not in the item list: ItemId 0, the cashier types the name and price
    IF EXISTS (SELECT 1 FROM @Items WHERE ItemId = 0 AND (LTRIM(RTRIM(ISNULL(LineDescrip, N''))) = N'' OR UnitPrice <= 0))
        THROW 51010, 'Other item needs a description and a price above 0.', 1;

    SELECT @Gross = SUM(ROUND(Qty * UnitPrice, 2)), @Net = SUM(Amount) - @Discount FROM @Items;
    -- bill type for reports: wholesale when any line is wholesale
    SET @BillPriceType = CASE WHEN EXISTS (SELECT 1 FROM @Items WHERE ISNULL(PriceType, @PriceType) = 2) THEN 2 ELSE 1 END;

    IF ISNULL((SELECT SUM(Amount) FROM @Payments), 0) <> @Net
        THROW 51006, 'Payments must add up to the bill net amount.', 1;
    IF EXISTS (SELECT 1 FROM @Payments WHERE Tendered < Amount)
        THROW 51015, 'Cash tendered cannot be less than the amount paid.', 1;

    INSERT @Lines (LineNum, UnitCost, Profit, InDiscountBase, Amount, MktPrice)
    SELECT LineNum, UnitCost, Profit, InDiscountBase, Amount, MktPrice FROM dbo.zf_fn_BillLineCost(@Items);

    IF @Discount < 0
        THROW 51013, 'Bill discount cannot be negative.', 1;
    IF @DiscountPercent IS NOT NULL
    BEGIN
        IF @DiscountPercent <= 0 OR @DiscountPercent > 100
            THROW 51014, 'Discount percent must be above 0 and at most 100.', 1;
        IF @Discount <> ROUND(ISNULL((SELECT SUM(Amount) FROM @Lines WHERE InDiscountBase = 1), 0) * @DiscountPercent / 100, 2)
            THROW 51014, 'Bill discount does not match the discount percent of the bill. Enter the discount again.', 1;
    END
    IF @InvType = 1 AND @Discount > 0
    BEGIN
        DECLARE @MaxDiscount DECIMAL(18,2) = ISNULL((SELECT SUM(ISNULL(Profit, 0)) FROM @Lines), 0);
        IF @MaxDiscount < 0 SET @MaxDiscount = 0;
        IF @Discount > @MaxDiscount
        BEGIN
            DECLARE @DiscMsg NVARCHAR(200) = N'Discount is more than this bill allows (max Rs ' + CONVERT(NVARCHAR(30), @MaxDiscount) + N').';
            THROW 51012, @DiscMsg, 1;
        END
    END

    IF @InvType = 1
    BEGIN
        DECLARE @BadItem NVARCHAR(200), @Msg NVARCHAR(400);

        SELECT TOP 1 @BadItem = CAST(l.ItemId AS NVARCHAR(20))
        FROM @Items l WHERE l.ItemId <> 0 AND NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Item i WHERE i.ItemId = l.ItemId);
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
        -- ISNULLs keep every test TRUE/FALSE: a NULL price must never let a line through.
        WHERE i.OpenPrice = 0
          AND l.UnitPrice <> ISNULL(q.Price, ISNULL(i.RetailPrice, -1))
          AND NOT (ISNULL(l.PriceType, @PriceType) = 2 AND ISNULL(i.WholesalePrice, 0) > 0 AND l.UnitPrice = ISNULL(i.WholesalePrice, 0))
          AND NOT EXISTS (SELECT 1 FROM dbo.zf_tb_ItemPriceLink p
                          WHERE p.ItemId = l.ItemId AND p.Status = 1
                            AND (p.RetailPrice = l.UnitPrice OR (ISNULL(l.PriceType, @PriceType) = 2 AND p.WholesalePrice = l.UnitPrice)));
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

        INSERT dbo.zf_tb_Invoice (InvoiceNo, InvoiceSeq, ZNo, InvType, InvDate, CashierId, GrossAmount, Discount, NetAmount, Status, PriceType, DiscountPercent)
        VALUES (@InvoiceNo, @Seq, @ZNo, @InvType, GETDATE(), @CashierId, @Gross, @Discount, @Net, 1, @BillPriceType, @DiscountPercent);

        INSERT dbo.zf_tb_InvoiceItem (InvoiceNo, LineNum, ItemId, Qty, UnitPrice, Discount, Amount, LineDescrip, PriceType,
                                      PriceLinkId, UnitCost, MktPrice)
        SELECT @InvoiceNo, it.LineNum, it.ItemId, it.Qty, it.UnitPrice, it.Discount, it.Amount,
               CASE WHEN it.ItemId = 0 THEN LTRIM(RTRIM(it.LineDescrip)) END,   -- real items keep their name in zf_tb_Item
               ISNULL(it.PriceType, @PriceType),
               it.PriceLinkId, c.UnitCost, c.MktPrice
        FROM @Items it
        JOIN @Lines c ON c.LineNum = it.LineNum;

        INSERT dbo.zf_tb_InvoicePayment (InvoiceNo, LineNum, PayType, Amount, RefNo, Tendered)
        SELECT @InvoiceNo, LineNum, PayType, Amount, RefNo, Tendered FROM @Payments;

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

-- Puts the bill on the screen aside (before payment) → @SuspendId. Not an invoice: no number, no Z, no upload.
-- Prices are NOT checked here — zf_sp_SaveInvoice checks them when the recalled bill is paid.
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
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @InvType NOT IN (1, 2)
        THROW 51001, 'InvType must be 1 (sale) or 2 (refund).', 1;
    IF @PriceType NOT IN (1, 2) OR EXISTS (SELECT 1 FROM @Items WHERE PriceType NOT IN (1, 2))
        THROW 51009, 'PriceType must be 1 (retail) or 2 (wholesale).', 1;
    IF NOT EXISTS (SELECT 1 FROM @Items)
        THROW 51031, 'There is nothing to suspend: the bill has no items.', 1;
    IF EXISTS (SELECT 1 FROM @Items WHERE Qty <= 0)
        THROW 51003, 'Item quantity must be positive (use InvType 2 for refunds).', 1;
    IF EXISTS (SELECT 1 FROM @Items WHERE Amount <> ROUND(Qty * UnitPrice, 2) - Discount)
        THROW 51004, 'Line Amount must equal Qty * UnitPrice - Discount.', 1;
    IF EXISTS (SELECT 1 FROM @Items WHERE ItemId = 0 AND (LTRIM(RTRIM(ISNULL(LineDescrip, N''))) = N'' OR UnitPrice <= 0))
        THROW 51010, 'Other item needs a description and a price above 0.', 1;

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
END
GO

-- Bills waiting to be recalled, oldest first (the recall list). FirstItems = a short preview of the lines.
CREATE PROCEDURE dbo.zf_sp_GetSuspendedBills
AS
BEGIN
    SET NOCOUNT ON;
    SELECT b.SuspendId, b.Label, b.InvType, b.PriceType, b.CashierId, b.LineCount, b.NetAmount, b.SuspendedAt,
           STUFF((SELECT TOP 3 N', ' + ISNULL(l.LineDescrip, ISNULL(i.Inv_Descrip, i.Descrip))
                  FROM dbo.zf_tb_SuspendedBillItem l
                  LEFT JOIN dbo.zf_tb_Item i ON i.ItemId = l.ItemId AND l.ItemId <> 0
                  WHERE l.SuspendId = b.SuspendId
                  ORDER BY l.LineNum
                  FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N'') AS FirstItems
    FROM dbo.zf_tb_SuspendedBill b
    WHERE b.Status = 1
    ORDER BY b.SuspendId;
END
GO

-- Takes a suspended bill back to the billing screen (Status 2) — once only, so it can't be billed twice.
-- 2 result sets: the header, then the lines with the item's CURRENT name, status and prices
-- (ItemFound 0 = the item is gone or inactive: the page drops that line and says so).
CREATE PROCEDURE dbo.zf_sp_RecallSuspendedBill
    @SuspendId INT,
    @CashierId VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.zf_tb_SuspendedBill
    SET Status = 2, ClosedAt = GETDATE(), ClosedBy = @CashierId
    WHERE SuspendId = @SuspendId AND Status = 1;

    IF @@ROWCOUNT = 0
        THROW 51032, 'This suspended bill was already recalled or cancelled.', 1;

    SELECT SuspendId, Label, InvType, PriceType, CashierId, Discount, LineCount, NetAmount, SuspendedAt, DiscountPercent
    FROM dbo.zf_tb_SuspendedBill WHERE SuspendId = @SuspendId;

    SELECT l.LineNum, l.ItemId, l.PriceLinkId, l.PriceType, l.Qty, l.UnitPrice, l.Discount, l.Amount, l.LineDescrip,
           CAST(CASE WHEN l.ItemId = 0 OR i.Status = 1 THEN 1 ELSE 0 END AS BIT) AS ItemFound,
           ISNULL(l.LineDescrip, ISNULL(i.Inv_Descrip, i.Descrip)) AS Name
    FROM dbo.zf_tb_SuspendedBillItem l
    LEFT JOIN dbo.zf_tb_Item i ON i.ItemId = l.ItemId AND l.ItemId <> 0
    WHERE l.SuspendId = @SuspendId
    ORDER BY l.LineNum;
END
GO

-- Throws a suspended bill away (customer left). Kept as Status 9 for audit.
CREATE PROCEDURE dbo.zf_sp_CancelSuspendedBill
    @SuspendId INT,
    @CashierId VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.zf_tb_SuspendedBill
    SET Status = 9, ClosedAt = GETDATE(), ClosedBy = @CashierId
    WHERE SuspendId = @SuspendId AND Status = 1;

    IF @@ROWCOUNT = 0
        THROW 51032, 'This suspended bill was already recalled or cancelled.', 1;
END
GO

-- Barcode, then RefCode — or one item by @ItemId (picked from zf_sp_SearchItems). Active items only.
-- Scale sticker: when nothing matches and @Code is 10 digits, it is read as 5 digits scale code + 5 digits weight in
-- grams (1000801410 = RefCode 10008, 1.410 kg). Scale items (UnitCode KGS) only; the scale code is the RefCode padded
-- to 5 digits, same rule as the PLU in the scale export (05_BackOffice_Export.sql). Weight 00000 = not found.
-- 2 result sets: the item (with the last known stock, for display; ScaleQty = the sticker weight in kg, else NULL),
-- then its active price links (empty = sell at the normal / quantity price, no price choice).
CREATE PROCEDURE dbo.zf_sp_FindItem
    @Code   NVARCHAR(50) = NULL,
    @ItemId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ScaleQty DECIMAL(18,3);

    IF @ItemId IS NOT NULL
        SET @ItemId = (SELECT ItemId FROM dbo.zf_tb_Item WHERE ItemId = @ItemId AND Status = 1);   -- NULL if inactive / missing
    ELSE
    BEGIN
        SELECT TOP 1 @ItemId = i.ItemId
        FROM dbo.zf_tb_Item i
        WHERE (i.Barcode = @Code OR i.RefCode = @Code) AND i.Status = 1
        ORDER BY CASE WHEN i.Barcode = @Code THEN 0 ELSE 1 END;

        IF @ItemId IS NULL AND LEN(@Code) = 10 AND @Code NOT LIKE N'%[^0-9]%' AND RIGHT(@Code, 5) <> N'00000'
        BEGIN
            SELECT TOP 1 @ItemId = i.ItemId
            FROM dbo.zf_tb_Item i
            WHERE i.UnitCode = 'KGS' AND i.Status = 1
              AND i.RefCode NOT LIKE N'%[^0-9]%' AND LEN(i.RefCode) BETWEEN 1 AND 5
              AND RIGHT(N'00000' + i.RefCode, 5) = LEFT(@Code, 5)
            ORDER BY i.ItemId;

            IF @ItemId IS NOT NULL
                SET @ScaleQty = CAST(RIGHT(@Code, 5) AS INT) / 1000.0;
        END
    END

    SELECT i.*, s.Qty AS StockQty, @ScaleQty AS ScaleQty
    FROM dbo.zf_tb_Item i
    LEFT JOIN dbo.zf_tb_StockBalance s ON s.ItemId = i.ItemId
    WHERE i.ItemId = @ItemId;

    SELECT PriceLinkId, RetailPrice, WholesalePrice, Remark
    FROM dbo.zf_tb_ItemPriceLink
    WHERE ItemId = @ItemId AND Status = 1
    ORDER BY RetailPrice;
END
GO

-- Cashier search by name: every word typed must appear in Descrip or Inv_Descrip (any order, any case),
-- e.g. 'sugar 1kg' finds 'SUGAR WHITE 1KG'. Active items only, names starting with the text first.
-- Pick a row, then zf_sp_FindItem @ItemId for the full item and its price links.
-- Works on SQL Server 2008 R2 (tills still on 2008): the words are split with a loop, not STRING_SPLIT.
CREATE PROCEDURE dbo.zf_sp_SearchItems
    @Text NVARCHAR(100),
    @Top  INT = 50
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
        SET @Top = 0;   -- nothing typed → no rows (same columns, so callers always get one shape)

    SELECT TOP (@Top)
           i.ItemId, i.RefCode, i.Barcode, i.Descrip, i.Inv_Descrip,
           ISNULL(i.RetailPrice, 0) AS RetailPrice, i.WholesalePrice, i.OpenPrice, i.IsSaleLocked, s.Qty AS StockQty,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM dbo.zf_tb_ItemPriceLink p WHERE p.ItemId = i.ItemId AND p.Status = 1)
                     THEN 1 ELSE 0 END AS BIT) AS HasPriceLinks
    FROM dbo.zf_tb_Item i
    LEFT JOIN dbo.zf_tb_StockBalance s ON s.ItemId = i.ItemId
    WHERE i.Status = 1
      AND NOT EXISTS (SELECT 1 FROM @words w
                      WHERE ISNULL(i.Descrip, N'') NOT LIKE N'%' + w.Word + N'%'
                        AND ISNULL(i.Inv_Descrip, N'') NOT LIKE N'%' + w.Word + N'%')
    ORDER BY CASE WHEN i.Descrip LIKE @t + N'%' OR i.Inv_Descrip LIKE @t + N'%' THEN 0 ELSE 1 END, i.Descrip;
END
GO

-- Specific bills (used to resend the ones the back office reports missing for a Z).
CREATE PROCEDURE dbo.zf_sp_GetInvoicesByNo
    @InvoiceNos dbo.zf_tt_InvoiceNo READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SELECT i.InvoiceNo, i.InvoiceSeq, i.ZNo, i.InvType, i.InvDate, i.CashierId, i.GrossAmount, i.Discount, i.NetAmount, i.Status, i.PriceType
    FROM dbo.zf_tb_Invoice i JOIN @InvoiceNos n ON n.InvoiceNo = i.InvoiceNo ORDER BY i.InvoiceSeq;

    SELECT it.InvoiceNo, it.LineNum, it.ItemId, it.Qty, it.UnitPrice, it.Discount, it.Amount, it.LineDescrip, it.PriceType,
           it.UnitCost   -- back office sales dashboard profit
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
            -- part of OtherAmount: 5 bank transfer, 6 cheque
            BankAmount   = ISNULL((SELECT SUM(CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END)
                                   FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                                   WHERE i.ZNo = @ZNo AND i.Status <> 9 AND p.PayType = 5), 0),
            ChequeAmount = ISNULL((SELECT SUM(CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END)
                                   FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                                   WHERE i.ZNo = @ZNo AND i.Status <> 9 AND p.PayType = 6), 0),
            Status       = 1
        FROM dbo.zf_tb_ZReport z
        WHERE z.ZNo = @ZNo;

        UPDATE dbo.zf_tb_ZReport SET NetSales = SalesAmount - RefundAmount WHERE ZNo = @ZNo;

        -- drawer cash for the cashier's count (zf_sp_GetCashSummary shows the same while the Z is open)
        UPDATE z SET
            OpeningCash = ISNULL((SELECT SUM(Amount) FROM dbo.zf_tb_CashMovement WHERE ZNo = @ZNo AND Status = 1 AND Kind = 1), 0),
            PaidIn      = ISNULL((SELECT SUM(Amount) FROM dbo.zf_tb_CashMovement WHERE ZNo = @ZNo AND Status = 1 AND Kind = 2), 0),
            PaidOut     = ISNULL((SELECT SUM(Amount) FROM dbo.zf_tb_CashMovement WHERE ZNo = @ZNo AND Status = 1 AND Kind = 3), 0)
        FROM dbo.zf_tb_ZReport z WHERE z.ZNo = @ZNo;
        UPDATE dbo.zf_tb_ZReport SET ExpectedCash = OpeningCash + CashAmount + PaidIn - PaidOut WHERE ZNo = @ZNo;
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
           z.CashAmount, z.CardAmount, z.OtherAmount, z.BankAmount, z.ChequeAmount, z.Status
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
            QtyLevel4 = s.QtyLevel4, PriceLevel4 = s.PriceLevel4, Status = s.Status, UDate = s.UDate,
            CostPrice = s.CostPrice, UnitCode = s.UnitCode
        FROM dbo.zf_tb_Item t JOIN @Items s ON s.ItemId = t.ItemId;

        INSERT dbo.zf_tb_Item (ItemId, RefCode, Barcode, Descrip, Inv_Descrip, SinhalaDescrip, OpenPrice, MaxPrice,
                               RetailPrice, WholesalePrice, SpecialPrice, IsSaleLocked, NoDiscount, DiscountAmount, DiscountPercent,
                               QtyLevel2, PriceLevel2, QtyLevel3, PriceLevel3, QtyLevel4, PriceLevel4, Status, UDate, CostPrice,
                               UnitCode)
        SELECT s.ItemId, s.RefCode, s.Barcode, s.Descrip, s.Inv_Descrip, s.SinhalaDescrip, s.OpenPrice, s.MaxPrice,
               s.RetailPrice, s.WholesalePrice, s.SpecialPrice, s.IsSaleLocked, s.NoDiscount, s.DiscountAmount, s.DiscountPercent,
               s.QtyLevel2, s.PriceLevel2, s.QtyLevel3, s.PriceLevel3, s.QtyLevel4, s.PriceLevel4, s.Status, s.UDate, s.CostPrice,
               s.UnitCode
        FROM @Items s WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Item t WHERE t.ItemId = s.ItemId);

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
        UPDATE t SET ItemId = s.ItemId, RetailPrice = s.RetailPrice, WholesalePrice = s.WholesalePrice,
                     Remark = s.Remark, Status = s.Status, UDate = s.UDate, CostPrice = s.CostPrice
        FROM dbo.zf_tb_ItemPriceLink t JOIN @Rows s ON s.PriceLinkId = t.PriceLinkId;

        INSERT dbo.zf_tb_ItemPriceLink (PriceLinkId, ItemId, RetailPrice, WholesalePrice, Remark, Status, UDate, CostPrice)
        SELECT s.PriceLinkId, s.ItemId, s.RetailPrice, s.WholesalePrice, s.Remark, s.Status, s.UDate, s.CostPrice FROM @Rows s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_ItemPriceLink t WHERE t.PriceLinkId = s.PriceLinkId);

        UPDATE dbo.zf_tb_Config SET LastPriceLinkSyncAt = @ServerTime WHERE Id = 1;
    COMMIT;
END
GO

-- Profit view and discount cap for the bill on the screen (TillService POST /bill/profit, supervisor PIN only).
-- Same rule as zf_sp_SaveInvoice (zf_fn_BillLineCost). 2 result sets:
--   lines:  LineNum, UnitCost, Cost, Profit (NULL = cost unknown)
--   totals: Amount, Cost, Profit (known lines only), UnknownCostLines, DiscountBase,
--           MaxDiscount (= profit, never below 0), MaxDiscountPercent (of DiscountBase, rounded DOWN to 2 decimals)
CREATE PROCEDURE dbo.zf_sp_GetBillProfit
    @Items dbo.zf_tt_InvoiceItem READONLY
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @c TABLE (LineNum INT PRIMARY KEY, Amount DECIMAL(18,2), UnitCost DECIMAL(18,2), Cost DECIMAL(18,2),
                      Profit DECIMAL(18,2), InDiscountBase BIT);
    INSERT @c SELECT LineNum, Amount, UnitCost, Cost, Profit, InDiscountBase FROM dbo.zf_fn_BillLineCost(@Items);

    SELECT LineNum, UnitCost, Cost, Profit FROM @c ORDER BY LineNum;

    DECLARE @Profit DECIMAL(18,2) = ISNULL((SELECT SUM(ISNULL(Profit, 0)) FROM @c), 0),
            @Base   DECIMAL(18,2) = ISNULL((SELECT SUM(Amount) FROM @c WHERE InDiscountBase = 1), 0);
    DECLARE @Max DECIMAL(18,2) = CASE WHEN @Profit > 0 THEN @Profit ELSE 0 END;

    SELECT ISNULL((SELECT SUM(Amount) FROM @c), 0)                    AS Amount,
           ISNULL((SELECT SUM(Cost) FROM @c WHERE Cost IS NOT NULL), 0) AS Cost,
           @Profit                                                     AS Profit,
           (SELECT COUNT(*) FROM @c WHERE UnitCost IS NULL)            AS UnknownCostLines,
           @Base                                                       AS DiscountBase,
           @Max                                                        AS MaxDiscount,
           CAST(CASE WHEN @Base > 0 AND @Max < @Base THEN FLOOR(@Max * 10000 / @Base) / 100
                     WHEN @Base > 0 THEN 100 ELSE 0 END AS DECIMAL(5,2)) AS MaxDiscountPercent;
END
GO

-- Bills of one day (newest first) for the reprint list. Voided bills are listed too (Status 9).
CREATE PROCEDURE dbo.zf_sp_GetInvoicesByDate
    @Date DATE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT i.InvoiceNo, i.InvType, i.InvDate, i.CashierId, i.ZNo, i.NetAmount, i.Discount, i.Status, i.Synced,
           (SELECT COUNT(*) FROM dbo.zf_tb_InvoiceItem it WHERE it.InvoiceNo = i.InvoiceNo) AS LineCount,
           ISNULL((SELECT SUM(p.Amount) FROM dbo.zf_tb_InvoicePayment p WHERE p.InvoiceNo = i.InvoiceNo AND p.PayType = 1), 0) AS CashAmount,
           ISNULL((SELECT SUM(p.Amount) FROM dbo.zf_tb_InvoicePayment p WHERE p.InvoiceNo = i.InvoiceNo AND p.PayType = 2), 0) AS CardAmount,
           ISNULL((SELECT SUM(p.Amount) FROM dbo.zf_tb_InvoicePayment p WHERE p.InvoiceNo = i.InvoiceNo AND p.PayType NOT IN (1, 2)), 0) AS OtherAmount
    FROM dbo.zf_tb_Invoice i
    WHERE i.InvDate >= @Date AND i.InvDate < DATEADD(DAY, 1, @Date)
    ORDER BY i.InvoiceSeq DESC;
END
GO

-- One bill with everything the receipt needs. 3 result sets: header (+ till code), lines (with the item's code
-- and name), payments. 51041 when there is no such bill on this till.
CREATE PROCEDURE dbo.zf_sp_GetInvoiceForPrint
    @InvoiceNo VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Invoice WHERE InvoiceNo = @InvoiceNo)
        THROW 51041, 'Bill not found on this till.', 1;

    SELECT i.InvoiceNo, i.InvoiceSeq, i.ZNo, i.InvType, i.InvDate, i.CashierId, i.GrossAmount, i.Discount,
           i.DiscountPercent, i.NetAmount, i.Status, i.PriceType, i.Synced, c.TerminalCode,
           i.RefInvoiceNo   -- refund against a bill: the sale bill (printed on the refund receipt)
    FROM dbo.zf_tb_Invoice i CROSS JOIN dbo.zf_tb_Config c
    WHERE i.InvoiceNo = @InvoiceNo;

    SELECT it.LineNum, it.ItemId, it.Qty, it.UnitPrice, it.Discount, it.Amount, it.PriceType, it.MktPrice,
           COALESCE(it.LineDescrip, m.Inv_Descrip, m.Descrip, N'Item ' + CAST(it.ItemId AS NVARCHAR(20))) AS Name,
           COALESCE(m.Barcode, m.RefCode, CASE WHEN it.ItemId <> 0 THEN CAST(it.ItemId AS NVARCHAR(20)) END) AS Code
    FROM dbo.zf_tb_InvoiceItem it
    LEFT JOIN dbo.zf_tb_Item m ON m.ItemId = it.ItemId AND it.ItemId <> 0
    WHERE it.InvoiceNo = @InvoiceNo
    ORDER BY it.LineNum;

    SELECT LineNum, PayType, Amount, RefNo, Tendered
    FROM dbo.zf_tb_InvoicePayment WHERE InvoiceNo = @InvoiceNo ORDER BY LineNum;
END
GO

-- A sale bill as the refund screen shows it: what was sold, what was already given back, what is left.
-- 3 result sets: header (CanRefund 0 + Reason when nothing on it can be refunded), lines, the bill's payments.
-- 51041 when there is no such bill on this till — a bill is refunded on the till that made it.
CREATE PROCEDURE dbo.zf_sp_GetInvoiceForRefund
    @InvoiceNo VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Invoice WHERE InvoiceNo = @InvoiceNo)
        THROW 51041, 'Bill not found on this till.', 1;

    -- given back so far, per line of the sale bill (refund bills that were voided do not count)
    DECLARE @Done TABLE (LineNum INT PRIMARY KEY, Qty DECIMAL(18,3));
    INSERT @Done (LineNum, Qty)
    SELECT it.RefLineNum, SUM(it.Qty)
    FROM dbo.zf_tb_Invoice r
    JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = r.InvoiceNo
    WHERE r.RefInvoiceNo = @InvoiceNo AND r.InvType = 2 AND r.Status <> 9 AND it.RefLineNum IS NOT NULL
    GROUP BY it.RefLineNum;

    DECLARE @Left DECIMAL(18,3) = ISNULL((SELECT SUM(it.Qty - ISNULL(d.Qty, 0))
                                          FROM dbo.zf_tb_InvoiceItem it LEFT JOIN @Done d ON d.LineNum = it.LineNum
                                          WHERE it.InvoiceNo = @InvoiceNo), 0);

    SELECT i.InvoiceNo, i.ZNo, i.InvType, i.InvDate, i.CashierId, i.GrossAmount, i.Discount, i.DiscountPercent,
           i.NetAmount, i.Status, i.PriceType,
           ISNULL((SELECT SUM(r.NetAmount) FROM dbo.zf_tb_Invoice r
                   WHERE r.RefInvoiceNo = i.InvoiceNo AND r.InvType = 2 AND r.Status <> 9), 0) AS RefundedAmount,
           CAST(CASE WHEN i.InvType = 1 AND i.Status = 1 AND @Left > 0 THEN 1 ELSE 0 END AS BIT) AS CanRefund,
           CASE WHEN i.InvType <> 1 THEN N'This is a refund bill - it cannot be refunded.'
                WHEN i.Status <> 1  THEN N'This bill was voided - it cannot be refunded.'
                WHEN @Left <= 0     THEN N'Everything on this bill was already refunded.' END AS Reason
    FROM dbo.zf_tb_Invoice i
    WHERE i.InvoiceNo = @InvoiceNo;

    SELECT it.LineNum, it.ItemId, it.Qty, it.UnitPrice, it.Discount, it.Amount, it.PriceType,
           COALESCE(it.LineDescrip, m.Inv_Descrip, m.Descrip, N'Item ' + CAST(it.ItemId AS NVARCHAR(20))) AS Name,
           COALESCE(m.Barcode, m.RefCode, CASE WHEN it.ItemId <> 0 THEN CAST(it.ItemId AS NVARCHAR(20)) END) AS Code,
           m.UnitCode,
           CAST(ISNULL(d.Qty, 0) AS DECIMAL(18,3))          AS RefundedQty,
           CAST(it.Qty - ISNULL(d.Qty, 0) AS DECIMAL(18,3)) AS LeftQty
    FROM dbo.zf_tb_InvoiceItem it
    LEFT JOIN @Done d ON d.LineNum = it.LineNum
    LEFT JOIN dbo.zf_tb_Item m ON m.ItemId = it.ItemId AND it.ItemId <> 0
    WHERE it.InvoiceNo = @InvoiceNo
    ORDER BY it.LineNum;

    SELECT LineNum, PayType, Amount, RefNo
    FROM dbo.zf_tb_InvoicePayment WHERE InvoiceNo = @InvoiceNo ORDER BY LineNum;
END
GO

-- Refund against the original bill. The page sends only WHICH lines and HOW MUCH of each (@Lines); the price,
-- the discounts and the amount come from the sale bill, never from the page.
--   - Only a completed sale bill of THIS till. A line can never give back more than was sold on it minus what
--     earlier refunds of the same bill already gave back (51066) — no PIN lifts that.
--   - Line: the sale's UnitPrice; its line discount in proportion to the quantity (the last part of a line takes
--     what is left of the discount).
--   - Bill discount of the sale: given back in proportion to the refunded line amounts; the refund that brings the
--     last of the bill back takes what is left, so the refunds of a bill add up to what the customer paid.
--   - Saved by zf_sp_SaveInvoice as a normal refund bill (InvType 2: own number, open Z, upload, stock comes back
--     on the back office) with ONE payment of the whole amount (@PayType / @RefNo), then marked with
--     RefInvoiceNo / RefLineNum. UnitCost and MktPrice are the sale's, so the profit taken back is the profit made.
--   - @CheckOnly 1: nothing is saved — the same checks and amounts, for the screen before the cashier confirms.
-- 2 result sets: totals (InvoiceNo NULL when @CheckOnly), refund lines.
CREATE PROCEDURE dbo.zf_sp_SaveBillRefund
    @RefInvoiceNo VARCHAR(30),
    @CashierId    VARCHAR(20) = NULL,
    @PayType      INT = 1,              -- how the money goes back: 1 cash, 2 card, 3 credit, 4 voucher, 5 bank transfer, 6 cheque
    @RefNo        VARCHAR(30) = NULL,
    @Lines        dbo.zf_tt_RefundLine READONLY,
    @CheckOnly    BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @InvoiceNo VARCHAR(30), @InvType INT, @Status INT, @BillDiscount DECIMAL(18,2), @BillLines DECIMAL(18,2),
            @Sub DECIMAL(18,2), @Discount DECIMAL(18,2), @Net DECIMAL(18,2), @GivenBack DECIMAL(18,2), @AllBack BIT,
            @Msg NVARCHAR(400);
    DECLARE @Items dbo.zf_tt_InvoiceItem, @Payments dbo.zf_tt_InvoicePayment;
    DECLARE @Map  TABLE (LineNum INT PRIMARY KEY, RefLineNum INT NOT NULL);
    DECLARE @Done TABLE (LineNum INT PRIMARY KEY, Qty DECIMAL(18,3), Discount DECIMAL(18,2));

    IF NOT EXISTS (SELECT 1 FROM @Lines)
        THROW 51061, 'Pick at least one line to refund.', 1;
    IF EXISTS (SELECT 1 FROM @Lines WHERE Qty <= 0)
        THROW 51062, 'Refund quantity must be above 0.', 1;
    IF @PayType NOT IN (1, 2, 3, 4, 5, 6)
        THROW 51067, 'Payment type must be 1 cash, 2 card, 3 credit, 4 voucher, 5 bank transfer or 6 cheque.', 1;

    BEGIN TRAN;
        -- the sale bill stays locked until the refund is saved: two refunds of one bill can't both pass the check
        SELECT @InvType = InvType, @Status = Status, @BillDiscount = Discount
        FROM dbo.zf_tb_Invoice WITH (UPDLOCK, HOLDLOCK) WHERE InvoiceNo = @RefInvoiceNo;

        IF @InvType IS NULL
            THROW 51041, 'Bill not found on this till.', 1;
        IF @InvType <> 1
            THROW 51063, 'This is a refund bill - it cannot be refunded.', 1;
        IF @Status <> 1
            THROW 51064, 'This bill was voided - it cannot be refunded.', 1;
        IF EXISTS (SELECT 1 FROM @Lines l
                   WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_InvoiceItem it WHERE it.InvoiceNo = @RefInvoiceNo AND it.LineNum = l.RefLineNum))
            THROW 51065, 'A picked line is not on this bill. Scan the bill again.', 1;

        INSERT @Done (LineNum, Qty, Discount)
        SELECT it.RefLineNum, SUM(it.Qty), SUM(it.Discount)
        FROM dbo.zf_tb_Invoice r
        JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = r.InvoiceNo
        WHERE r.RefInvoiceNo = @RefInvoiceNo AND r.InvType = 2 AND r.Status <> 9 AND it.RefLineNum IS NOT NULL
        GROUP BY it.RefLineNum;

        -- never more than was sold on the line minus what was already given back
        SELECT TOP 1 @Msg = COALESCE(it.LineDescrip, m.Inv_Descrip, m.Descrip, N'Line ' + CAST(it.LineNum AS NVARCHAR(10)))
               + CASE WHEN it.Qty - ISNULL(d.Qty, 0) <= 0 THEN N' was already refunded in full.'
                      ELSE N': only ' + CONVERT(NVARCHAR(30), CAST(it.Qty - ISNULL(d.Qty, 0) AS DECIMAL(18,3)))
                           + N' left to refund (sold ' + CONVERT(NVARCHAR(30), it.Qty)
                           + N', already refunded ' + CONVERT(NVARCHAR(30), CAST(ISNULL(d.Qty, 0) AS DECIMAL(18,3))) + N').' END
        FROM @Lines l
        JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = @RefInvoiceNo AND it.LineNum = l.RefLineNum
        LEFT JOIN @Done d ON d.LineNum = it.LineNum
        LEFT JOIN dbo.zf_tb_Item m ON m.ItemId = it.ItemId AND it.ItemId <> 0
        WHERE l.Qty > it.Qty - ISNULL(d.Qty, 0)
        ORDER BY l.RefLineNum;
        IF @Msg IS NOT NULL
            THROW 51066, @Msg, 1;

        INSERT @Map (LineNum, RefLineNum)
        SELECT ROW_NUMBER() OVER (ORDER BY RefLineNum), RefLineNum FROM @Lines;

        INSERT @Items (LineNum, ItemId, Qty, UnitPrice, Discount, Amount, LineDescrip, PriceType, PriceLinkId)
        SELECT mp.LineNum, it.ItemId, l.Qty, it.UnitPrice, x.Discount, ROUND(l.Qty * it.UnitPrice, 2) - x.Discount,
               CASE WHEN it.ItemId = 0 THEN it.LineDescrip END, it.PriceType, it.PriceLinkId
        FROM @Map mp
        JOIN @Lines l ON l.RefLineNum = mp.RefLineNum
        JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = @RefInvoiceNo AND it.LineNum = l.RefLineNum
        LEFT JOIN @Done d ON d.LineNum = it.LineNum
        CROSS APPLY (SELECT CAST(CASE WHEN l.Qty < it.Qty - ISNULL(d.Qty, 0) THEN ROUND(it.Discount * l.Qty / it.Qty, 2)
                                      WHEN it.Discount > ISNULL(d.Discount, 0) THEN it.Discount - ISNULL(d.Discount, 0)
                                      ELSE 0 END AS DECIMAL(18,2)) AS Discount) x;

        SELECT @Sub = SUM(Amount) FROM @Items;
        SELECT @BillLines = SUM(Amount) FROM dbo.zf_tb_InvoiceItem WHERE InvoiceNo = @RefInvoiceNo;
        SELECT @GivenBack = ISNULL(SUM(Discount), 0) FROM dbo.zf_tb_Invoice
        WHERE RefInvoiceNo = @RefInvoiceNo AND InvType = 2 AND Status <> 9;
        SET @AllBack = CASE WHEN EXISTS (SELECT 1 FROM dbo.zf_tb_InvoiceItem it
                                         LEFT JOIN @Done d ON d.LineNum = it.LineNum
                                         LEFT JOIN @Lines l ON l.RefLineNum = it.LineNum
                                         WHERE it.InvoiceNo = @RefInvoiceNo AND it.Qty - ISNULL(d.Qty, 0) - ISNULL(l.Qty, 0) > 0)
                            THEN 0 ELSE 1 END;

        SET @Discount = CASE WHEN @BillDiscount <= 0 OR @BillLines <= 0 THEN 0
                             WHEN @AllBack = 1 THEN @BillDiscount - @GivenBack
                             ELSE ROUND(@BillDiscount * @Sub / @BillLines, 2) END;
        IF @Discount < 0 SET @Discount = 0;
        IF @Discount > @Sub SET @Discount = @Sub;
        SET @Net = @Sub - @Discount;

        IF @CheckOnly = 0
        BEGIN
            INSERT @Payments (LineNum, PayType, Amount, RefNo, Tendered) VALUES (1, @PayType, @Net, @RefNo, NULL);

            EXEC dbo.zf_sp_SaveInvoice @InvType = 2, @PriceType = 1, @CashierId = @CashierId, @Discount = @Discount,
                                       @Items = @Items, @Payments = @Payments, @InvoiceNo = @InvoiceNo OUTPUT;

            UPDATE dbo.zf_tb_Invoice SET RefInvoiceNo = @RefInvoiceNo WHERE InvoiceNo = @InvoiceNo;

            UPDATE r SET RefLineNum = mp.RefLineNum, UnitCost = o.UnitCost, MktPrice = o.MktPrice
            FROM dbo.zf_tb_InvoiceItem r
            JOIN @Map mp ON mp.LineNum = r.LineNum
            JOIN dbo.zf_tb_InvoiceItem o ON o.InvoiceNo = @RefInvoiceNo AND o.LineNum = mp.RefLineNum
            WHERE r.InvoiceNo = @InvoiceNo;
        END
    COMMIT;

    SELECT @InvoiceNo AS InvoiceNo, @RefInvoiceNo AS RefInvoiceNo, @Sub AS LinesAmount, @Discount AS Discount, @Net AS NetAmount;

    SELECT mp.RefLineNum, i.LineNum, i.ItemId,
           COALESCE(i.LineDescrip, m.Inv_Descrip, m.Descrip, N'Item ' + CAST(i.ItemId AS NVARCHAR(20))) AS Name,
           i.Qty, i.UnitPrice, i.Discount, i.Amount
    FROM @Items i
    JOIN @Map mp ON mp.LineNum = i.LineNum
    LEFT JOIN dbo.zf_tb_Item m ON m.ItemId = i.ItemId AND i.ItemId <> 0
    ORDER BY i.LineNum;
END
GO

-- Records a cash drawer opening: @Kind 1 after a bill paid in cash, 2 No Sale, 3 opening cash, 4 paid in, 5 paid out.
-- Rows are never changed.
CREATE PROCEDURE dbo.zf_sp_LogDrawer
    @Kind      INT,
    @InvoiceNo VARCHAR(30) = NULL,
    @CashierId VARCHAR(20) = NULL,
    @Reason    NVARCHAR(100) = NULL,
    @Opened    BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    IF @Kind NOT BETWEEN 1 AND 5
        THROW 51042, 'Drawer Kind must be 1 bill, 2 No Sale, 3 opening cash, 4 paid in or 5 paid out.', 1;
    INSERT dbo.zf_tb_DrawerLog (Kind, InvoiceNo, CashierId, Reason, Opened)
    VALUES (@Kind, @InvoiceNo, @CashierId, NULLIF(LTRIM(RTRIM(@Reason)), N''), @Opened);
END
GO

-- Opening cash / paid in / paid out (zf_tb_CashMovement) into the open Z — opens a Z when none is open, so the float
-- can be entered before the first bill. Opening cash: one per Z; typed again before the Z's first bill it replaces the
-- old one (Status 9), after a bill it is refused (51051 — use paid in / paid out). Paid out needs a reason.
-- Paid out can't take more cash than the drawer should hold (51054). Returns the new row.
CREATE PROCEDURE dbo.zf_sp_AddCashMovement
    @Kind      INT,
    @Amount    DECIMAL(18,2),
    @Reason    NVARCHAR(100) = NULL,
    @CashierId VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ZNo INT, @MoveId INT, @Msg NVARCHAR(200);
    SET @Reason = NULLIF(LTRIM(RTRIM(@Reason)), N'');

    IF @Kind NOT IN (1, 2, 3)
        THROW 51050, 'Kind must be 1 (opening cash), 2 (paid in) or 3 (paid out).', 1;
    IF @Amount IS NULL OR @Amount <= 0
        THROW 51052, 'Enter an amount above 0.', 1;
    IF @Kind = 3 AND @Reason IS NULL
        THROW 51053, 'Enter a reason for the paid out.', 1;

    BEGIN TRAN;
        EXEC dbo.zf_sp_OpenZ @CashierId = @CashierId, @ZNo = @ZNo OUTPUT, @Silent = 1;

        IF @Kind = 1 AND EXISTS (SELECT 1 FROM dbo.zf_tb_CashMovement WITH (UPDLOCK, HOLDLOCK) WHERE ZNo = @ZNo AND Kind = 1 AND Status = 1)
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.zf_tb_Invoice WHERE ZNo = @ZNo)
            BEGIN
                SET @Msg = N'Opening cash for Z ' + CAST(@ZNo AS NVARCHAR(10)) + N' is already entered and bills are made. Use Paid In or Paid Out.';
                THROW 51051, @Msg, 1;
            END
            UPDATE dbo.zf_tb_CashMovement SET Status = 9 WHERE ZNo = @ZNo AND Kind = 1 AND Status = 1;
        END

        IF @Kind = 3
        BEGIN
            DECLARE @InDrawer DECIMAL(18,2) =
                  ISNULL((SELECT SUM(CASE Kind WHEN 3 THEN -Amount ELSE Amount END) FROM dbo.zf_tb_CashMovement
                          WHERE ZNo = @ZNo AND Status = 1), 0)
                + ISNULL((SELECT SUM(CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END)
                          FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                          WHERE i.ZNo = @ZNo AND i.Status <> 9 AND p.PayType = 1), 0);
            IF @Amount > @InDrawer
            BEGIN
                SET @Msg = N'Paid out is more than the cash in the drawer (Rs ' + CONVERT(NVARCHAR(30), @InDrawer) + N').';
                THROW 51054, @Msg, 1;
            END
        END

        INSERT dbo.zf_tb_CashMovement (ZNo, Kind, Amount, Reason, CashierId)
        VALUES (@ZNo, @Kind, @Amount, @Reason, @CashierId);
        SET @MoveId = SCOPE_IDENTITY();
    COMMIT;

    SELECT MoveId, ZNo, Kind, Amount, Reason, CashierId, CreatedAt FROM dbo.zf_tb_CashMovement WHERE MoveId = @MoveId;
END
GO

-- Drawer cash of the open Z (same rules as zf_sp_CloseZ). 2 result sets: the totals (no rows when no Z is open),
-- then the Z's movements (replaced opening cash included, Status 9).
CREATE PROCEDURE dbo.zf_sp_GetCashSummary
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ZNo INT = (SELECT MAX(ZNo) FROM dbo.zf_tb_ZReport WHERE Status = 0);

    SELECT z.ZNo, z.OpenedAt, t.OpeningCash, t.HasOpeningCash, t.PaidIn, t.PaidOut, c.CashSales,
           t.OpeningCash + c.CashSales + t.PaidIn - t.PaidOut AS ExpectedCash
    FROM dbo.zf_tb_ZReport z
    CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN Kind = 1 THEN Amount END), 0) AS OpeningCash,
                        CAST(ISNULL(MAX(CASE WHEN Kind = 1 THEN 1 ELSE 0 END), 0) AS BIT) AS HasOpeningCash,
                        ISNULL(SUM(CASE WHEN Kind = 2 THEN Amount END), 0) AS PaidIn,
                        ISNULL(SUM(CASE WHEN Kind = 3 THEN Amount END), 0) AS PaidOut
                 FROM dbo.zf_tb_CashMovement WHERE ZNo = z.ZNo AND Status = 1) t
    CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END), 0) AS CashSales
                 FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                 WHERE i.ZNo = z.ZNo AND i.Status <> 9 AND p.PayType = 1) c
    WHERE z.ZNo = @ZNo;

    SELECT MoveId, ZNo, Kind, Amount, Reason, CashierId, CreatedAt, Status
    FROM dbo.zf_tb_CashMovement WHERE ZNo = @ZNo ORDER BY MoveId;
END
GO

-- X report: the totals of the OPEN Z as zf_sp_CloseZ would store them right now - read only, nothing is closed or
-- changed. Same columns as the zf_sp_CloseZ answer (ClosedAt NULL, Status 0); no rows when no Z is open.
-- The rules here must match zf_sp_CloseZ.
CREATE PROCEDURE dbo.zf_sp_GetXReport
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ZNo INT = (SELECT MAX(ZNo) FROM dbo.zf_tb_ZReport WHERE Status = 0);

    SELECT z.ZNo, z.BusinessDate, z.CashierId, z.OpenedAt, CAST(NULL AS DATETIME) AS ClosedAt, z.FromSeq, z.ToSeq,
           b.InvoiceCount, l.LineCount, l.TotalQty, b.SalesAmount, b.RefundAmount,
           b.SalesAmount - b.RefundAmount AS NetSales,
           p.CashAmount, p.CardAmount, p.OtherAmount, p.BankAmount, p.ChequeAmount, m.OpeningCash, m.PaidIn, m.PaidOut,
           m.OpeningCash + p.CashAmount + m.PaidIn - m.PaidOut AS ExpectedCash, z.Status
    FROM dbo.zf_tb_ZReport z
    CROSS APPLY (SELECT COUNT(*) AS InvoiceCount,
                        ISNULL(SUM(CASE WHEN Status <> 9 AND InvType = 1 THEN NetAmount END), 0) AS SalesAmount,
                        ISNULL(SUM(CASE WHEN Status <> 9 AND InvType = 2 THEN NetAmount END), 0) AS RefundAmount
                 FROM dbo.zf_tb_Invoice WHERE ZNo = z.ZNo) b
    CROSS APPLY (SELECT COUNT(*) AS LineCount,
                        ISNULL(SUM(CASE WHEN i.InvType = 2 THEN -it.Qty ELSE it.Qty END), 0) AS TotalQty
                 FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoiceItem it ON it.InvoiceNo = i.InvoiceNo
                 WHERE i.ZNo = z.ZNo AND i.Status <> 9) l
    CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN x.PayType = 1 THEN x.Amount END), 0) AS CashAmount,
                        ISNULL(SUM(CASE WHEN x.PayType = 2 THEN x.Amount END), 0) AS CardAmount,
                        ISNULL(SUM(CASE WHEN x.PayType NOT IN (1, 2) THEN x.Amount END), 0) AS OtherAmount,
                        ISNULL(SUM(CASE WHEN x.PayType = 5 THEN x.Amount END), 0) AS BankAmount,
                        ISNULL(SUM(CASE WHEN x.PayType = 6 THEN x.Amount END), 0) AS ChequeAmount
                 FROM (SELECT p.PayType, CASE WHEN i.InvType = 2 THEN -p.Amount ELSE p.Amount END AS Amount
                       FROM dbo.zf_tb_Invoice i JOIN dbo.zf_tb_InvoicePayment p ON p.InvoiceNo = i.InvoiceNo
                       WHERE i.ZNo = z.ZNo AND i.Status <> 9) x) p
    CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN Kind = 1 THEN Amount END), 0) AS OpeningCash,
                        ISNULL(SUM(CASE WHEN Kind = 2 THEN Amount END), 0) AS PaidIn,
                        ISNULL(SUM(CASE WHEN Kind = 3 THEN Amount END), 0) AS PaidOut
                 FROM dbo.zf_tb_CashMovement WHERE ZNo = z.ZNo AND Status = 1) m
    WHERE z.ZNo = @ZNo;
END
GO

/* ---------------------------------------------------------------------------
   Cashier sign-in (2026-10-09, Docs/StockSystem.md §6.12)
   Users downloaded from the back office (api/Sync/Cashiers, needs Sync:TerminalKey) so a cashier can sign in while the
   till is offline. TillService checks the password against PasswordHash (PBKDF2, made by ItemApi); SQL never sees a
   password. CanUseTill 0 (disabled, or role "Back office") → sign-in refused, no hash kept. Self-contained section:
   its own type and procs are dropped and recreated here.
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.zf_tb_Cashier', 'U') IS NULL
CREATE TABLE dbo.zf_tb_Cashier (
    UserId        INT           NOT NULL CONSTRAINT PK_zf_tb_Cashier PRIMARY KEY,
    LoginName     VARCHAR(50)   NOT NULL,
    UserName      NVARCHAR(100) NULL,
    RoleId        INT           NULL,             -- 1 Admin, 3 Cashier (2 Back office never has CanUseTill)
    CanUseTill    BIT           NOT NULL,
    PasswordHash  VARCHAR(255)  NULL,
    UpdatedDate   DATETIME      NULL              -- back office time of the last change
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_zf_tb_Cashier_Login')
    CREATE UNIQUE INDEX UX_zf_tb_Cashier_Login ON dbo.zf_tb_Cashier (LoginName);
GO
IF COL_LENGTH('dbo.zf_tb_Config', 'LastCashierSyncAt') IS NULL
    ALTER TABLE dbo.zf_tb_Config ADD LastCashierSyncAt DATETIME NULL;   -- SERVER time of the last cashier download
GO

IF OBJECT_ID('dbo.zf_sp_UpsertCashiers', 'P') IS NOT NULL DROP PROCEDURE dbo.zf_sp_UpsertCashiers;
IF OBJECT_ID('dbo.zf_sp_GetCashier', 'P')     IS NOT NULL DROP PROCEDURE dbo.zf_sp_GetCashier;
GO
IF TYPE_ID('dbo.zf_tt_Cashier') IS NOT NULL DROP TYPE dbo.zf_tt_Cashier;
GO
CREATE TYPE dbo.zf_tt_Cashier AS TABLE (
    UserId        INT           NOT NULL PRIMARY KEY,
    LoginName     VARCHAR(50)   NOT NULL,
    UserName      NVARCHAR(100) NULL,
    RoleId        INT           NULL,
    CanUseTill    BIT           NOT NULL,
    PasswordHash  VARCHAR(255)  NULL,
    UpdatedDate   DATETIME      NULL
);
GO

CREATE PROCEDURE dbo.zf_sp_UpsertCashiers
    @Rows        dbo.zf_tt_Cashier READONLY,
    @ServerTime  DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRAN;
        -- a login name that moved to another user id (rare) — drop the old row first so the unique index holds
        DELETE t FROM dbo.zf_tb_Cashier t
        JOIN @Rows s ON s.LoginName = t.LoginName AND s.UserId <> t.UserId;

        UPDATE t SET LoginName = s.LoginName, UserName = s.UserName, RoleId = s.RoleId, CanUseTill = s.CanUseTill,
                     PasswordHash = CASE WHEN s.CanUseTill = 1 THEN s.PasswordHash END, UpdatedDate = s.UpdatedDate
        FROM dbo.zf_tb_Cashier t JOIN @Rows s ON s.UserId = t.UserId;

        INSERT dbo.zf_tb_Cashier (UserId, LoginName, UserName, RoleId, CanUseTill, PasswordHash, UpdatedDate)
        SELECT s.UserId, s.LoginName, s.UserName, s.RoleId, s.CanUseTill,
               CASE WHEN s.CanUseTill = 1 THEN s.PasswordHash END, s.UpdatedDate
        FROM @Rows s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.zf_tb_Cashier t WHERE t.UserId = s.UserId);

        UPDATE dbo.zf_tb_Config SET LastCashierSyncAt = @ServerTime WHERE Id = 1;
    COMMIT;
END
GO

-- One user by login name (any case), for sign-in. Second result set: how many users may sign in on this till
-- (0 = the cashier list was never downloaded — connect to the back office and press Reload).
CREATE PROCEDURE dbo.zf_sp_GetCashier
    @LoginName VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT UserId, LoginName, UserName, RoleId, CanUseTill, PasswordHash
    FROM dbo.zf_tb_Cashier WHERE LoginName = LTRIM(RTRIM(@LoginName));

    SELECT COUNT(*) AS TillUsers FROM dbo.zf_tb_Cashier WHERE CanUseTill = 1;
END
GO
