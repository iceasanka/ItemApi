namespace ItemApi.Models
{
    // A GRN line whose cost looks wrong, found before the GRN goes to stock (GRN Entry > Commit). A cost above the sell
    // price, or far from our cost now, is most often a case / line total typed (or read by GRN scan) as the cost a piece.
    public class GrnCostCheckLine
    {
        public long LineNum { get; set; }
        public int ItemId { get; set; }
        public string? Descrip { get; set; }
        public decimal Qty { get; set; }
        public decimal Cost { get; set; }
        public decimal? SellPrice { get; set; }
        public decimal? OurCost { get; set; }
        public string Reason { get; set; } = "";
    }
}
