/* =============================================================================
   01_BackOffice_Stock.sql
   Run on: BACK OFFICE database (easyway)            Prefix: z_ (tables z_tb_, types z_tt_, procs z_sp_)
   Safe to re-run: tables are created only if missing; types and procs are dropped and recreated.

   Stock is a LEDGER. Every movement is one row in z_tb_StockLedger (+ in, - out), rows are never
   updated or deleted. z_tb_StockBalance is the running total, updated in the same transaction by
   z_sp_PostStockMovements — the ONLY proc that writes to either table.

   TxnType  1 GRN (+)   2 PRN (-)   3 Sale (-)   4 Sale refund (+)   5 Adjustment (+/-)   7 Opening (+/-)

   Database compatibility level is 100 (SQL 2008), so no OPENJSON / window running totals here;
   batches are passed as table-valued parameters (z_tt_*).
   See Docs/StockSystem.md for the full design.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;   -- required for the filtered index (sqlcmd defaults it to OFF)
GO

/* ---------------------------------------------------------------------------
   0. Counters — ADJNO for stock adjustment numbers (ADJ00000001), next to PNO / PRNO
   --------------------------------------------------------------------------- */
IF COL_LENGTH('dbo.z_tb_System', 'ADJNO') IS NULL
    ALTER TABLE dbo.z_tb_System ADD ADJNO INT NOT NULL CONSTRAINT DF_z_tb_System_ADJNO DEFAULT (0);
GO

/* ---------------------------------------------------------------------------
   1. Tables
   --------------------------------------------------------------------------- */

-- Cashier tills. A till must be registered here before it can sync.
IF OBJECT_ID('dbo.z_tb_Terminal', 'U') IS NULL
CREATE TABLE dbo.z_tb_Terminal (
    TerminalId      INT          NOT NULL CONSTRAINT PK_z_tb_Terminal PRIMARY KEY,  -- 1, 2, 3 ... fixed per till
    TerminalCode    VARCHAR(10)  NOT NULL,                                          -- 'T01' = invoice number prefix
    LocationId      INT          NOT NULL,
    TerminalName    VARCHAR(50)  NULL,
    Status          INT          NOT NULL CONSTRAINT DF_z_tb_Terminal_Status DEFAULT (1),   -- 1 active, 0 disabled (sync refused)
    LastZNo         INT          NOT NULL CONSTRAINT DF_z_tb_Terminal_LastZNo DEFAULT (0),  -- last reconciled Z
    LastSyncAt      DATETIME     NULL,   -- last invoice upload
    LastItemSyncAt  DATETIME     NULL,   -- last item/price download
    CDate           DATETIME     NOT NULL CONSTRAINT DF_z_tb_Terminal_CDate DEFAULT (GETDATE()),
    CONSTRAINT UQ_z_tb_Terminal_Code UNIQUE (TerminalCode)
);
GO

-- Every stock movement. Insert-only.
IF OBJECT_ID('dbo.z_tb_StockLedger', 'U') IS NULL
    CREATE TABLE dbo.z_tb_StockLedger (
        LedgerId    BIGINT        IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_StockLedger PRIMARY KEY,
        LocationId  INT           NOT NULL,
        ItemId      INT           NOT NULL,   -- z_tb_Item.ItemId
        TxnType     INT           NOT NULL,   -- see header
        DocNo       VARCHAR(30)   NOT NULL,   -- GRN00000001 / PRN00000001 / ADJ00000001 / T01-00000123
        DocLineNo   INT           NOT NULL,
        TerminalId  INT           NULL,       -- sales/refunds only
        ZNo         INT           NULL,       -- sales/refunds only
        Qty         DECIMAL(18,3) NOT NULL,   -- signed
        CostPrice   DECIMAL(18,2) NULL,
        SellPrice   DECIMAL(18,2) NULL,       -- price actually charged (sales)
        TxnDate     DATETIME      NOT NULL,   -- when it happened (till time for sales)
        CDate       DATETIME      NOT NULL CONSTRAINT DF_z_tb_StockLedger_CDate DEFAULT (GETDATE()),  -- when the server stored it
        UserId      VARCHAR(20)   NULL,
        -- one row per document line: re-sending the same document never double-counts
        CONSTRAINT UQ_z_tb_StockLedger_Doc UNIQUE (TxnType, DocNo, DocLineNo)
    );
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_StockLedger_Item')
    CREATE INDEX IX_z_tb_StockLedger_Item ON dbo.z_tb_StockLedger (LocationId, ItemId, TxnDate) INCLUDE (Qty);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_StockLedger_Z')
    CREATE INDEX IX_z_tb_StockLedger_Z ON dbo.z_tb_StockLedger (TerminalId, ZNo) WHERE TerminalId IS NOT NULL;
GO

-- Current stock = SUM(z_tb_StockLedger.Qty), kept up to date by z_sp_PostStockMovements.
IF OBJECT_ID('dbo.z_tb_StockBalance', 'U') IS NULL
    CREATE TABLE dbo.z_tb_StockBalance (
        LocationId    INT           NOT NULL,
        ItemId        INT           NOT NULL,
        Qty           DECIMAL(18,3) NOT NULL CONSTRAINT DF_z_tb_StockBalance_Qty DEFAULT (0),
        AvgCost       DECIMAL(18,2) NULL,   -- weighted average, moved by GRNs only
        LastLedgerId  BIGINT        NULL,
        UDate         DATETIME      NOT NULL CONSTRAINT DF_z_tb_StockBalance_UDate DEFAULT (GETDATE()),
        CONSTRAINT PK_z_tb_StockBalance PRIMARY KEY (LocationId, ItemId)
    );
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_StockBalance_UDate')
    CREATE INDEX IX_z_tb_StockBalance_UDate ON dbo.z_tb_StockBalance (LocationId, UDate);  -- till download "changed since"
GO

-- Adjustment reasons (UI drop-down)
IF OBJECT_ID('dbo.z_tb_StockAdjReason', 'U') IS NULL
CREATE TABLE dbo.z_tb_StockAdjReason (
    ReasonId    INT          NOT NULL CONSTRAINT PK_z_tb_StockAdjReason PRIMARY KEY,
    ReasonName  VARCHAR(50)  NOT NULL,
    Status      INT          NOT NULL CONSTRAINT DF_z_tb_StockAdjReason_Status DEFAULT (1)
);
GO
IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_StockAdjReason)
    INSERT dbo.z_tb_StockAdjReason (ReasonId, ReasonName) VALUES
        (1, 'Stock count'), (2, 'Damaged'), (3, 'Expired'), (4, 'Lost / Theft'),
        (5, 'Found'), (6, 'Own use'), (7, 'Opening stock'), (99, 'Other');
GO

