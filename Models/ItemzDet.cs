using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    [Table("z_tb_ItemDet")]
    public class ItemzDet
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int ItemDetId { get; set; }

        public int ItemId { get; set; }
        public int LocationId { get; set; }
        public decimal? RetailPrice { get; set; }
        public decimal? WholesalePrice { get; set; }
        public decimal? SpecialPrice { get; set; }
        public decimal? CostPrice { get; set; }
        public decimal? AverageCost { get; set; }
        public int? UnitId { get; set; }
        public decimal? WholesaleMargin { get; set; }
        public decimal? RetailMargin { get; set; }
        public bool IsSaleLocked { get; set; } = false;
        public bool NoDiscount { get; set; } = false;
        public decimal? ReorderLevel { get; set; }
        public decimal? ReorderQty { get; set; }
        public decimal? QtyLevel2 { get; set; }
        public decimal? PriceLevel2 { get; set; }
        public decimal? QtyLevel3 { get; set; }
        public decimal? PriceLevel3 { get; set; }
        public decimal? QtyLevel4 { get; set; }
        public decimal? PriceLevel4 { get; set; }
        public decimal? DiscountAmount { get; set; }
        public decimal? DiscountPercent { get; set; }
        public int? UserId { get; set; }
        public DateTime CDate { get; set; }
        public DateTime UDate { get; set; }

        // Navigation property
        [ForeignKey("ItemId")]
        public Itemz? Item { get; set; }
    }
}
