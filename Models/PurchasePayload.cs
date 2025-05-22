namespace ItemApi.Models
{
    public class PurchasePayload
    {
        public GrnSummary Summary { get; set; }
        public List<PurchaseItem> Items { get; set; }
    }
}
