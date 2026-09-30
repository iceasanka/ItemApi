using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    // ─── Entities (read-only in EF; written by z_sp_* procs) ─────────────────────

    // Cashier till registered with the back office
    [Table("z_tb_Terminal")]
    public class Terminal
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.None)]
        public int TerminalId { get; set; }

        [MaxLength(10)]
        public string TerminalCode { get; set; }

        public int LocationId { get; set; }

        [MaxLength(50)]
        public string? TerminalName { get; set; }

        // 1 active, 0 disabled (sync refused)
        public int Status { get; set; }

        public int LastZNo { get; set; }

        public DateTime? LastSyncAt { get; set; }

        public DateTime? LastItemSyncAt { get; set; }

        public DateTime CDate { get; set; }
    }

    [Table("z_tb_ZReport")]
    public class ZReport
    {
        [Key]
        public int ZId { get; set; }
        public int TerminalId { get; set; }
        public int ZNo { get; set; }
        public int LocationId { get; set; }
        public DateTime BusinessDate { get; set; }
        [MaxLength(20)]
        public string? CashierId { get; set; }
        public DateTime? OpenedAt { get; set; }
        public DateTime? ClosedAt { get; set; }
        public int? FromSeq { get; set; }
        public int? ToSeq { get; set; }
        public int InvoiceCount { get; set; }
        public int LineCount { get; set; }
        [Column(TypeName = "decimal(18,3)")] public decimal TotalQty { get; set; }
        [Column(TypeName = "decimal(18,2)")] public decimal SalesAmount { get; set; }
        [Column(TypeName = "decimal(18,2)")] public decimal RefundAmount { get; set; }
        [Column(TypeName = "decimal(18,2)")] public decimal NetSales { get; set; }
        [Column(TypeName = "decimal(18,2)")] public decimal CashAmount { get; set; }
        [Column(TypeName = "decimal(18,2)")] public decimal CardAmount { get; set; }
        [Column(TypeName = "decimal(18,2)")] public decimal OtherAmount { get; set; }
        public int? SrvInvoiceCount { get; set; }
        public int? SrvLineCount { get; set; }
        [Column(TypeName = "decimal(18,3)")] public decimal? SrvTotalQty { get; set; }
        [Column(TypeName = "decimal(18,2)")] public decimal? SrvNetSales { get; set; }
        public int? MissingCount { get; set; }
        // Meta.ZReportStatus
        public int Status { get; set; }
        [MaxLength(500)]
        public string? MismatchNote { get; set; }
        public DateTime SubmittedAt { get; set; }
        public DateTime? ReconciledAt { get; set; }

        [NotMapped]
        public string? TerminalCode { get; set; }

        [NotMapped]
        public List<ZReportItem>? Items { get; set; }
    }

    // Key (ZId, ItemId) set in AppDbContext.StockLedger.cs
    [Table("z_tb_ZReportItem")]
    public class ZReportItem
    {
        public int ZId { get; set; }
        public int ItemId { get; set; }
        [Column(TypeName = "decimal(18,3)")] public decimal Qty { get; set; }
        [Column(TypeName = "decimal(18,2)")] public decimal Amount { get; set; }
        [Column(TypeName = "decimal(18,3)")] public decimal? SrvQty { get; set; }
        [Column(TypeName = "decimal(18,2)")] public decimal? SrvAmount { get; set; }

        [NotMapped]
        public string? RefCode { get; set; }

        [NotMapped]
        public string? Descrip { get; set; }
    }

    // ─── Requests / responses for api/Sync ────────────────────────────────────────

    // POST api/Sync/Terminal — register or update a till
    public class TerminalRegisterRequest
    {
        public int TerminalId { get; set; }

        [Required]
        [MaxLength(10)]
        public string TerminalCode { get; set; }

        [MaxLength(50)]
        public string? TerminalName { get; set; }

        // 1 active, 0 disabled
        public int Status { get; set; } = 1;
    }

    // GET api/Sync/Terminals — back office dashboard / adjustment-screen warning
    public class TerminalStatus
    {
        public int TerminalId { get; set; }
        public string TerminalCode { get; set; } = "";
        public string? TerminalName { get; set; }
        public int Status { get; set; }
        public DateTime? LastSyncAt { get; set; }
        public DateTime? LastItemSyncAt { get; set; }
        public int LastZNo { get; set; }
        // Z reports received but not reconciled (Status 2 or 4)
        public int OpenZCount { get; set; }
        // no upload for a while — sales may be waiting on the till (counts may be off)
        public bool IsStale { get; set; }
    }

    // GET api/Sync/Items — row = z_sp_GetItemsForSync = zf_tt_Item on the till
    public class SyncItem
    {
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        public string? Descrip { get; set; }
        public string? Inv_Descrip { get; set; }
        public string? SinhalaDescrip { get; set; }
        public bool OpenPrice { get; set; }
        public decimal? MaxPrice { get; set; }
        public decimal? RetailPrice { get; set; }
        public decimal? WholesalePrice { get; set; }
        public decimal? SpecialPrice { get; set; }
        public bool IsSaleLocked { get; set; }
        public bool NoDiscount { get; set; }
        public decimal? DiscountAmount { get; set; }
        public decimal? DiscountPercent { get; set; }
        public decimal? QtyLevel2 { get; set; }
        public decimal? PriceLevel2 { get; set; }
        public decimal? QtyLevel3 { get; set; }
        public decimal? PriceLevel3 { get; set; }
        public decimal? QtyLevel4 { get; set; }
        public decimal? PriceLevel4 { get; set; }
        public int Status { get; set; }
        public DateTime? UDate { get; set; }
    }

    public class SyncStockBalance
    {
        public int ItemId { get; set; }
        public decimal Qty { get; set; }
        public DateTime? UDate { get; set; }
    }

    // Download response: the till stores ServerTime and sends it back as "since" next time
    public class SyncDownload<T>
    {
        public DateTime ServerTime { get; set; }
        public List<T> Rows { get; set; } = new();
    }

    // POST api/Sync/Invoices — from zf_sp_GetUnsyncedInvoices
    public class SyncInvoiceBatch
    {
        public int TerminalId { get; set; }

        [Required]
        public List<SyncInvoice> Invoices { get; set; } = new();
    }

    public class SyncInvoice
    {
        [Required]
        [MaxLength(30)]
        public string InvoiceNo { get; set; }
        public int InvoiceSeq { get; set; }
        public int ZNo { get; set; }
        // 1 sale, 2 refund
        public int InvType { get; set; }
        public DateTime InvDate { get; set; }
        [MaxLength(20)]
        public string? CashierId { get; set; }
        public decimal GrossAmount { get; set; }
        public decimal Discount { get; set; }
        public decimal NetAmount { get; set; }
        // 1 completed, 9 voided
        public int Status { get; set; }
        public List<SyncInvoiceItem> Items { get; set; } = new();
        public List<SyncPayment> Payments { get; set; } = new();
    }

    public class SyncInvoiceItem
    {
        public int LineNum { get; set; }
        public int ItemId { get; set; }
        public decimal Qty { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal Discount { get; set; }
        public decimal Amount { get; set; }
    }

    public class SyncPayment
    {
        public int LineNum { get; set; }
        // 1 cash, 2 card, 3 credit, 4 voucher
        public int PayType { get; set; }
        public decimal Amount { get; set; }
        [MaxLength(30)]
        public string? RefNo { get; set; }
    }

    // One per invoice sent. The till marks BOTH "Inserted" and "Duplicate" as synced.
    public class SyncInvoiceResult
    {
        public string InvoiceNo { get; set; } = "";
        public string Result { get; set; } = "";
    }

    // POST api/Sync/ZReport — from zf_sp_GetZForSubmit
    public class ZReportSubmit
    {
        public int TerminalId { get; set; }
        public int ZNo { get; set; }
        public DateTime BusinessDate { get; set; }
        [MaxLength(20)]
        public string? CashierId { get; set; }
        public DateTime? OpenedAt { get; set; }
        public DateTime? ClosedAt { get; set; }
        public int? FromSeq { get; set; }
        public int? ToSeq { get; set; }
        public int InvoiceCount { get; set; }
        public int LineCount { get; set; }
        public decimal TotalQty { get; set; }
        public decimal SalesAmount { get; set; }
        public decimal RefundAmount { get; set; }
        public decimal NetSales { get; set; }
        public decimal CashAmount { get; set; }
        public decimal CardAmount { get; set; }
        public decimal OtherAmount { get; set; }
        public List<ZReportSubmitItem> Items { get; set; } = new();
    }

    public class ZReportSubmitItem
    {
        public int ItemId { get; set; }
        public decimal Qty { get; set; }
        public decimal Amount { get; set; }
    }

    // Result row of z_sp_SubmitZReport / z_sp_ReconcileZReport
    public class ZReportResult
    {
        public int ZId { get; set; }
        public int TerminalId { get; set; }
        public int ZNo { get; set; }
        public DateTime BusinessDate { get; set; }
        // 3 reconciled, 4 mismatch
        public int Status { get; set; }
        public int InvoiceCount { get; set; }
        public int? SrvInvoiceCount { get; set; }
        public int LineCount { get; set; }
        public int? SrvLineCount { get; set; }
        public decimal TotalQty { get; set; }
        public decimal? SrvTotalQty { get; set; }
        public decimal NetSales { get; set; }
        public decimal? SrvNetSales { get; set; }
        public int MissingCount { get; set; }
        public string? MismatchNote { get; set; }
    }

    // Response of POST api/Sync/ZReport
    public class ZReportSubmitResponse
    {
        public ZReportResult Result { get; set; }

        // Status 4 only: invoice numbers the till must resend (zf_sp_GetInvoicesByNo), then submit the Z again
        public List<string> MissingInvoiceNos { get; set; } = new();
    }

    public class ZMissingInvoice
    {
        public int InvoiceSeq { get; set; }
        public string InvoiceNo { get; set; } = "";
    }

    // POST api/Sync/ZReports/Search
    public class ZReportSearchRequest
    {
        public DateTime? FromDate { get; set; }
        public DateTime? ToDate { get; set; }
        public int? TerminalId { get; set; }
        public int? Status { get; set; }
    }
}