-- Stock adjustment header (ADJ00000001). Posted immediately on save.
IF OBJECT_ID('dbo.z_tb_StockAdjustment', 'U') IS NULL
CREATE TABLE dbo.z_tb_StockAdjustment (
    AdjId          INT           IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_StockAdjustment PRIMARY KEY,
    AdjNo          VARCHAR(20)   NOT NULL,
    LocationId     INT           NOT NULL,
    AdjDate        DATETIME      NOT NULL,
    ReasonId       INT           NULL,
    Remark         VARCHAR(200)  NULL,
    LineCount      INT           NOT NULL,
    TotalAdjQty    DECIMAL(18,3) NOT NULL,
    TotalAdjValue  DECIMAL(18,2) NOT NULL,   -- SUM(AdjQty * AvgCost)
    Status         INT           NOT NULL CONSTRAINT DF_z_tb_StockAdjustment_Status DEFAULT (2),  -- 2 posted
    UserId         VARCHAR(20)   NULL,
    CDate          DATETIME      NOT NULL CONSTRAINT DF_z_tb_StockAdjustment_CDate DEFAULT (GETDATE()),
    CONSTRAINT UQ_z_tb_StockAdjustment_AdjNo UNIQUE (AdjNo)
);
GO

IF OBJECT_ID('dbo.z_tb_StockAdjustmentItem', 'U') IS NULL
CREATE TABLE dbo.z_tb_StockAdjustmentItem (
    AdjId       INT           NOT NULL,
    LineNum     INT           NOT NULL,
    ItemId      INT           NOT NULL,
    SystemQty   DECIMAL(18,3) NOT NULL,   -- server balance at the moment of posting
    CountedQty  DECIMAL(18,3) NULL,       -- set = "count mode" (AdjQty = CountedQty - SystemQty)
    AdjQty      DECIMAL(18,3) NOT NULL,   -- signed quantity posted to the ledger
    CostPrice   DECIMAL(18,2) NULL,
    ReasonId    INT           NULL,
    Remark      VARCHAR(100)  NULL,
    CONSTRAINT PK_z_tb_StockAdjustmentItem PRIMARY KEY (AdjId, LineNum)
);
GO

-- Sales uploaded from the tills
IF OBJECT_ID('dbo.z_tb_SalesInvoice', 'U') IS NULL
    CREATE TABLE dbo.z_tb_SalesInvoice (
        InvoiceId    INT           IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_SalesInvoice PRIMARY KEY,
        InvoiceNo    VARCHAR(30)   NOT NULL,   -- T01-00000123 (made on the till)
        TerminalId   INT           NOT NULL,
        LocationId   INT           NOT NULL,
        ZNo          INT           NOT NULL,
        InvoiceSeq   INT           NOT NULL,   -- 123 — used to find missing invoices at Z
        InvType      INT           NOT NULL,   -- 1 sale, 2 refund
        InvDate      DATETIME      NOT NULL,
        CashierId    VARCHAR(20)   NULL,
        GrossAmount  DECIMAL(18,2) NOT NULL,
        Discount     DECIMAL(18,2) NOT NULL,
        NetAmount    DECIMAL(18,2) NOT NULL,
        Status       INT           NOT NULL,   -- 1 completed, 9 cancelled (kept for numbering, no stock effect)
        CDate        DATETIME      NOT NULL CONSTRAINT DF_z_tb_SalesInvoice_CDate DEFAULT (GETDATE()),
        PriceType    INT           NOT NULL CONSTRAINT DF_z_tb_SalesInvoice_PriceType DEFAULT (1),   -- 1 retail, 2 = has wholesale line(s)
        CONSTRAINT UQ_z_tb_SalesInvoice_No  UNIQUE (InvoiceNo),
        CONSTRAINT UQ_z_tb_SalesInvoice_Seq UNIQUE (TerminalId, InvoiceSeq)
    );
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_SalesInvoice_Z')
    CREATE INDEX IX_z_tb_SalesInvoice_Z ON dbo.z_tb_SalesInvoice (TerminalId, ZNo);
GO

-- added with wholesale bills (2026-10-02) — databases created before get the column here
IF COL_LENGTH('dbo.z_tb_SalesInvoice', 'PriceType') IS NULL
    ALTER TABLE dbo.z_tb_SalesInvoice ADD PriceType INT NOT NULL CONSTRAINT DF_z_tb_SalesInvoice_PriceType DEFAULT (1);
GO

