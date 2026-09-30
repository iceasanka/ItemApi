using System.ComponentModel.DataAnnotations;

namespace ItemApi.Models
{
    // Purchase return header DTO (not an EF entity) — stored in z_tb_TempPurchaseSummary with
    // Type = 2. Mapped to/from TempPurchaseSummary in TempPurchaseReturnSummaryRepository:
    //   PrnNo   ↔ GrnNo
    //   RetType ↔ PMode
    public class TempPurchaseReturnSummary
    {
        public int Idx { get; set; }

        [Required]
        [MaxLength(20)]
        public string PrnNo { get; set; }

        public int? LocationId { get; set; }

        [MaxLength(30)]
        public string? RefNo { get; set; }

        public DateTime? PDate { get; set; }

        public int? SuppId { get; set; }

        // Filled from z_tb_Supplier by SearchAsync
        public string? SuppName { get; set; }

        public int? RetType { get; set; }

        public decimal? GAmount { get; set; }

        [MaxLength(20)]
        public string? POderNo { get; set; }

        public decimal? SubTotDisc { get; set; }

        public decimal? NetAmount { get; set; }

        public decimal? Qty { get; set; }

        // Always saved as 2 (purchase return) regardless of what the UI sends
        public int? Type { get; set; }

        public int? Status { get; set; }

        [MaxLength(200)]
        public string? Remark { get; set; }

        public DateTime? UDate { get; set; }

        [MaxLength(20)]
        public string? UserId { get; set; }
    }
}
