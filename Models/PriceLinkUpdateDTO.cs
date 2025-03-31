namespace ItemApi.Models
{
    public class PriceLinkUpdateDTO
    {
        public string ItemCode { get; set; }
        public string ItemDescrip { get; set; }
        public string Loca { get; set; }
        public string UserName { get; set; }
        public int Status { get; set; }
        public decimal Price { get; set; }
        public decimal CostPrice { get; set; }
        public int PackSize { get; set; }
        public decimal EWholePrice { get; set; }
        public decimal PRetPrice { get; set; }
        public decimal PWholePrice { get; set; }
        public int IsUpdateAllLocation { get; set; }
    }
}