IF OBJECT_ID('dbo.z_tb_SalesInvoiceItem', 'U') IS NULL
CREATE TABLE dbo.z_tb_SalesInvoiceItem (
    InvoiceId  INT           NOT NULL,
    LineNum    INT           NOT NULL,
    ItemId     INT           NOT NULL,
    Qty        DECIMAL(18,3) NOT NULL,   -- always positive; InvType decides the direction
    UnitPrice  DECIMAL(18,2) NOT NULL,
    CostPrice  DECIMAL(18,2) NULL,       -- AvgCost at upload time (tills don't know cost)
    Discount   DECIMAL(18,2) NOT NULL,
    Amount     DECIMAL(18,2) NOT NULL,
    LineDescrip NVARCHAR(50) NULL,       -- "other item" (ItemId 0, not in the item list): what the cashier typed
    PriceType  INT           NOT NULL CONSTRAINT DF_z_tb_SalesInvoiceItem_PriceType DEFAULT (1),   -- 1 retail, 2 wholesale price on this line
    CONSTRAINT PK_z_tb_SalesInvoiceItem PRIMARY KEY (InvoiceId, LineNum)
);
GO

-- added with "other item" lines (2026-10-02) — databases created before get the column here
IF COL_LENGTH('dbo.z_tb_SalesInvoiceItem', 'LineDescrip') IS NULL
    ALTER TABLE dbo.z_tb_SalesInvoiceItem ADD LineDescrip NVARCHAR(50) NULL;
GO

-- added with per-line wholesale (2026-10-02)
IF COL_LENGTH('dbo.z_tb_SalesInvoiceItem', 'PriceType') IS NULL
    ALTER TABLE dbo.z_tb_SalesInvoiceItem ADD PriceType INT NOT NULL CONSTRAINT DF_z_tb_SalesInvoiceItem_PriceType DEFAULT (1);
GO

-- added with the sales dashboard (2026-10-06): the cost the till used for its profit view / discount cap
-- (zf_tb_InvoiceItem.UnitCost). Profit on the back office = this, else CostPrice (AvgCost), else the item cost now.
IF COL_LENGTH('dbo.z_tb_SalesInvoiceItem', 'TillUnitCost') IS NULL
    ALTER TABLE dbo.z_tb_SalesInvoiceItem ADD TillUnitCost DECIMAL(18,2) NULL;
GO

-- sales dashboard: bills by date
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_SalesInvoice_Date')
    CREATE INDEX IX_z_tb_SalesInvoice_Date ON dbo.z_tb_SalesInvoice (InvDate)
        INCLUDE (TerminalId, LocationId, InvType, Status, Discount, NetAmount);
GO

IF OBJECT_ID('dbo.z_tb_SalesPayment', 'U') IS NULL
CREATE TABLE dbo.z_tb_SalesPayment (
    InvoiceId  INT           NOT NULL,
    LineNum    INT           NOT NULL,
    PayType    INT           NOT NULL,   -- 1 cash, 2 card, 3 credit, 4 voucher
    Amount     DECIMAL(18,2) NOT NULL,
    RefNo      VARCHAR(30)   NULL,
    CONSTRAINT PK_z_tb_SalesPayment PRIMARY KEY (InvoiceId, LineNum)
);
GO

-- Z report = cashier day end. Till figures + what the server received (Srv*).
IF OBJECT_ID('dbo.z_tb_ZReport', 'U') IS NULL
CREATE TABLE dbo.z_tb_ZReport (
    ZId              INT           IDENTITY(1,1) NOT NULL CONSTRAINT PK_z_tb_ZReport PRIMARY KEY,
    TerminalId       INT           NOT NULL,
    ZNo              INT           NOT NULL,
    LocationId       INT           NOT NULL,
    BusinessDate     DATE          NOT NULL,
    CashierId        VARCHAR(20)   NULL,
    OpenedAt         DATETIME      NULL,
    ClosedAt         DATETIME      NULL,
    FromSeq          INT           NULL,   -- invoice sequence range of this Z
    ToSeq            INT           NULL,
    -- till figures
    InvoiceCount     INT           NOT NULL,   -- all invoices incl. cancelled
    LineCount        INT           NOT NULL,   -- lines of completed invoices
    TotalQty         DECIMAL(18,3) NOT NULL,   -- sold qty - refunded qty
    SalesAmount      DECIMAL(18,2) NOT NULL,
    RefundAmount     DECIMAL(18,2) NOT NULL,
    NetSales         DECIMAL(18,2) NOT NULL,   -- SalesAmount - RefundAmount
    CashAmount       DECIMAL(18,2) NOT NULL,
    CardAmount       DECIMAL(18,2) NOT NULL,
    OtherAmount      DECIMAL(18,2) NOT NULL,
    -- server figures (filled by z_sp_ReconcileZReport)
    SrvInvoiceCount  INT           NULL,
    SrvLineCount     INT           NULL,
    SrvTotalQty      DECIMAL(18,3) NULL,
    SrvNetSales      DECIMAL(18,2) NULL,
    MissingCount     INT           NULL,
    Status           INT           NOT NULL,   -- 2 received, 3 reconciled, 4 mismatch
    MismatchNote     VARCHAR(500)  NULL,
    SubmittedAt      DATETIME      NOT NULL CONSTRAINT DF_z_tb_ZReport_SubmittedAt DEFAULT (GETDATE()),
    ReconciledAt     DATETIME      NULL,
    CONSTRAINT UQ_z_tb_ZReport UNIQUE (TerminalId, ZNo)
);
GO

IF OBJECT_ID('dbo.z_tb_ZReportItem', 'U') IS NULL
CREATE TABLE dbo.z_tb_ZReportItem (
    ZId        INT           NOT NULL,
    ItemId     INT           NOT NULL,
    Qty        DECIMAL(18,3) NOT NULL,   -- till: net qty
    Amount     DECIMAL(18,2) NOT NULL,
    SrvQty     DECIMAL(18,3) NULL,       -- server: net qty
    SrvAmount  DECIMAL(18,2) NULL,
    CONSTRAINT PK_z_tb_ZReportItem PRIMARY KEY (ZId, ItemId)
);
GO

/* ---------------------------------------------------------------------------
   2. Drop procs, then types (procs depend on the types)
   --------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.z_sp_PostStockMovements', 'P')      IS NOT NULL DROP PROCEDURE dbo.z_sp_PostStockMovements;
IF OBJECT_ID('dbo.z_sp_PostPurchaseDoc', 'P')         IS NOT NULL DROP PROCEDURE dbo.z_sp_PostPurchaseDoc;
IF OBJECT_ID('dbo.z_sp_PostGrn', 'P')                 IS NOT NULL DROP PROCEDURE dbo.z_sp_PostGrn;
IF OBJECT_ID('dbo.z_sp_PostPrn', 'P')                 IS NOT NULL DROP PROCEDURE dbo.z_sp_PostPrn;
IF OBJECT_ID('dbo.z_sp_SaveStockAdjustment', 'P')     IS NOT NULL DROP PROCEDURE dbo.z_sp_SaveStockAdjustment;
IF OBJECT_ID('dbo.z_sp_SyncSalesInvoices', 'P')       IS NOT NULL DROP PROCEDURE dbo.z_sp_SyncSalesInvoices;
IF OBJECT_ID('dbo.z_sp_SubmitZReport', 'P')           IS NOT NULL DROP PROCEDURE dbo.z_sp_SubmitZReport;
IF OBJECT_ID('dbo.z_sp_ReconcileZReport', 'P')        IS NOT NULL DROP PROCEDURE dbo.z_sp_ReconcileZReport;
IF OBJECT_ID('dbo.z_sp_GetZMissingInvoices', 'P')     IS NOT NULL DROP PROCEDURE dbo.z_sp_GetZMissingInvoices;
IF OBJECT_ID('dbo.z_sp_GetItemsForSync', 'P')         IS NOT NULL DROP PROCEDURE dbo.z_sp_GetItemsForSync;
IF OBJECT_ID('dbo.z_sp_GetStockBalanceForSync', 'P')  IS NOT NULL DROP PROCEDURE dbo.z_sp_GetStockBalanceForSync;
GO
IF TYPE_ID('dbo.z_tt_StockMovement')    IS NOT NULL DROP TYPE dbo.z_tt_StockMovement;
IF TYPE_ID('dbo.z_tt_AdjustmentItem')   IS NOT NULL DROP TYPE dbo.z_tt_AdjustmentItem;
IF TYPE_ID('dbo.z_tt_SalesInvoice')     IS NOT NULL DROP TYPE dbo.z_tt_SalesInvoice;
IF TYPE_ID('dbo.z_tt_SalesInvoiceItem') IS NOT NULL DROP TYPE dbo.z_tt_SalesInvoiceItem;
IF TYPE_ID('dbo.z_tt_SalesPayment')     IS NOT NULL DROP TYPE dbo.z_tt_SalesPayment;
IF TYPE_ID('dbo.z_tt_ZReportItem')      IS NOT NULL DROP TYPE dbo.z_tt_ZReportItem;
GO

/* ---------------------------------------------------------------------------
   3. Table types (column order must match the DataTables built in AppDbContext.StockLedger.cs)
   --------------------------------------------------------------------------- */
CREATE TYPE dbo.z_tt_StockMovement AS TABLE (
    TxnType     INT           NOT NULL,
    DocNo       VARCHAR(30)   NOT NULL,
    DocLineNo   INT           NOT NULL,
    ItemId      INT           NOT NULL,
    Qty         DECIMAL(18,3) NOT NULL,
    CostPrice   DECIMAL(18,2) NULL,
    SellPrice   DECIMAL(18,2) NULL,
    TerminalId  INT           NULL,
    ZNo         INT           NULL,
    TxnDate     DATETIME      NOT NULL,
    PRIMARY KEY (TxnType, DocNo, DocLineNo)
);
GO
CREATE TYPE dbo.z_tt_AdjustmentItem AS TABLE (
    LineNum     INT           NOT NULL PRIMARY KEY,
    ItemId      INT           NOT NULL,
    CountedQty  DECIMAL(18,3) NULL,   -- count mode
    AdjQty      DECIMAL(18,3) NULL,   -- +/- mode (used when CountedQty is NULL)
    ReasonId    INT           NULL,
    Remark      VARCHAR(100)  NULL
);
GO
CREATE TYPE dbo.z_tt_SalesInvoice AS TABLE (
    InvoiceNo    VARCHAR(30)   NOT NULL PRIMARY KEY,
    InvoiceSeq   INT           NOT NULL,
    ZNo          INT           NOT NULL,
    InvType      INT           NOT NULL,
    InvDate      DATETIME      NOT NULL,
    CashierId    VARCHAR(20)   NULL,
    GrossAmount  DECIMAL(18,2) NOT NULL,
    Discount     DECIMAL(18,2) NOT NULL,
    NetAmount    DECIMAL(18,2) NOT NULL,
    Status       INT           NOT NULL,
    PriceType    INT           NOT NULL    -- 1 retail, 2 wholesale
);
GO
CREATE TYPE dbo.z_tt_SalesInvoiceItem AS TABLE (
    InvoiceNo  VARCHAR(30)   NOT NULL,
    LineNum    INT           NOT NULL,
    ItemId     INT           NOT NULL,
    Qty        DECIMAL(18,3) NOT NULL,
    UnitPrice  DECIMAL(18,2) NOT NULL,
    Discount   DECIMAL(18,2) NOT NULL,
    Amount     DECIMAL(18,2) NOT NULL,
    LineDescrip NVARCHAR(50) NULL,       -- only for ItemId 0 ("other item")
    PriceType  INT           NULL,       -- 1 retail, 2 wholesale; NULL (older tills) → the bill's PriceType
    UnitCost   DECIMAL(18,2) NULL,       -- the till's cost for this line; NULL (older tills / unknown)
    PRIMARY KEY (InvoiceNo, LineNum)
);
GO
CREATE TYPE dbo.z_tt_SalesPayment AS TABLE (
    InvoiceNo  VARCHAR(30)   NOT NULL,
    LineNum    INT           NOT NULL,
    PayType    INT           NOT NULL,
    Amount     DECIMAL(18,2) NOT NULL,
    RefNo      VARCHAR(30)   NULL,
    PRIMARY KEY (InvoiceNo, LineNum)
);
GO
CREATE TYPE dbo.z_tt_ZReportItem AS TABLE (
    ItemId  INT           NOT NULL PRIMARY KEY,
    Qty     DECIMAL(18,3) NOT NULL,
    Amount  DECIMAL(18,2) NOT NULL
);
GO

/* ---------------------------------------------------------------------------
   4. Procs
   --------------------------------------------------------------------------- */

-- The ONLY writer of z_tb_StockLedger / z_tb_StockBalance.
-- Skips lines already in the ledger (same TxnType+DocNo+DocLineNo), so callers can safely retry.
CREATE PROCEDURE dbo.z_sp_PostStockMovements
    @LocationId     INT,
    @UserId         VARCHAR(20) = NULL,
    @Moves          dbo.z_tt_StockMovement READONLY,
    @InsertedCount  INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ins TABLE (LedgerId BIGINT, ItemId INT, Qty DECIMAL(18,3), CostPrice DECIMAL(18,2), TxnType INT);

    BEGIN TRAN;

    INSERT dbo.z_tb_StockLedger
        (LocationId, ItemId, TxnType, DocNo, DocLineNo, TerminalId, ZNo, Qty, CostPrice, SellPrice, TxnDate, UserId)
    OUTPUT inserted.LedgerId, inserted.ItemId, inserted.Qty, inserted.CostPrice, inserted.TxnType INTO @ins
    SELECT @LocationId, m.ItemId, m.TxnType, m.DocNo, m.DocLineNo, m.TerminalId, m.ZNo, m.Qty, m.CostPrice, m.SellPrice, m.TxnDate, @UserId
    FROM @Moves m
    WHERE m.Qty <> 0
      AND NOT EXISTS (SELECT 1 FROM dbo.z_tb_StockLedger g WITH (UPDLOCK, HOLDLOCK)
                      WHERE g.TxnType = m.TxnType AND g.DocNo = m.DocNo AND g.DocLineNo = m.DocLineNo);

    SET @InsertedCount = @@ROWCOUNT;

    -- first movement of an item at this location creates its balance row
    INSERT dbo.z_tb_StockBalance (LocationId, ItemId, Qty)
    SELECT DISTINCT @LocationId, i.ItemId, 0
    FROM @ins i
    WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_StockBalance b WITH (UPDLOCK, HOLDLOCK)
                      WHERE b.LocationId = @LocationId AND b.ItemId = i.ItemId);

    -- Qty = Qty + movement (atomic, so two tills posting at once can't overwrite each other).
    -- AvgCost: weighted average over GRN lines that carry a cost; negative stock is treated as 0.
    UPDATE b SET
        AvgCost = CASE WHEN x.InQty > 0
                       THEN (CASE WHEN b.Qty > 0 THEN b.Qty * ISNULL(b.AvgCost, 0) ELSE 0 END + x.InValue)
                            / (CASE WHEN b.Qty > 0 THEN b.Qty ELSE 0 END + x.InQty)
                       ELSE b.AvgCost END,
        Qty          = b.Qty + x.Qty,
        LastLedgerId = x.LastLedgerId,
        UDate        = GETDATE()
    FROM dbo.z_tb_StockBalance b
    JOIN (SELECT ItemId,
                 SUM(Qty) AS Qty,
                 SUM(CASE WHEN TxnType = 1 AND CostPrice IS NOT NULL THEN Qty ELSE 0 END)             AS InQty,
                 SUM(CASE WHEN TxnType = 1 AND CostPrice IS NOT NULL THEN Qty * CostPrice ELSE 0 END) AS InValue,
                 MAX(LedgerId) AS LastLedgerId
          FROM @ins
          GROUP BY ItemId) x ON x.ItemId = b.ItemId
    WHERE b.LocationId = @LocationId;

    COMMIT;
END
GO

-- Posts a GRN (@Type 1, +Qty) or PRN (@Type 2, -Qty) from z_tb_TempPurchase into stock
-- and marks the summary + lines Status = 2 (posted). Posting twice is refused.
CREATE PROCEDURE dbo.z_sp_PostPurchaseDoc
    @DocNo   VARCHAR(20),
    @Type    INT,
    @UserId  VARCHAR(20) = NULL,
    @PostedLines INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LocationId INT, @Status INT, @PDate DATETIME, @Moves dbo.z_tt_StockMovement;

    SELECT @LocationId = ISNULL(LocationId, 1), @Status = Status, @PDate = PDate
    FROM dbo.z_tb_TempPurchaseSummary
    WHERE GrnNo = @DocNo AND ISNULL(Type, 1) = @Type;

    IF @@ROWCOUNT = 0
        THROW 50001, 'Document not found.', 1;
    IF @Status = 2
        THROW 50002, 'Document is already posted to stock.', 1;

    INSERT @Moves (TxnType, DocNo, DocLineNo, ItemId, Qty, CostPrice, SellPrice, TerminalId, ZNo, TxnDate)
    SELECT @Type,                                   -- TxnType 1 GRN / 2 PRN
           @DocNo,
           ROW_NUMBER() OVER (ORDER BY Idx),
           ItemId,
           CASE WHEN @Type = 2 THEN -ISNULL(Qty, 0) ELSE ISNULL(Qty, 0) END,
           CostPrice, SellPrice, NULL, NULL,
           ISNULL(@PDate, GETDATE())
    FROM dbo.z_tb_TempPurchase
    WHERE GrnNo = @DocNo AND ISNULL(Qty, 0) <> 0;

    IF NOT EXISTS (SELECT 1 FROM @Moves)
        THROW 50003, 'Document has no lines with quantity.', 1;

    BEGIN TRAN;
        EXEC dbo.z_sp_PostStockMovements @LocationId = @LocationId, @UserId = @UserId, @Moves = @Moves,
                                         @InsertedCount = @PostedLines OUTPUT;

        UPDATE dbo.z_tb_TempPurchaseSummary SET Status = 2, UDate = GETDATE()
        WHERE GrnNo = @DocNo AND ISNULL(Type, 1) = @Type;

        UPDATE dbo.z_tb_TempPurchase SET Status = 2, UDate = GETDATE()
        WHERE GrnNo = @DocNo;
    COMMIT;
END
GO

CREATE PROCEDURE dbo.z_sp_PostGrn
    @GrnNo VARCHAR(20), @UserId VARCHAR(20) = NULL, @PostedLines INT = NULL OUTPUT
AS
    EXEC dbo.z_sp_PostPurchaseDoc @DocNo = @GrnNo, @Type = 1, @UserId = @UserId, @PostedLines = @PostedLines OUTPUT;
GO

CREATE PROCEDURE dbo.z_sp_PostPrn
    @PrnNo VARCHAR(20), @UserId VARCHAR(20) = NULL, @PostedLines INT = NULL OUTPUT
AS
    EXEC dbo.z_sp_PostPurchaseDoc @DocNo = @PrnNo, @Type = 2, @UserId = @UserId, @PostedLines = @PostedLines OUTPUT;
GO

-- Saves AND posts a stock adjustment in one go. Can be run any time.
-- Per line: CountedQty set  -> AdjQty = CountedQty - current server balance (count mode)
--           CountedQty NULL -> AdjQty as given, + or - (quantity mode)
-- NOTE count mode: sales not yet uploaded from a till are not in the balance yet; they will be
-- deducted again when they arrive. Count while all tills are synced (UI warns — see docs).
CREATE PROCEDURE dbo.z_sp_SaveStockAdjustment
    @LocationId  INT,
    @AdjDate     DATETIME = NULL,
    @ReasonId    INT = NULL,
    @Remark      VARCHAR(200) = NULL,
    @UserId      VARCHAR(20) = NULL,
    @Items       dbo.z_tt_AdjustmentItem READONLY,
    @AdjNo       VARCHAR(20) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM @Items)
        THROW 50011, 'Add at least one line.', 1;
    IF EXISTS (SELECT 1 FROM @Items WHERE CountedQty IS NULL AND ISNULL(AdjQty, 0) = 0)
        THROW 50012, 'Each line needs a CountedQty or a non-zero AdjQty.', 1;
    IF EXISTS (SELECT 1 FROM @Items WHERE CountedQty < 0)
        THROW 50013, 'CountedQty cannot be negative.', 1;
    IF EXISTS (SELECT ItemId FROM @Items WHERE CountedQty IS NOT NULL GROUP BY ItemId HAVING COUNT(*) > 1)
        THROW 50014, 'An item can only be counted once per adjustment.', 1;
    IF EXISTS (SELECT 1 FROM @Items i WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_Item t WHERE t.ItemId = i.ItemId))
        THROW 50015, 'Unknown ItemId in adjustment lines.', 1;

    -- z_tb_System.LocaId is '01' style, LocationId is 1 style
    DECLARE @LocaCode VARCHAR(5) = RIGHT('00' + CAST(@LocationId AS VARCHAR(5)), 2),
            @Next INT, @AdjId INT, @Moves dbo.z_tt_StockMovement;
    DECLARE @lines TABLE (
        LineNum INT PRIMARY KEY, ItemId INT, SystemQty DECIMAL(18,3), CountedQty DECIMAL(18,3),
        AdjQty DECIMAL(18,3), CostPrice DECIMAL(18,2), ReasonId INT, Remark VARCHAR(100));

    SET @AdjDate = ISNULL(@AdjDate, GETDATE());

    BEGIN TRAN;
        UPDATE dbo.z_tb_System SET @Next = ADJNO = ADJNO + 1 WHERE LocaId = @LocaCode;
        IF @Next IS NULL
            THROW 50016, 'z_tb_System row not found for this location.', 1;
        SET @AdjNo = 'ADJ' + RIGHT('00000000' + CAST(@Next AS VARCHAR(10)), 8);   -- ADJ00000001

        -- lock the balances so SystemQty can't move until we post
        INSERT @lines
        SELECT i.LineNum, i.ItemId, ISNULL(b.Qty, 0), i.CountedQty,
               CASE WHEN i.CountedQty IS NOT NULL THEN i.CountedQty - ISNULL(b.Qty, 0) ELSE i.AdjQty END,
               b.AvgCost, ISNULL(i.ReasonId, @ReasonId), i.Remark
        FROM @Items i
        LEFT JOIN dbo.z_tb_StockBalance b WITH (UPDLOCK, HOLDLOCK)
               ON b.LocationId = @LocationId AND b.ItemId = i.ItemId;

        INSERT dbo.z_tb_StockAdjustment
            (AdjNo, LocationId, AdjDate, ReasonId, Remark, LineCount, TotalAdjQty, TotalAdjValue, Status, UserId)
        SELECT @AdjNo, @LocationId, @AdjDate, @ReasonId, @Remark,
               COUNT(*), SUM(AdjQty), SUM(AdjQty * ISNULL(CostPrice, 0)), 2, @UserId
        FROM @lines;
        SET @AdjId = SCOPE_IDENTITY();

        INSERT dbo.z_tb_StockAdjustmentItem
            (AdjId, LineNum, ItemId, SystemQty, CountedQty, AdjQty, CostPrice, ReasonId, Remark)
        SELECT @AdjId, LineNum, ItemId, SystemQty, CountedQty, AdjQty, CostPrice, ReasonId, Remark
        FROM @lines;

        INSERT @Moves (TxnType, DocNo, DocLineNo, ItemId, Qty, CostPrice, SellPrice, TerminalId, ZNo, TxnDate)
        SELECT 5, @AdjNo, LineNum, ItemId, AdjQty, CostPrice, NULL, NULL, NULL, @AdjDate
        FROM @lines
        WHERE AdjQty <> 0;   -- counted = system: recorded on the document, nothing to post

        EXEC dbo.z_sp_PostStockMovements @LocationId = @LocationId, @UserId = @UserId, @Moves = @Moves;
    COMMIT;
