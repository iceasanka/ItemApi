using System.ComponentModel.DataAnnotations;

namespace ItemApi.Models
{
    // Purchase return line DTO (not an EF entity) — stored in z_tb_TempPurchase.
    // Mapped to/from TempPurchase in TempPurchaseReturnRepository (PrnNo ↔ GrnNo).
    public class TempPurchaseReturn
    {
        public int Idx { get; set; }

        [Required]
        [MaxLength(20)]
        public string PrnNo { get; set; }

        public int? LocationId { get; set; }

        public int ItemId { get; set; }

        public DateTime? PDate { get; set; }

        public decimal? CostPrice { get; set; }

        public decimal? SellPrice { get; set; }

        public decimal? Qty { get; set; }

        public decimal? Discount { get; set; }

        public decimal? GAmount { get; set; }

        public DateOnly? ExpDate { get; set; }

        public int? Status { get; set; }

        public DateTime? UDate { get; set; }

        [MaxLength(20)]
        public string? UserId { get; set; }
    }
}
