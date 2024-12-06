namespace ItemApi.Models
{
    public class DeleteTempPurchaseRequest
    {
        public string SerialNo { get; set; }
        public string ID { get; set; }
        public string LocaCode { get; set; }
        public string UserName { get; set; }
        public string ItemCode { get; set; }
        public decimal Cost { get; set; }
        public string IdNo { get; set; }
        public int CancelAll { get; set; }
    }
}
