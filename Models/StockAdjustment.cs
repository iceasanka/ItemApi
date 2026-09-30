using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    // Stock adjustment header (ADJ00000001). Saved + posted by z_sp_SaveStockAdjustment — read-only in EF.
    [Table("z_tb_StockAdjustment")]
    public class StockAdjustment
    {
        [Key]
        public int AdjId { get; set; }

        [MaxLength(20)]
        public string AdjNo { get; set; }

        public int LocationId { get; set; }

        public DateTime AdjDate { get; set; }

        public int? ReasonId { get; set; }

        [MaxLength(200)]
        public string? Remark { get; set; }

        public int LineCount { get; set; }

        [Column(TypeName = "decimal(18,3)")]
        public decimal TotalAdjQty { get; set; }

        [Column(TypeName = "decimal(18,2)")]
        public decimal TotalAdjValue { get; set; }

        // 2 = posted
        public int Status { get; set; }

        [MaxLength(20)]
        public string? UserId { get; set; }

        public DateTime CDate { get; set; }

        // Not columns — filled by StockAdjustmentRepository for the UI
        [NotMapped]
        public string? ReasonName { get; set; }

        [NotMapped]
        public List<StockAdjustmentItem>? Items { get; set; }
    }

    // Key (AdjId, LineNum) set in AppDbContext.StockLedger.cs
    [Table("z_tb_StockAdjustmentItem")]
    public class StockAdjustmentItem
    {
        public int AdjId { get; set; }

        public int LineNum { get; set; }

        public int ItemId { get; set; }

        // server balance when the adjustment was posted
        [Column(TypeName = "decimal(18,3)")]
        public decimal SystemQty { get; set; }

        // set = count mode (AdjQty = CountedQty - SystemQty)
        [Column(TypeName = "decimal(18,3)")]
        public decimal? CountedQty { get; set; }

        // signed quantity posted to the ledger
        [Column(TypeName = "decimal(18,3)")]
        public decimal AdjQty { get; set; }

        [Column(TypeName = "decimal(18,2)")]
        public decimal? CostPrice { get; set; }

        public int? ReasonId { get; set; }

        [MaxLength(100)]
        public string? Remark { get; set; }

        [NotMapped]
        public string? RefCode { get; set; }

        [NotMapped]
        public string? Descrip { get; set; }
    }

    [Table("z_tb_StockAdjReason")]
    public class StockAdjReason
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.None)]
        public int ReasonId { get; set; }

        [MaxLength(50)]
        public string ReasonName { get; set; }

        public int Status { get; set; }
    }

    // POST api/StockAdjustment/Save
    public class StockAdjustmentRequest
    {
        // defaults to now
        public DateTime? AdjDate { get; set; }

        // header reason, used for lines without their own ReasonId
        public int? ReasonId { get; set; }

        [MaxLength(200)]
        public string? Remark { get; set; }

        [MaxLength(20)]
        public string? UserId { get; set; }

        [Required]
        [MinLength(1)]
        public List<StockAdjustmentLine> Lines { get; set; } = new();
    }

    public class StockAdjustmentLine
    {
        public int ItemId { get; set; }

        // Count mode: the quantity physically counted. The server works out the difference.
        public decimal? CountedQty { get; set; }

        // Quantity mode (used when CountedQty is null): + adds stock, - removes stock
        public decimal? AdjQty { get; set; }

        public int? ReasonId { get; set; }

        [MaxLength(100)]
        public string? Remark { get; set; }
    }

    // POST api/StockAdjustment/Search
    public class StockAdjustmentSearchRequest
    {
        public string? AdjNo { get; set; }
        public DateTime? FromDate { get; set; }
        public DateTime? ToDate { get; set; }
        public int? ReasonId { get; set; }
    }
}
