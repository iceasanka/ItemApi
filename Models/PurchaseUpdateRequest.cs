namespace ItemApi.Models
{
    public class PurchaseUpdateRequest
    {
        public int UpdateStatus { get; set; }
        public string SerialNo { get; set; }
        public string SuppCode { get; set; }
        public string ItemCode { get; set; }
        public string Descrip { get; set; }
        public string LocaCode { get; set; }
        public string PackScale { get; set; }
        public string Unit { get; set; }
        public decimal Cost { get; set; }
        public decimal Rate { get; set; }
        public decimal ERate { get; set; }
        public double Qty { get; set; }
        public string DiscP { get; set; }
        public decimal Discount { get; set; }
        public decimal Amount { get; set; }
        public string Id { get; set; }
        public string UserName { get; set; }
        public double PackSize { get; set; }
        public string Remark { get; set; }
        public string BarcodeSrl { get; set; }
        public string CSCode { get; set; }
        public string CSName { get; set; }
        public int RowNo { get; set; }
        public decimal Nbt { get; set; }
        public decimal Tax { get; set; }
        public string ManufactureDate { get; set; }
    }
}
