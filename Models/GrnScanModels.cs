using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    // GRN scan (R&D): a photo of a supplier invoice read by Google Gemini into header + lines, with the sums checked
    // here (step 1), each line matched to one of our items (step 2, z_tb_SupplierItemMap), made into a suspended GRN
    // (step 3). Docs/StockSystem.md 6.31.

    // What Gemini returns (the response schema in GrnScanReader asks for exactly these names). Numbers as printed;
    // null = not on the paper.
    public class GrnScanHeader
    {
        public string? SupplierName { get; set; }
        public string? InvoiceNo { get; set; }
        // yyyy-MM-dd
        public string? InvoiceDate { get; set; }
        public string? VatNo { get; set; }
        // "Page 1 of 2"
        public string? PageText { get; set; }
        public decimal? TotalGross { get; set; }
        public decimal? TotalDiscount { get; set; }
        public decimal? NetTotal { get; set; }
    }

    public class GrnScanLine
    {
        public int? LineNo { get; set; }
        // the supplier's own item code (e.g. "3551304" of "3551304-SLT NAT LIQUID 450MLX20")
        public string? SupplierCode { get; set; }
        public string? Description { get; set; }
        public string? Barcode { get; set; }
        // invoices with cases + pieces columns; SaleQty when the invoice has one qty column
        public decimal? SaleCases { get; set; }
        public decimal? SalePieces { get; set; }
        public decimal? SaleQty { get; set; }
        public decimal? FreeCases { get; set; }
        public decimal? FreePieces { get; set; }
        public decimal? FreeQty { get; set; }
        // pieces in one case ("Case Config")
        public decimal? CaseSize { get; set; }
        public decimal? UnitPrice { get; set; }
        public decimal? GrossAmount { get; set; }
        // line discount ("Scheme Disc")
        public decimal? Discount { get; set; }
        public decimal? Mrp { get; set; }
        // the model could not read part of the line well
        public bool Unclear { get; set; }
        public string? Note { get; set; }

        // ─── worked out by ItemApi ───
        // pieces bought / free: SaleQty, else cases x case size + pieces
        public decimal? Qty { get; set; }
        public decimal? FreeTotal { get; set; }
        // (gross - discount) / qty
        public decimal? UnitCost { get; set; }
        // qty x unit price - gross (0 = adds up)
        public decimal? AmountDiff { get; set; }
        // ok / check / error
        public string Status { get; set; } = "ok";
        public List<string> Issues { get; set; } = new();

        // ─── our item (step 2: matched when the supplier is known) ───
        public int? ItemId { get; set; }
        // code / name / barcode = a saved match or a printed barcode; null = not matched (see Suggestions)
        public string? MatchedBy { get; set; }
        public int? MapId { get; set; }
        public GrnScanItemHit? Item { get; set; }
        // closest item names, best first (only for a line without a match)
        public List<GrnScanItemHit> Suggestions { get; set; } = new();
        // unit cost against our cost price, % (null = no cost on either side)
        public decimal? CostChangePct { get; set; }
    }

    // one of our items, for a match or a suggestion
    public class GrnScanItemHit
    {
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        public string? Descrip { get; set; }
        public decimal? RetailPrice { get; set; }
        public decimal? CostPrice { get; set; }
        // 1 = active
        public int? Status { get; set; }
        // the item's supplier is the invoice's supplier
        public bool SameSupplier { get; set; }
        // 0-1, how close the name is (suggestions / search only)
        public decimal Score { get; set; }
    }

    // POST api/GrnScan/Match — match lines already read (e.g. after the supplier was changed) without reading again
    public class GrnScanMatchRequest
    {
        public int SupplierId { get; set; }
        public List<GrnScanLine> Lines { get; set; } = new();
    }

    // POST api/GrnScan/SaveMatches — the matches confirmed on the review page
    public class GrnScanSaveRequest
    {
        public int SupplierId { get; set; }
        public int? UserId { get; set; }
        public List<GrnScanSaveLine> Lines { get; set; } = new();
    }

    public class GrnScanSaveLine
    {
        public string? SupplierCode { get; set; }
        public string? Description { get; set; }
        public int ItemId { get; set; }
        public decimal? CaseSize { get; set; }
    }

    // ─── db rows (column names = the procs) ───

    public class GrnScanMatchRow
    {
        public int LineKey { get; set; }
        public int? ItemId { get; set; }
        public string? MatchedBy { get; set; }
        public int? MapId { get; set; }
        public decimal? MapCaseSize { get; set; }
        public string? RefCode { get; set; }
        public string? ItemBarcode { get; set; }
        public string? ItemDescrip { get; set; }
        public int? ItemStatus { get; set; }
        public decimal? RetailPrice { get; set; }
        public decimal? CostPrice { get; set; }
    }

    public class GrnScanMapRow
    {
        public string? SupplierCode { get; set; }
        public string SupplierDescrip { get; set; } = "";
        public string DescripKey { get; set; } = "";
        public int ItemId { get; set; }
        public decimal? CaseSize { get; set; }
    }

    // z_sp_GrnScanGetMaps — GET api/GrnScan/Maps
    public class GrnScanMap
    {
        public int MapId { get; set; }
        public int SuppId { get; set; }
        public string? SupplierCode { get; set; }
        public string SupplierDescrip { get; set; } = "";
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? ItemDescrip { get; set; }
        public int? ItemStatus { get; set; }
        public decimal? CaseSize { get; set; }
        public int UseCount { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime LastSavedAt { get; set; }
    }

    public class GrnScanItemRow
    {
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        public string? Descrip { get; set; }
        public int? SupId { get; set; }
        public decimal? RetailPrice { get; set; }
        public decimal? CostPrice { get; set; }
    }

    // POST api/GrnScan/MakeDraft — the confirmed lines of a scan become a suspended GRN (opened on GRN Entry)
    public class GrnScanDraftRequest
    {
        public int SupplierId { get; set; }
        // the saved scan it is made from (marked Status 1 with the GRN no)
        public int? ScanId { get; set; }
        public int? UserId { get; set; }
        // the supplier's invoice no (GRN RefNo) and date (in the remark)
        public string? InvoiceNo { get; set; }
        public string? InvoiceDate { get; set; }
        // "mrp" = the selling price of each line is the printed MRP (when there is one); else our selling price now
        public string? SellPrice { get; set; }
        // true = make it even when this invoice no of the supplier is already on another GRN
        public bool AllowSameInvoice { get; set; }
        public List<GrnScanDraftLine> Lines { get; set; } = new();
    }

    public class GrnScanDraftLine
    {
        public int ItemId { get; set; }
        // pieces bought and free
        public decimal Qty { get; set; }
        public decimal? FreeQty { get; set; }
        public decimal GrossAmount { get; set; }
        public decimal? Discount { get; set; }
        public decimal? Mrp { get; set; }
        // kept as a saved match (z_tb_SupplierItemMap)
        public string? SupplierCode { get; set; }
        public string? Description { get; set; }
        public decimal? CaseSize { get; set; }
    }

    // z_sp_GrnScanMakeDraft answer (+ MatchesSaved)
    public class GrnScanDraftResult
    {
        public string GrnNo { get; set; } = "";
        public int Lines { get; set; }
        public decimal Qty { get; set; }
        public decimal Amount { get; set; }
    }

    // the line as it goes on the GRN
    public class GrnScanDraftRow
    {
        public int LineKey { get; set; }
        public int ItemId { get; set; }
        public decimal Qty { get; set; }
        public decimal CostPrice { get; set; }
        public decimal? SellPrice { get; set; }
        public decimal GAmount { get; set; }
    }

    // z_tb_GrnScan - a saved scan (U031). Status 0 open, 1 GRN draft made.
    [Table("z_tb_GrnScan")]
    public class GrnScanDoc
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int ScanId { get; set; }
        public int? SuppId { get; set; }
        public string? InvoiceNo { get; set; }
        public string? InvoiceDate { get; set; }
        public string? Folder { get; set; }
        public int Pages { get; set; }
        public int Lines { get; set; }
        public int Matched { get; set; }
        public int Status { get; set; }
        public string? GrnNo { get; set; }
        public string ResultJson { get; set; } = "";
        public string? StateJson { get; set; }
        public DateTime CreatedAt { get; set; }
        public int? CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public int? UpdatedBy { get; set; }
    }

    // the page's work on a scan: picks (line index → our item) and lines left out
    public class GrnScanState
    {
        public Dictionary<int, GrnScanItemHit> Picks { get; set; } = new();
        public Dictionary<int, bool> Skip { get; set; } = new();
    }

    // PUT api/GrnScan/Scans/{id} — the page keeps its work as it goes
    public class GrnScanSaveStateRequest
    {
        public int? SupplierId { get; set; }
        public int? UserId { get; set; }
        public GrnScanResult Result { get; set; } = new();
        public GrnScanState State { get; set; } = new();
    }

    // GET api/GrnScan/Scans — the list
    public class GrnScanListRow
    {
        public int ScanId { get; set; }
        public int? SuppId { get; set; }
        public string? SuppName { get; set; }
        public string? InvoiceNo { get; set; }
        public string? InvoiceDate { get; set; }
        public int Pages { get; set; }
        public int Lines { get; set; }
        public int Matched { get; set; }
        public int Status { get; set; }
        public string? GrnNo { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // GET api/GrnScan/Scans/{id} — a saved scan to carry on with
    public class GrnScanOpen
    {
        public int ScanId { get; set; }
        public int? SuppId { get; set; }
        public string? SuppName { get; set; }
        public int Status { get; set; }
        public string? GrnNo { get; set; }
        public int Pages { get; set; }
        public GrnScanResult Result { get; set; } = new();
        public GrnScanState State { get; set; } = new();
    }

    // POST api/GrnScan/Scans/Flush
    public class GrnScanFlushRequest
    {
        public List<int> ScanIds { get; set; } = new();
    }

    public class GrnScanSavedRow { public int Saved { get; set; } }
    public class GrnScanDeletedRow { public int Deleted { get; set; } }

    public class GrnScanResult
    {
        public string Model { get; set; } = "";
        public int Images { get; set; }
        public long Ms { get; set; }
        public int? SupplierId { get; set; }
        public GrnScanHeader Header { get; set; } = new();
        public List<GrnScanLine> Lines { get; set; } = new();
        public GrnScanCheck Check { get; set; } = new();
        // token use (free tier limits / cost)
        public int? InputTokens { get; set; }
        public int? OutputTokens { get; set; }
        // folder name under GrnScan:SaveFolder (images + gemini.json + result.json), null = not saved
        public string? SavedAs { get; set; }
        // the saved scan (z_tb_GrnScan) - reopen it with GET api/GrnScan/Scans/{id}; null = not kept (no U031)
        public int? ScanId { get; set; }
    }

    public class GrnScanCheck
    {
        public int Lines { get; set; }
        public int LinesOk { get; set; }
        public int LinesToCheck { get; set; }
        public int LinesWithError { get; set; }
        public decimal SumGross { get; set; }
        public decimal SumDiscount { get; set; }
        // sum of the lines - the total printed (null = no total on the paper)
        public decimal? GrossDiff { get; set; }
        public List<string> Issues { get; set; } = new();
    }

    // Gemini refused / failed / the key is not set → HTTP 400 / 502 { message }
    public class GrnScanException : Exception
    {
        public int StatusCode { get; }
        public GrnScanException(string message, int statusCode = 400) : base(message) => StatusCode = statusCode;
    }
}