END
GO

-- Compares a Z report with the invoices the server has for that till + Z.
-- Status 3 reconciled / 4 mismatch. @Silent = 1 skips the result set (used from other procs).
CREATE PROCEDURE dbo.z_sp_ReconcileZReport
    @TerminalId INT,
    @ZNo        INT,
    @Silent     BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ZId INT, @FromSeq INT, @ToSeq INT,
            @InvoiceCount INT, @LineCount INT, @TotalQty DECIMAL(18,3), @NetSales DECIMAL(18,2),
            @SrvInvoiceCount INT, @SrvLineCount INT, @SrvTotalQty DECIMAL(18,3), @SrvNetSales DECIMAL(18,2),
            @Missing INT = 0, @ItemDiffs INT, @Status INT, @Note VARCHAR(500) = '';

    SELECT @ZId = ZId, @FromSeq = FromSeq, @ToSeq = ToSeq, @InvoiceCount = InvoiceCount,
           @LineCount = LineCount, @TotalQty = TotalQty, @NetSales = NetSales
    FROM dbo.z_tb_ZReport
    WHERE TerminalId = @TerminalId AND ZNo = @ZNo;

    IF @ZId IS NULL
        THROW 50031, 'Z report not found.', 1;

    SELECT @SrvInvoiceCount = COUNT(*),
           @SrvNetSales = ISNULL(SUM(CASE WHEN Status = 9 THEN 0
                                          WHEN InvType = 2 THEN -NetAmount ELSE NetAmount END), 0)
    FROM dbo.z_tb_SalesInvoice
    WHERE TerminalId = @TerminalId AND ZNo = @ZNo;

    DECLARE @agg TABLE (ItemId INT PRIMARY KEY, Qty DECIMAL(18,3), Amount DECIMAL(18,2));
    INSERT @agg
    SELECT it.ItemId,
           SUM(CASE WHEN s.InvType = 2 THEN -it.Qty ELSE it.Qty END),
           SUM(CASE WHEN s.InvType = 2 THEN -it.Amount ELSE it.Amount END)
    FROM dbo.z_tb_SalesInvoice s
    JOIN dbo.z_tb_SalesInvoiceItem it ON it.InvoiceId = s.InvoiceId
    WHERE s.TerminalId = @TerminalId AND s.ZNo = @ZNo AND s.Status <> 9
    GROUP BY it.ItemId;

    SELECT @SrvLineCount = COUNT(*)
    FROM dbo.z_tb_SalesInvoice s
    JOIN dbo.z_tb_SalesInvoiceItem it ON it.InvoiceId = s.InvoiceId
    WHERE s.TerminalId = @TerminalId AND s.ZNo = @ZNo AND s.Status <> 9;

    SELECT @SrvTotalQty = ISNULL(SUM(Qty), 0) FROM @agg;

    IF @FromSeq IS NOT NULL AND @ToSeq IS NOT NULL AND @ToSeq >= @FromSeq
        SELECT @Missing = (@ToSeq - @FromSeq + 1) - COUNT(*)
        FROM dbo.z_tb_SalesInvoice
        WHERE TerminalId = @TerminalId AND InvoiceSeq BETWEEN @FromSeq AND @ToSeq;

    BEGIN TRAN;
        -- per-item: server side next to the till side
        UPDATE zi SET SrvQty = ISNULL(a.Qty, 0), SrvAmount = ISNULL(a.Amount, 0)
        FROM dbo.z_tb_ZReportItem zi
        LEFT JOIN @agg a ON a.ItemId = zi.ItemId
        WHERE zi.ZId = @ZId;

        INSERT dbo.z_tb_ZReportItem (ZId, ItemId, Qty, Amount, SrvQty, SrvAmount)
        SELECT @ZId, a.ItemId, 0, 0, a.Qty, a.Amount
        FROM @agg a
        WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_ZReportItem zi WHERE zi.ZId = @ZId AND zi.ItemId = a.ItemId);

        SELECT @ItemDiffs = COUNT(*) FROM dbo.z_tb_ZReportItem
        WHERE ZId = @ZId AND (Qty <> SrvQty OR Amount <> SrvAmount);

        IF @SrvInvoiceCount <> @InvoiceCount SET @Note = @Note + 'Invoices till ' + CAST(@InvoiceCount AS VARCHAR(10)) + ' / server ' + CAST(@SrvInvoiceCount AS VARCHAR(10)) + '. ';
        IF @SrvLineCount    <> @LineCount    SET @Note = @Note + 'Lines till ' + CAST(@LineCount AS VARCHAR(10)) + ' / server ' + CAST(@SrvLineCount AS VARCHAR(10)) + '. ';
        IF @SrvTotalQty     <> @TotalQty     SET @Note = @Note + 'Qty till ' + CAST(@TotalQty AS VARCHAR(20)) + ' / server ' + CAST(@SrvTotalQty AS VARCHAR(20)) + '. ';
        IF @SrvNetSales     <> @NetSales     SET @Note = @Note + 'Net sales till ' + CAST(@NetSales AS VARCHAR(20)) + ' / server ' + CAST(@SrvNetSales AS VARCHAR(20)) + '. ';
        IF @Missing > 0                      SET @Note = @Note + CAST(@Missing AS VARCHAR(10)) + ' invoice(s) not received. ';
        IF @ItemDiffs > 0                    SET @Note = @Note + CAST(@ItemDiffs AS VARCHAR(10)) + ' item(s) differ. ';

        SET @Status = CASE WHEN @Note = '' THEN 3 ELSE 4 END;

        UPDATE dbo.z_tb_ZReport SET
            SrvInvoiceCount = @SrvInvoiceCount, SrvLineCount = @SrvLineCount,
            SrvTotalQty = @SrvTotalQty, SrvNetSales = @SrvNetSales, MissingCount = @Missing,
            Status = @Status,
            MismatchNote = NULLIF(RTRIM(@Note), ''),
            ReconciledAt = CASE WHEN @Status = 3 THEN GETDATE() ELSE NULL END
        WHERE ZId = @ZId;

        IF @Status = 3
            UPDATE dbo.z_tb_Terminal SET LastZNo = @ZNo WHERE TerminalId = @TerminalId AND LastZNo < @ZNo;
    COMMIT;

    IF @Silent = 0
        SELECT ZId, TerminalId, ZNo, BusinessDate, Status, InvoiceCount, SrvInvoiceCount, LineCount, SrvLineCount,
               TotalQty, SrvTotalQty, NetSales, SrvNetSales, ISNULL(MissingCount, 0) AS MissingCount, MismatchNote
        FROM dbo.z_tb_ZReport WHERE ZId = @ZId;
