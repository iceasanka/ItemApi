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

        public int? LocaCode { get; set; }

        [MaxLength(30)]
        public string? RefNo { get; set; }

        public DateTime? PDate { get; set; }

        [MaxLength(20)]
        public string? SuppCode { get; set; }

        [MaxLength(10)]
        public string? PMode { get; set; }

        public decimal? GAmount { get; set; }

        [MaxLength(20)]
        public string? POderNo { get; set; }

        public decimal? Disc { get; set; }

        public decimal? SubTotDisc { get; set; }

        public decimal? NetAmount { get; set; }

        public decimal? Advance { get; set; }

        public decimal? Returns { get; set; }

        public decimal? Balance { get; set; }

        public decimal? Qty { get; set; }

        [MaxLength(10)]
        public string? Type { get; set; }

        public int? Status { get; set; }

        [MaxLength(200)]
        public string? Remark { get; set; }

        public DateTime? UDate { get; set; }

        [MaxLength(20)]
        public string? UserId { get; set; }
    }
}
