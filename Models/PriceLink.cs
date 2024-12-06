namespace ItemApi.Models
{
    public class PriceLink
    {
        public string itemcode { get; set; }
        public int packsize { get; set; }
        public decimal costprice { get; set; }
        public decimal price { get; set; }
        public decimal ewholeprice { get; set; }
        public decimal pretprice { get; set; }
        public decimal pwholeprice { get; set; }
    }
}
