using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    [Table("z_tb_SupplierLedger")]
    public class SupplierLedger
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int LedgerId { get; set; }

        public int SuppId { get; set; }

        public DateTime TxnDate { get; set; }

        /// <summary>
        /// 1 = PURCHASE, 2 = PAYMENT, 3 = RETURN
        /// </summary>
        public int Type { get; set; }

        [MaxLength(50)]
        public string ReferenceId { get; set; }

        [MaxLength(250)]
        public string? Remark { get; set; }

        [Column(TypeName = "decimal(18,2)")]
        public decimal DebitAmount { get; set; } = 0;

        [Column(TypeName = "decimal(18,2)")]
        public decimal CreditAmount { get; set; } = 0;

        public int? UserId { get; set; }

        public DateTime CDate { get; set; } = DateTime.Now;

        public DateTime UDate { get; set; } = DateTime.Now;

        /// <summary>
        /// Computed by stored procedure — not mapped to a column
        /// </summary>
        [NotMapped]
        public decimal RunningBalance { get; set; }

        [NotMapped]
        public string TypeName => Type switch
        {
            1 => "PURCHASE",
            2 => "PAYMENT",
            3 => "RETURN",
            _ => "UNKNOWN"
        };
    }
}