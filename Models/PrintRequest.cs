namespace ItemApi.Models
{
    public class PrintRequest
    {
        public TableData CashTable { get; set; }
        public TableData CreditTable { get; set; }
        public TableData DebitTable { get; set; }
        public decimal TotalCashBalance { get; set; }
    }
}
