using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    // Customers + back office quotations and invoices (DBScript/06_BackOffice_SalesDoc.sql, Docs/StockSystem.md §6.11).
    // Document only: no stock movement, no customer balance, no tax.

    [Table("z_tb_Customer")]
    public class Customer
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int CustomerId { get; set; }
        [MaxLength(100)]
        public string Name { get; set; } = "";
        [MaxLength(200)]
        public string? Address { get; set; }
        [MaxLength(20)]
        public string? Phone { get; set; }
        [MaxLength(100)]
        public string? Email { get; set; }
        // 1 active, 0 deleted
        public int Status { get; set; } = 1;
        public int? UserId { get; set; }
        public DateTime CDate { get; set; }
        public DateTime UDate { get; set; }
    }

    [Table("z_tb_SalesDoc")]
    public class SalesDoc
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int DocId { get; set; }
        // 1 quotation, 2 invoice (SalesDocType)
        public int DocType { get; set; }
        public string DocNo { get; set; } = "";
        public DateTime DocDate { get; set; }
        public DateTime? ValidUntil { get; set; }
        public int? CustomerId { get; set; }
        public string CustName { get; set; } = "";
        public string? CustAddress { get; set; }
        public string? CustPhone { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal GrossAmount { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal Discount { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal NetAmount { get; set; }
        // 1 open, 2 invoiced (quotation), 9 cancelled (SalesDocStatus)
        public int Status { get; set; } = 1;
        public int? FromDocId { get; set; }
        public string? CancelReason { get; set; }
        public int LocationId { get; set; }
        public int? UserId { get; set; }
        public DateTime CDate { get; set; }
        public DateTime UDate { get; set; }

        public List<SalesDocItem> Items { get; set; } = new();
    }

    [Table("z_tb_SalesDocItem")]
    public class SalesDocItem
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int DocItemId { get; set; }
        public int DocId { get; set; }
        public int LineNum { get; set; }
        // 0 = typed by hand
        public int ItemId { get; set; }
        public string Descrip { get; set; } = "";
        [Column(TypeName = "decimal(18,3)")]
        public decimal Qty { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal UnitPrice { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal Discount { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal Amount { get; set; }
    }

    [Table("z_tb_SalesDocCounter")]
    public class SalesDocCounter
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.None)]
        public int DocType { get; set; }
        public string Prefix { get; set; } = "";
        public int LastNo { get; set; }
    }

    [Table("z_tb_SalesDocSetting")]
    public class SalesDocSetting
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.None)]
        public int Id { get; set; }
        [MaxLength(100)]
        public string CompanyName { get; set; } = "";
        [MaxLength(200)]
        public string? CompanyAddress { get; set; }
        [MaxLength(50)]
        public string? CompanyPhone { get; set; }
        [MaxLength(100)]
        public string? CompanyEmail { get; set; }
        public string? LogoFile { get; set; }
        public int QuotationValidDays { get; set; } = 14;
        [MaxLength(1000)]
        public string? QuotationTerms { get; set; }
        [MaxLength(1000)]
        public string? InvoiceTerms { get; set; }
        public int? UserId { get; set; }
        public DateTime UDate { get; set; }
    }

    public static class SalesDocType
    {
        public const int Quotation = 1;
        public const int Invoice = 2;
    }

    public static class SalesDocStatus
    {
        public const int Open = 1;
        public const int Invoiced = 2;
        public const int Cancelled = 9;
    }

    // ─── Requests ───

    public class SalesDocLineRequest
    {
        public int ItemId { get; set; }
        public string? Descrip { get; set; }
        public decimal Qty { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal Discount { get; set; }
    }

    public class SalesDocRequest
    {
        public int DocType { get; set; }
        public DateTime? DocDate { get; set; }
        public DateTime? ValidUntil { get; set; }
        public int? CustomerId { get; set; }
        // one-off customer when CustomerId is empty; with CustomerId these are taken from the customer
        public string? CustName { get; set; }
        public string? CustAddress { get; set; }
        public string? CustPhone { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public decimal Discount { get; set; }
        public int? UserId { get; set; }
        public List<SalesDocLineRequest> Items { get; set; } = new();
    }

    public class SalesDocSearchRequest
    {
        public int? DocType { get; set; }
        public DateTime? FromDate { get; set; }
        public DateTime? ToDate { get; set; }
        public int? CustomerId { get; set; }
        // doc no, customer name or reference
        public string? Text { get; set; }
        public int? Status { get; set; }
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 50;
    }

    public class SalesDocCancelRequest
    {
        public string? Reason { get; set; }
        public int? UserId { get; set; }
    }

    public class SalesDocToInvoiceRequest
    {
        public DateTime? DocDate { get; set; }
        public int? UserId { get; set; }
    }

    // ─── Responses ───

    public class SalesDocRow
    {
        public int DocId { get; set; }
        public int DocType { get; set; }
        public string DocNo { get; set; } = "";
        public DateTime DocDate { get; set; }
        public DateTime? ValidUntil { get; set; }
        public int? CustomerId { get; set; }
        public string CustName { get; set; } = "";
        public string? Reference { get; set; }
        public int LineCount { get; set; }
        public decimal NetAmount { get; set; }
        public int Status { get; set; }
        public int? FromDocId { get; set; }
        public string? FromDocNo { get; set; }
        public string? InvoiceDocNo { get; set; }
        public DateTime CDate { get; set; }
    }

    public class SalesDocSearchResult
    {
        public int Total { get; set; }
        public List<SalesDocRow> Rows { get; set; } = new();
    }

    // one document with lines, plus the linked quotation / invoice numbers
    public class SalesDocDetail
    {
        public SalesDoc Doc { get; set; } = new();
        public string? FromDocNo { get; set; }
        public int? InvoiceDocId { get; set; }
        public string? InvoiceDocNo { get; set; }
    }

    // Business errors (bad line, wrong status, ...) → HTTP 400 { message }
    public class SalesDocException : Exception
    {
        public SalesDocException(string message) : base(message) { }
    }
}
