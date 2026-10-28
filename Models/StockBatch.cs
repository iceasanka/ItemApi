using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    // FIFO cost batch: one row per stock-in, Qty = what is left (StockSystem.md 6.30).
    // Written ONLY by z_sp_ApplyStockBatches — read-only in the API.
    [Table("z_tb_StockBatch")]
    public class StockBatch
    {
        [Key]
        public int BatchId { get; set; }

        public int LocationId { get; set; }

        public int ItemId { get; set; }

        // NULL = the item's normal price (follows z_tb_ItemDet.RetailPrice)
        [Column(TypeName = "decimal(18,2)")]
        public decimal? SellPrice { get; set; }

        public int? PriceLinkId { get; set; }

        [Column(TypeName = "decimal(18,2)")]
        public decimal? CostPrice { get; set; }

        [Column(TypeName = "decimal(18,3)")]
        public decimal InQty { get; set; }

        [Column(TypeName = "decimal(18,3)")]
        public decimal Qty { get; set; }

        public long LedgerId { get; set; }

        // Meta.StockTxnType of the movement that brought it in
        public int TxnType { get; set; }

        [MaxLength(30)]
        public string DocNo { get; set; } = "";

        public DateTime InDate { get; set; }

        public DateTime UDate { get; set; }
    }
}
