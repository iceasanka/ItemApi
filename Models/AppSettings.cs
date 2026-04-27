namespace ItemApi.Models
{
    public class AppSettings
    {
        public string TemplatePath { get; set; }

        public string DataTextFilePath { get; set; }

        public string DiscountPrintTemplatePath {  get; set; }

        public string PricePrintTemplatePath { get; set; }

        public string PrinterName { get; set; }
        public string PrinterHP { get; set; }

        public string DiscountPercentagePrintTemplatePath { get; set; }

        public string LandScapePricePrintTemplatePath { get; set; }


        public string ChequePrintTemplatePath { get; set; }
        public string SettlementTemplatePath { get; set; }
        public string StickerExpireDatePrint { get; set; }
        public string PrinterZebra { get; set; }

        public string Apicre { get; set; }
    }
}
