namespace ItemApi.Models
{
    public class PrintBarcodeRequest
    {
        public ItemWithDetails ItemDetails { get; set; }
        public int LabelCount { get; set; }

        public string expireDate { get; set; }
        public string mrDate { get; set; }
    }
}
