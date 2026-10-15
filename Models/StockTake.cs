using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    // Stock take (ST00000001): count sheets → counts → post the difference as one stock adjustment.
    // Tables and procs: DBScript/Updates/U006_BackOffice_StockTake.sql. Read-only in EF — writes go through the z_sp_* procs.
    [Table("z_tb_StockTake")]
    public class StockTake
    {
        [Key]
        public int StockTakeId { get; set; }

        [MaxLength(20)]
        public string? StockTakeNo { get; set; }

        public int LocationId { get; set; }

        [MaxLength(100)]
        public string? Title { get; set; }

        // the count is "as at" this moment; the post compares with the ledger up to here
        public DateTime FreezeAt { get; set; }

        public int? CatId { get; set; }
        public int? SubCatId { get; set; }
        public int? SupId { get; set; }
        public bool IncludeZeroStock { get; set; }

        // 1 counting, 2 posted, 9 cancelled (Meta.StockTakeStatus)
        public int Status { get; set; }

        // the adjustment made by the post; null = nothing to adjust (or not posted)
        [MaxLength(20)]
        public string? AdjNo { get; set; }

        public bool? UncountedAsZero { get; set; }
        public DateTime? PostedAt { get; set; }

        [MaxLength(20)]
        public string? PostedBy { get; set; }

        [MaxLength(20)]
        public string? UserId { get; set; }

        public DateTime CDate { get; set; }
        public DateTime UDate { get; set; }

        // Not columns — filled by StockTakeRepository
        [NotMapped] public int ItemCount { get; set; }
        [NotMapped] public int CountedItems { get; set; }
        [NotMapped] public int SheetCount { get; set; }
        [NotMapped] public int SheetsDone { get; set; }
        [NotMapped] public List<StockTakeSheet>? Sheets { get; set; }
    }

    [Table("z_tb_StockTakeSheet")]
    public class StockTakeSheet
    {
        [Key]
        public int SheetId { get; set; }

        public int StockTakeId { get; set; }

        public int SheetNo { get; set; }

        [MaxLength(100)]
        public string? SheetName { get; set; }

        [MaxLength(50)]
        public string? CountedBy { get; set; }

        // 1 open, 2 done
        public int Status { get; set; }

        public DateTime CDate { get; set; }

        [NotMapped] public int LineCount { get; set; }
        [NotMapped] public int CountedLines { get; set; }
    }

    // Key (SheetId, ItemId) set in AppDbContext.StockTake.cs
    [Table("z_tb_StockTakeItem")]
    public class StockTakeItem
    {
        public int SheetId { get; set; }
        public int ItemId { get; set; }
        public int StockTakeId { get; set; }
        public int LineNum { get; set; }

        // server balance when the line was made — shown only when the sheet is asked for with showSystemQty
        [Column(TypeName = "decimal(18,3)")]
        public decimal FrozenQty { get; set; }

        [Column(TypeName = "decimal(18,2)")]
        public decimal? CostPrice { get; set; }

        // null = not counted yet
        [Column(TypeName = "decimal(18,3)")]
        public decimal? CountedQty { get; set; }

        [MaxLength(100)]
        public string? Remark { get; set; }

        [MaxLength(20)]
        public string? CountedBy { get; set; }

        public DateTime? CountedAt { get; set; }
    }

    // GET api/StockTake/{id}/Sheet/{sheetId} — one line of a count sheet
    public class StockTakeSheetLine
    {
        public int LineNum { get; set; }
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        public string? Descrip { get; set; }
        public string? UnitCode { get; set; }
        public decimal? CountedQty { get; set; }
        public string? Remark { get; set; }
        public string? CountedBy { get; set; }
        public DateTime? CountedAt { get; set; }
        // null unless showSystemQty=true (blind count by default)
        public decimal? SystemQty { get; set; }
    }

    public class StockTakeSheetView
    {
        public StockTake Header { get; set; } = null!;
        public StockTakeSheet Sheet { get; set; } = null!;
        public List<StockTakeSheetLine> Lines { get; set; } = new();
    }

    // z_sp_GetStockTakeVariance — one row per item (counts of every sheet added up)
    public class StockTakeVarianceRow
    {
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        public string? Descrip { get; set; }
        public string? CatName { get; set; }
        public string? UnitCode { get; set; }
        public string? Sheets { get; set; }          // "3" or "3 +1" (on more than one sheet)
        public int Lines { get; set; }
        public int CountedLines { get; set; }
        public decimal? CountedQty { get; set; }     // null = nobody counted it
        public decimal? CostPrice { get; set; }
        public decimal SystemQty { get; set; }       // ledger as at FreezeAt (posted: what the post used)
        public decimal? DiffQty { get; set; }        // counted - system
        public decimal? DiffValue { get; set; }      // DiffQty × cost
        public decimal RetailPrice { get; set; }
        public string? Remark { get; set; }
    }

    public class StockTakeVariance
    {
        public StockTake Header { get; set; } = null!;
        public int ItemCount { get; set; }
        public int CountedItems { get; set; }
        public int UncountedItems { get; set; }
        public int ItemsWithDiff { get; set; }
        public decimal ShortValue { get; set; }      // sum of negative DiffValue (as a negative number)
        public decimal ExcessValue { get; set; }     // sum of positive DiffValue
        public decimal NetValue { get; set; }
        public List<StockTakeVarianceRow> Rows { get; set; } = new();
    }

    public class StockTakeCreateResult
    {
        public int StockTakeId { get; set; }
        public int ItemCount { get; set; }
        public int SheetCount { get; set; }
        public int Skipped { get; set; }             // items left out: already in another open stock take
    }

    public class StockTakePostResult
    {
        public string? AdjNo { get; set; }
        public int AdjustedItems { get; set; }
    }

    // ─── Requests ───────────────────────────────────────────────────────────────

    // POST api/StockTake/Create
    public class StockTakeCreateRequest
    {
        [MaxLength(100)]
        public string? Title { get; set; }
        public int? CatId { get; set; }
        public int? SubCatId { get; set; }
        public int? SupId { get; set; }
        // false: only items with stock (+ or −) on the server; true: every active item
        public bool IncludeZeroStock { get; set; }
        // a new sheet every n items of a category (5–500, default 50)
        public int? ItemsPerSheet { get; set; }
        [MaxLength(20)]
        public string? UserId { get; set; }
    }

    // POST api/StockTake/Search
    public class StockTakeSearchRequest
    {
        public DateTime? FromDate { get; set; }
        public DateTime? ToDate { get; set; }
        public int? Status { get; set; }
        public string? StockTakeNo { get; set; }
    }

    // POST api/StockTake/{id}/Sheet
    public class StockTakeAddSheetRequest
    {
        [Required, MaxLength(100)]
        public string SheetName { get; set; } = "";
        [MaxLength(50)]
        public string? CountedBy { get; set; }
    }

    // POST api/StockTake/{id}/Sheet/{sheetId}/AddItem — itemId, or a barcode / item code that was scanned
    public class StockTakeAddItemRequest
    {
        public int? ItemId { get; set; }
        [MaxLength(50)]
        public string? Code { get; set; }
    }

    // POST api/StockTake/{id}/Sheet/{sheetId}/Counts
    public class StockTakeCountsRequest
    {
        public List<StockTakeCountLine> Counts { get; set; } = new();
        [MaxLength(50)]
        public string? CountedBy { get; set; }
        // true marks the sheet done, false opens it again, null leaves it
        public bool? Done { get; set; }
        [MaxLength(20)]
        public string? UserId { get; set; }
    }

    public class StockTakeCountLine
    {
        public int ItemId { get; set; }
        // null clears the count
        public decimal? CountedQty { get; set; }
        [MaxLength(100)]
        public string? Remark { get; set; }
    }

    // POST api/StockTake/{id}/Post
    public class StockTakePostRequest
    {
        // items nobody counted: false = left alone, true = counted as 0
        public bool UncountedAsZero { get; set; }
        // default 1 "Stock count"
        public int? ReasonId { get; set; }
        [MaxLength(20)]
        public string? UserId { get; set; }
    }

    // POST api/StockTake/{id}/Cancel
    public class StockTakeCancelRequest
    {
        [MaxLength(20)]
        public string? UserId { get; set; }
    }
}