END
GO

-- Uploads a batch of invoices from ONE till. Invoices already on the server are skipped
-- (Result = 'Duplicate'), so a till can resend after a lost reply. Returns one row per invoice sent.
CREATE PROCEDURE dbo.z_sp_SyncSalesInvoices
    @TerminalId  INT,
    @Invoices    dbo.z_tt_SalesInvoice READONLY,
    @Items       dbo.z_tt_SalesInvoiceItem READONLY,
    @Payments    dbo.z_tt_SalesPayment READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LocationId INT, @TerminalCode VARCHAR(10), @Moves dbo.z_tt_StockMovement, @z INT;
    DECLARE @new TABLE (InvoiceNo VARCHAR(30) PRIMARY KEY);
    DECLARE @map TABLE (InvoiceId INT, InvoiceNo VARCHAR(30) PRIMARY KEY);

    SELECT @LocationId = LocationId, @TerminalCode = TerminalCode
    FROM dbo.z_tb_Terminal WHERE TerminalId = @TerminalId AND Status = 1;

    IF @LocationId IS NULL
        THROW 50021, 'Terminal is not registered or is disabled.', 1;
    IF EXISTS (SELECT 1 FROM @Invoices WHERE InvoiceNo NOT LIKE @TerminalCode + '-%')
        THROW 50022, 'Invoice number does not belong to this terminal.', 1;
    IF EXISTS (SELECT 1 FROM @Invoices WHERE InvType NOT IN (1, 2) OR Status NOT IN (1, 9) OR PriceType NOT IN (1, 2))
        THROW 50023, 'Invalid InvType, Status or PriceType.', 1;
    IF EXISTS (SELECT 1 FROM @Items WHERE PriceType NOT IN (1, 2))
        THROW 50023, 'Invalid line PriceType.', 1;

    BEGIN TRAN;
        INSERT @new
        SELECT i.InvoiceNo FROM @Invoices i
        WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_SalesInvoice s WITH (UPDLOCK, HOLDLOCK) WHERE s.InvoiceNo = i.InvoiceNo);

        INSERT dbo.z_tb_SalesInvoice
            (InvoiceNo, TerminalId, LocationId, ZNo, InvoiceSeq, InvType, InvDate, CashierId, GrossAmount, Discount, NetAmount, Status, PriceType)
        OUTPUT inserted.InvoiceId, inserted.InvoiceNo INTO @map
        SELECT i.InvoiceNo, @TerminalId, @LocationId, i.ZNo, i.InvoiceSeq, i.InvType, i.InvDate, i.CashierId,
               i.GrossAmount, i.Discount, i.NetAmount, i.Status, i.PriceType
        FROM @Invoices i JOIN @new n ON n.InvoiceNo = i.InvoiceNo;

        INSERT dbo.z_tb_SalesInvoiceItem (InvoiceId, LineNum, ItemId, Qty, UnitPrice, CostPrice, Discount, Amount, LineDescrip, PriceType, TillUnitCost)
        SELECT m.InvoiceId, it.LineNum, it.ItemId, it.Qty, it.UnitPrice, b.AvgCost, it.Discount, it.Amount,
               CASE WHEN it.ItemId = 0 THEN it.LineDescrip END,
               ISNULL(it.PriceType, inv.PriceType), it.UnitCost
        FROM @Items it
        JOIN @map m ON m.InvoiceNo = it.InvoiceNo
        JOIN @Invoices inv ON inv.InvoiceNo = it.InvoiceNo
        LEFT JOIN dbo.z_tb_StockBalance b ON b.LocationId = @LocationId AND b.ItemId = it.ItemId;

        INSERT dbo.z_tb_SalesPayment (InvoiceId, LineNum, PayType, Amount, RefNo)
        SELECT m.InvoiceId, p.LineNum, p.PayType, p.Amount, p.RefNo
        FROM @Payments p JOIN @map m ON m.InvoiceNo = p.InvoiceNo;

        -- stock: sale -Qty (TxnType 3), refund +Qty (TxnType 4); cancelled invoices don't move stock;
        -- "other item" lines (ItemId 0) are not in the item list, so they have no stock
        INSERT @Moves (TxnType, DocNo, DocLineNo, ItemId, Qty, CostPrice, SellPrice, TerminalId, ZNo, TxnDate)
        SELECT CASE WHEN i.InvType = 2 THEN 4 ELSE 3 END,
               i.InvoiceNo, it.LineNum, it.ItemId,
               CASE WHEN i.InvType = 2 THEN it.Qty ELSE -it.Qty END,
               b.AvgCost, it.UnitPrice, @TerminalId, i.ZNo, i.InvDate
        FROM @Invoices i
        JOIN @new n ON n.InvoiceNo = i.InvoiceNo
        JOIN @Items it ON it.InvoiceNo = i.InvoiceNo
        LEFT JOIN dbo.z_tb_StockBalance b ON b.LocationId = @LocationId AND b.ItemId = it.ItemId
        WHERE i.Status <> 9 AND it.ItemId <> 0;

        EXEC dbo.z_sp_PostStockMovements @LocationId = @LocationId, @Moves = @Moves;

        UPDATE dbo.z_tb_Terminal SET LastSyncAt = GETDATE() WHERE TerminalId = @TerminalId;
    COMMIT;

    -- late invoices for a Z that was a mismatch: check that Z again
    DECLARE zc CURSOR LOCAL FAST_FORWARD FOR
        SELECT DISTINCT z.ZNo
        FROM dbo.z_tb_ZReport z
        JOIN @Invoices i ON i.ZNo = z.ZNo
        JOIN @new n ON n.InvoiceNo = i.InvoiceNo
        WHERE z.TerminalId = @TerminalId AND z.Status = 4;
    OPEN zc;
    FETCH NEXT FROM zc INTO @z;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC dbo.z_sp_ReconcileZReport @TerminalId = @TerminalId, @ZNo = @z, @Silent = 1;
        FETCH NEXT FROM zc INTO @z;
    END
    CLOSE zc;
    DEALLOCATE zc;

    SELECT i.InvoiceNo, CASE WHEN n.InvoiceNo IS NULL THEN 'Duplicate' ELSE 'Inserted' END AS Result
    FROM @Invoices i
    LEFT JOIN @new n ON n.InvoiceNo = i.InvoiceNo;
