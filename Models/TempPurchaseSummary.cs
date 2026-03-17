using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    [Table("z_tb_TempPurchaseSummary")]
    public class TempPurchaseSummary
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Idx { get; set; }

        [Required]
        [MaxLength(20)]
        public string GrnNo { get; set; }

        public int? LocaId { get; set; }

        [MaxLength(30)]
        public string? RefNo { get; set; }

        public DateTime? PDate { get; set; }

        [MaxLength(20)]
        public string? SuppId { get; set; }

        public int? PMode { get; set; }

        public decimal? GAmount { get; set; }

        [MaxLength(20)]
        public string? POderNo { get; set; }

        public decimal? SubTotDisc { get; set; }

        public decimal? NetAmount { get; set; }

        public decimal? Advance { get; set; }

        public decimal? Returns { get; set; }

        public decimal? Qty { get; set; }

        public int? Type { get; set; }

        public int? Status { get; set; }

        [MaxLength(200)]
        public string? Remark { get; set; }

        public DateTime? UDate { get; set; }

        [MaxLength(20)]
        public string? UserId { get; set; }
    }
}
