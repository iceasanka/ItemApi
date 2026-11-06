namespace ItemApi.Models
{
    // Cash Management > Print (api/Util/print) - printed as an ESC/POS slip (Service/ReceiptSlip.cs)
    public class PrintRequest
    {
        public TableData CashTable { get; set; } = new();     // rows { cash, qty }
        public TableData CreditTable { get; set; } = new();   // rows { credit, amount } - cash in
        public TableData DebitTable { get; set; } = new();    // rows { debit, amount } - cash out
        public decimal TotalCashBalance { get; set; }
        public decimal CashierCash { get; set; }
        public decimal ReturnedCoinsValue { get; set; }
        public decimal TotalReturnedToCashier { get; set; }
        public decimal FinalCashBalance { get; set; }
    }
}