END
GO

-- Till sends its Z at day end. Stored (or replaced, if not yet reconciled) and reconciled at once.
-- Returns the reconcile result row.
CREATE PROCEDURE dbo.z_sp_SubmitZReport
    @TerminalId    INT,
    @ZNo           INT,
    @BusinessDate  DATE,
    @CashierId     VARCHAR(20) = NULL,
    @OpenedAt      DATETIME = NULL,
    @ClosedAt      DATETIME = NULL,
    @FromSeq       INT = NULL,
    @ToSeq         INT = NULL,
    @InvoiceCount  INT,
    @LineCount     INT,
    @TotalQty      DECIMAL(18,3),
    @SalesAmount   DECIMAL(18,2),
    @RefundAmount  DECIMAL(18,2),
    @NetSales      DECIMAL(18,2),
    @CashAmount    DECIMAL(18,2) = 0,
    @CardAmount    DECIMAL(18,2) = 0,
    @OtherAmount   DECIMAL(18,2) = 0,
    @Items         dbo.z_tt_ZReportItem READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LocationId INT, @ZId INT, @Status INT;

    SELECT @LocationId = LocationId FROM dbo.z_tb_Terminal WHERE TerminalId = @TerminalId AND Status = 1;
    IF @LocationId IS NULL
        THROW 50021, 'Terminal is not registered or is disabled.', 1;

    BEGIN TRAN;
        SELECT @ZId = ZId, @Status = Status
        FROM dbo.z_tb_ZReport WITH (UPDLOCK, HOLDLOCK)
        WHERE TerminalId = @TerminalId AND ZNo = @ZNo;

        IF @ZId IS NULL
        BEGIN
            INSERT dbo.z_tb_ZReport
                (TerminalId, ZNo, LocationId, BusinessDate, CashierId, OpenedAt, ClosedAt, FromSeq, ToSeq,
                 InvoiceCount, LineCount, TotalQty, SalesAmount, RefundAmount, NetSales,
                 CashAmount, CardAmount, OtherAmount, Status)
            VALUES
                (@TerminalId, @ZNo, @LocationId, @BusinessDate, @CashierId, @OpenedAt, @ClosedAt, @FromSeq, @ToSeq,
                 @InvoiceCount, @LineCount, @TotalQty, @SalesAmount, @RefundAmount, @NetSales,
                 @CashAmount, @CardAmount, @OtherAmount, 2);
            SET @ZId = SCOPE_IDENTITY();
        END
        ELSE IF @Status <> 3   -- a reconciled Z is final; a resend is ignored
        BEGIN
            UPDATE dbo.z_tb_ZReport SET
                BusinessDate = @BusinessDate, CashierId = @CashierId, OpenedAt = @OpenedAt, ClosedAt = @ClosedAt,
                FromSeq = @FromSeq, ToSeq = @ToSeq, InvoiceCount = @InvoiceCount, LineCount = @LineCount,
                TotalQty = @TotalQty, SalesAmount = @SalesAmount, RefundAmount = @RefundAmount, NetSales = @NetSales,
                CashAmount = @CashAmount, CardAmount = @CardAmount, OtherAmount = @OtherAmount,
                Status = 2, SubmittedAt = GETDATE()
            WHERE ZId = @ZId;
            DELETE dbo.z_tb_ZReportItem WHERE ZId = @ZId;
        END

        IF @Status IS NULL OR @Status <> 3
            INSERT dbo.z_tb_ZReportItem (ZId, ItemId, Qty, Amount)
            SELECT @ZId, ItemId, Qty, Amount FROM @Items;
    COMMIT;

    IF @Status IS NULL OR @Status <> 3
        EXEC dbo.z_sp_ReconcileZReport @TerminalId = @TerminalId, @ZNo = @ZNo, @Silent = 1;

    SELECT ZId, TerminalId, ZNo, BusinessDate, Status, InvoiceCount, SrvInvoiceCount, LineCount, SrvLineCount,
           TotalQty, SrvTotalQty, NetSales, SrvNetSales, ISNULL(MissingCount, 0) AS MissingCount, MismatchNote
    FROM dbo.z_tb_ZReport WHERE ZId = @ZId;
