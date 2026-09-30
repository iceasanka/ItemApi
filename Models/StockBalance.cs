using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    // Current stock per item/location = SUM(z_tb_StockLedger.Qty). Kept up to date by
    // z_sp_PostStockMovements — read-only in the API. Key (LocationId, ItemId) set in AppDbContext.StockLedger.cs
    [Table("z_tb_StockBalance")]
    public class StockBalance
    {
        public int LocationId { get; set; }

        public int ItemId { get; set; }

        [Column(TypeName = "decimal(18,3)")]
        public decimal Qty { get; set; }

        // weighted average cost, moved by GRNs only
        [Column(TypeName = "decimal(18,2)")]
        public decimal? AvgCost { get; set; }

        public long? LastLedgerId { get; set; }

        public DateTime UDate { get; set; }
    }
}
