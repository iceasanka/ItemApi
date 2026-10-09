/* =============================================================================
   06_BackOffice_SalesDoc.sql
   Run on: back office db (easyway). Prefix z_. Re-runnable.
   Customers + Quotations and Invoices made in the back office, printed as A4 PDF.
   API: api/Customer (CustomerController), api/SalesDoc (SalesDocController). Docs/StockSystem.md §6.11.

   DOCUMENT ONLY: a quotation or invoice here does NOT move stock and does NOT make a customer balance.
   (Till bills are z_tb_SalesInvoice — a different thing.) No tax.
     - DocType 1 quotation (QT000001…), 2 invoice (INV000001…). Numbers from z_tb_SalesDocCounter, never reused.
     - Status 1 open, 2 invoiced (quotation turned into an invoice — FromDocId on the invoice), 9 cancelled.
     - Customer name / address / phone are COPIED onto the document, so a reprint never changes when the customer
       is edited later, and a one-off customer needs no customer record (CustomerId NULL).
     - Line ItemId 0 = a line typed by hand (service, item not in the list); Descrip is always stored.
   easyway is at compatibility level 100 (SQL 2008): no IIF / FORMAT / CONCAT / SEQUENCE.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Simple on purpose: one address line, one phone. Status 1 active, 0 deleted.
IF OBJECT_ID('dbo.z_tb_Customer', 'U') IS NULL
CREATE TABLE dbo.z_tb_Customer (
    CustomerId  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    Name        NVARCHAR(100) NOT NULL,
    Address     NVARCHAR(200) NULL,
    Phone       NVARCHAR(20)  NULL,
    Email       NVARCHAR(100) NULL,
    Status      INT           NOT NULL DEFAULT 1,
    UserId      INT           NULL,
    CDate       DATETIME      NOT NULL DEFAULT GETDATE(),
    UDate       DATETIME      NOT NULL DEFAULT GETDATE()
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_Customer_Name')
    CREATE INDEX IX_z_tb_Customer_Name ON dbo.z_tb_Customer (Name);
GO

IF OBJECT_ID('dbo.z_tb_SalesDocCounter', 'U') IS NULL
CREATE TABLE dbo.z_tb_SalesDocCounter (
    DocType  INT          NOT NULL PRIMARY KEY,
    Prefix   NVARCHAR(10) NOT NULL,
    LastNo   INT          NOT NULL DEFAULT 0
);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_SalesDocCounter WHERE DocType = 1)
    INSERT INTO dbo.z_tb_SalesDocCounter (DocType, Prefix, LastNo) VALUES (1, N'QT', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_SalesDocCounter WHERE DocType = 2)
    INSERT INTO dbo.z_tb_SalesDocCounter (DocType, Prefix, LastNo) VALUES (2, N'INV', 0);
GO

IF OBJECT_ID('dbo.z_tb_SalesDoc', 'U') IS NULL
CREATE TABLE dbo.z_tb_SalesDoc (
    DocId         INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    DocType       INT           NOT NULL,             -- 1 quotation, 2 invoice
    DocNo         NVARCHAR(20)  NOT NULL,
    DocDate       DATE          NOT NULL,
    ValidUntil    DATE          NULL,                 -- quotations
    CustomerId    INT           NULL,
    CustName      NVARCHAR(100) NOT NULL,
    CustAddress   NVARCHAR(200) NULL,
    CustPhone     NVARCHAR(20)  NULL,
    Reference     NVARCHAR(50)  NULL,                 -- customer's PO / ref
    Notes         NVARCHAR(500) NULL,                 -- printed under the lines
    GrossAmount   DECIMAL(18,2) NOT NULL,             -- sum of line amounts
    Discount      DECIMAL(18,2) NOT NULL DEFAULT 0,   -- document discount
    NetAmount     DECIMAL(18,2) NOT NULL,
    Status        INT           NOT NULL DEFAULT 1,   -- 1 open, 2 invoiced, 9 cancelled
    FromDocId     INT           NULL,                 -- invoice made from this quotation
    CancelReason  NVARCHAR(200) NULL,
    LocationId    INT           NOT NULL,
    UserId        INT           NULL,
    CDate         DATETIME      NOT NULL DEFAULT GETDATE(),
    UDate         DATETIME      NOT NULL DEFAULT GETDATE()
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_z_tb_SalesDoc_DocNo')
    CREATE UNIQUE INDEX UX_z_tb_SalesDoc_DocNo ON dbo.z_tb_SalesDoc (DocNo);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_SalesDoc_TypeDate')
    CREATE INDEX IX_z_tb_SalesDoc_TypeDate ON dbo.z_tb_SalesDoc (DocType, DocDate);
GO

IF OBJECT_ID('dbo.z_tb_SalesDocItem', 'U') IS NULL
CREATE TABLE dbo.z_tb_SalesDocItem (
    DocItemId  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    DocId      INT           NOT NULL REFERENCES dbo.z_tb_SalesDoc (DocId),
    LineNum    INT           NOT NULL,
    ItemId     INT           NOT NULL DEFAULT 0,      -- 0 = typed by hand
    Descrip    NVARCHAR(200) NOT NULL,
    Qty        DECIMAL(18,3) NOT NULL,
    UnitPrice  DECIMAL(18,2) NOT NULL,
    Discount   DECIMAL(18,2) NOT NULL DEFAULT 0,      -- line discount (amount)
    Amount     DECIMAL(18,2) NOT NULL                 -- Qty × UnitPrice − Discount
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_z_tb_SalesDocItem_Doc')
    CREATE INDEX IX_z_tb_SalesDocItem_Doc ON dbo.z_tb_SalesDocItem (DocId, LineNum);
GO

-- Company details printed on the PDF header and the default terms. One row (Id 1).
IF OBJECT_ID('dbo.z_tb_SalesDocSetting', 'U') IS NULL
CREATE TABLE dbo.z_tb_SalesDocSetting (
    Id                  INT            NOT NULL PRIMARY KEY,
    CompanyName         NVARCHAR(100)  NOT NULL,
    CompanyAddress      NVARCHAR(200)  NULL,
    CompanyPhone        NVARCHAR(50)   NULL,
    CompanyEmail        NVARCHAR(100)  NULL,
    LogoFile            NVARCHAR(100)  NULL,          -- file name under Uploads/ on the API server
    QuotationValidDays  INT            NOT NULL DEFAULT 14,
    QuotationTerms      NVARCHAR(1000) NULL,
    InvoiceTerms        NVARCHAR(1000) NULL,
    UserId              INT            NULL,
    UDate               DATETIME       NOT NULL DEFAULT GETDATE()
);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_SalesDocSetting WHERE Id = 1)
    INSERT INTO dbo.z_tb_SalesDocSetting (Id, CompanyName, QuotationValidDays, QuotationTerms, InvoiceTerms)
    VALUES (1, N'My Company', 14,
            N'Prices are valid until the date shown above. Subject to stock availability.',
            N'Thank you for your business.');
GO