END
GO

-- Invoice numbers inside a Z's sequence range that the server never received. The till resends these.
CREATE PROCEDURE dbo.z_sp_GetZMissingInvoices
    @TerminalId INT,
    @ZNo        INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FromSeq INT, @ToSeq INT, @TerminalCode VARCHAR(10);

    SELECT @FromSeq = z.FromSeq, @ToSeq = z.ToSeq, @TerminalCode = t.TerminalCode
    FROM dbo.z_tb_ZReport z
    JOIN dbo.z_tb_Terminal t ON t.TerminalId = z.TerminalId
    WHERE z.TerminalId = @TerminalId AND z.ZNo = @ZNo;

    IF @FromSeq IS NULL OR @ToSeq IS NULL OR @ToSeq < @FromSeq
    BEGIN
        SELECT CAST(NULL AS INT) AS InvoiceSeq, CAST(NULL AS VARCHAR(30)) AS InvoiceNo WHERE 1 = 0;
        RETURN;
    END

    ;WITH nums AS (
        SELECT TOP (@ToSeq - @FromSeq + 1)
               @FromSeq - 1 + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS Seq
        FROM sys.all_columns a CROSS JOIN sys.all_columns b
    )
    SELECT CAST(n.Seq AS INT) AS InvoiceSeq,   -- ROW_NUMBER() is bigint
           CAST(@TerminalCode + '-' + RIGHT('00000000' + CAST(n.Seq AS VARCHAR(10)), 8) AS VARCHAR(30)) AS InvoiceNo
    FROM nums n
    WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_SalesInvoice s WHERE s.TerminalId = @TerminalId AND s.InvoiceSeq = n.Seq)
    ORDER BY n.Seq;
