namespace ItemApi.Models
{
    public class PrintBarCode
    {
        public string Item_Code { get; set; }
        public string Barcode { get; set; }
        public string Descrip { get; set; }
        public string ERet_Price { get; set; }
        public string expireDate { get; set; }
        public string mrDate { get; set; }

        public string? printerName { get; set; }

        public string? printTemplatePath { get; set; }
        public int lblCount { get; set; }
    }
}
