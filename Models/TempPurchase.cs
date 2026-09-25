using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    [Table("z_tb_TempPurchase")]
    public class TempPurchase
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Idx { get; set; }

        [Required]
        [MaxLength(20)]
        public string GrnNo { get; set; }

        public int? LocationId { get; set; }

        public int ItemId { get; set; }

        public DateTime? PDate { get; set; }

        public decimal? Cost { get; set; }

        public decimal? Rate { get; set; }

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
