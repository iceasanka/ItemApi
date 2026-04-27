namespace ItemApi.Models
{
    public class CashierSettlement
    {
        public decimal ReturnedToCashier { get; set; }
        public decimal TotalCashBalance { get; set; }
        public decimal CashierCash { get; set; }
        public decimal ReturnedCoinsValue { get; set; }
        public decimal TotalReturnedToCashier { get; set; }
        public decimal CashBank { get; set; }

        public string? printerName { get; set; }

        public string? printTemplatePath { get; set; }
    }
}
