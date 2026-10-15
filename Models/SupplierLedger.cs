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

        public int? SuppId { get; set; }

        public DateTime TxnDate { get; set; }

        /// <summary>
        /// 1 = PURCHASE, 2 = PAYMENT, 3 = RETURN
        /// </summary>
        public int Type { get; set; }

        /// <summary>
        /// Left empty on add → made from the supplier code: SUP001-00001
        /// </summary>
        [MaxLength(100)]
        public string? ReferenceId { get; set; }

        /// <summary>
        /// The supplier's bill number (PURCHASE)
        /// </summary>
        [MaxLength(50)]
        public string? InvoiceNo { get; set; }

        [MaxLength(500)]
        public string? Remark { get; set; }

        /// <summary>
        /// PURCHASE: when the bill should be paid. Empty → TxnDate + the supplier's CreditDays
        /// </summary>
        public DateTime? DueDate { get; set; }

        /// <summary>
        /// PAYMENT made by a written cheque (z_tb_WrittenCheque) — change it through the cheque
        /// </summary>
        public int? ChequeId { get; set; }

        /// <summary>
        /// PAYMENT / RETURN: the bills it pays. null = leave as they are (on change); [] = pays no bill
        /// </summary>
        [NotMapped]
        public List<SupplierAllocation>? Allocations { get; set; }

        [Column(TypeName = "decimal(18,2)")]
        public decimal DebitAmount { get; set; } = 0;

        [Column(TypeName = "decimal(18,2)")]
        public decimal CreditAmount { get; set; } = 0;

        public int? UserId { get; set; }

        public DateTime? CDate { get; set; } 

        public DateTime? UDate { get; set; } 

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