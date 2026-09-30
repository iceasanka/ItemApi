using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    // One stock movement (insert-only). Written ONLY by z_sp_PostStockMovements — read-only in the API.
    [Table("z_tb_StockLedger")]
    public class StockLedger
    {
        [Key]
        public long LedgerId { get; set; }

        public int LocationId { get; set; }

        public int ItemId { get; set; }

        // Meta.StockTxnType
        public int TxnType { get; set; }

        [MaxLength(30)]
        public string DocNo { get; set; }

        public int DocLineNo { get; set; }

        public int? TerminalId { get; set; }

        public int? ZNo { get; set; }

        // signed: + in, - out
        [Column(TypeName = "decimal(18,3)")]
        public decimal Qty { get; set; }

        [Column(TypeName = "decimal(18,2)")]
        public decimal? CostPrice { get; set; }

        [Column(TypeName = "decimal(18,2)")]
        public decimal? SellPrice { get; set; }

        public DateTime TxnDate { get; set; }

        public DateTime CDate { get; set; }

        [MaxLength(20)]
        public string? UserId { get; set; }
    }
}