END
GO

-- Items + prices for a till, changed since @Since (NULL = everything).
-- Caller should take the server time BEFORE calling and use it as the next @Since.
CREATE PROCEDURE dbo.z_sp_GetItemsForSync
    @TerminalId INT,
    @Since      DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LocationId INT;
    SELECT @LocationId = LocationId FROM dbo.z_tb_Terminal WHERE TerminalId = @TerminalId AND Status = 1;
    IF @LocationId IS NULL
        THROW 50021, 'Terminal is not registered or is disabled.', 1;

    SELECT i.ItemId, i.RefCode, i.Barcode, i.Descrip, i.Inv_Descrip, i.SinhalaDescrip,
           CAST(ISNULL(i.OpenPrice, 0) AS BIT) AS OpenPrice, i.MaxPrice,
           d.RetailPrice, d.WholesalePrice, d.SpecialPrice,
           CAST(ISNULL(d.IsSaleLocked, 0) AS BIT) AS IsSaleLocked,
           CAST(ISNULL(d.NoDiscount, 0) AS BIT)   AS NoDiscount,
           d.DiscountAmount, d.DiscountPercent,
           d.QtyLevel2, d.PriceLevel2, d.QtyLevel3, d.PriceLevel3, d.QtyLevel4, d.PriceLevel4,
           i.Status,
           CASE WHEN d.UDate > i.UDate THEN d.UDate ELSE i.UDate END AS UDate,  -- datetime2: some items have 0001-01-01
           d.CostPrice   -- till profit view + bill discount cap (shown on the till only with the supervisor PIN)
    FROM dbo.z_tb_Item i
    LEFT JOIN dbo.z_tb_ItemDet d ON d.ItemId = i.ItemId AND d.LocationId = @LocationId
    WHERE @Since IS NULL OR i.UDate > @Since OR d.UDate > @Since;

    UPDATE dbo.z_tb_Terminal SET LastItemSyncAt = GETDATE() WHERE TerminalId = @TerminalId;
END
GO

-- Stock balances for a till (display only — tills never block a sale on stock), changed since @Since.
CREATE PROCEDURE dbo.z_sp_GetStockBalanceForSync
    @TerminalId INT,
    @Since      DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LocationId INT;
    SELECT @LocationId = LocationId FROM dbo.z_tb_Terminal WHERE TerminalId = @TerminalId AND Status = 1;
    IF @LocationId IS NULL
        THROW 50021, 'Terminal is not registered or is disabled.', 1;

    SELECT ItemId, Qty, UDate
    FROM dbo.z_tb_StockBalance
    WHERE LocationId = @LocationId AND (@Since IS NULL OR UDate > @Since);
END
GO
