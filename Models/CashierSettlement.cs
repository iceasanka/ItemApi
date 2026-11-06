namespace ItemApi.Models
{
    // Cash Management > Print Settlement (api/Util/printCashierSettlement) - printed as an ESC/POS slip (Service/ReceiptSlip.cs)
    public class CashierSettlement
    {
        public decimal ReturnedToCashier { get; set; }
        public decimal TotalCashBalance { get; set; }
        public decimal CashierCash { get; set; }
        public decimal ReturnedCoinsValue { get; set; }
        public decimal TotalReturnedToCashier { get; set; }
        public decimal CashBank { get; set; }
    }
}
