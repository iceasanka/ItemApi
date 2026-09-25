namespace ItemApi.Models
{
    public class ItemzWithDetails
    {
        // From z_tb_Item
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        public string? Descrip { get; set; }
        public string? SinhalaDescrip { get; set; }
        public int? CatId { get; set; }
        public int? SubCatId { get; set; }
        public int? SupId { get; set; }
        public bool UseExp { get; set; }
        public string? Inv_Descrip { get; set; }
        public decimal? MaxPrice { get; set; }
        public bool OpenPrice { get; set; }

        // From z_tb_ItemDet
        public int ItemDetId { get; set; }
        public int LocationId { get; set; }
        public decimal? RetailPrice { get; set; }
        public decimal? WholesalePrice { get; set; }
        public decimal? SpecialPrice { get; set; }
        public decimal? CostPrice { get; set; }
        public decimal? AverageCost { get; set; }
        public int? UnitId { get; set; }
        public decimal? WholesaleMargin { get; set; }
        public decimal? RetailMargin { get; set; }
        public bool IsSaleLocked { get; set; }
        public bool NoDiscount { get; set; }
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
    }
}
