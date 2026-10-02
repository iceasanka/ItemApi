using System.ComponentModel.DataAnnotations;

namespace ItemApi.Models
{
    // z_tb_ItemPriceLink — extra retail prices for the same item (DBScript/03_BackOffice_PriceLink.sql).
    // Read and written through procs only; not an EF entity.
    // Not the old-system PriceLink (tb_PriceLink, ItemsController) — keep the two separate.
    public class ItemzPriceLink
    {
        public int PriceLinkId { get; set; }
        public int ItemId { get; set; }
        public int LocationId { get; set; }
        public decimal RetailPrice { get; set; }
        public decimal? WholesalePrice { get; set; }
        public decimal? CostPrice { get; set; }
        public string? Remark { get; set; }
        // 1 active, 0 deleted
        public int Status { get; set; }
        public int? UserId { get; set; }
        public DateTime CDate { get; set; }
        public DateTime UDate { get; set; }
    }

    // POST api/Itemz/AddPriceLink
    public class AddPriceLinkRequest
    {
        public int ItemId { get; set; }

        public decimal RetailPrice { get; set; }

        public decimal? WholesalePrice { get; set; }

        public decimal? CostPrice { get; set; }

        [MaxLength(50)]
        public string? Remark { get; set; }

        public int? UserId { get; set; }
    }
}
