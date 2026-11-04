namespace ItemApi.Models
{
    // POST api/SupplierLedger/Till — a supplier ledger entry typed at a till (Menu > Add ledger entry), sent live by
    // TillService with the shared terminal key. Amount = Qty x Price (worked out here, rounded to cents).
    public class TillLedgerRequest
    {
        public int TerminalId { get; set; }
        public string? CashierId { get; set; }
        public int SuppId { get; set; }
        /// <summary>1 = PURCHASE (debit), 2 = PAYMENT (credit), 3 = RETURN (credit)</summary>
        public int Type { get; set; } = 1;
        public decimal Qty { get; set; }
        public decimal Price { get; set; }
        public string? InvoiceNo { get; set; }
        public string? Remark { get; set; }
    }

    // GET api/SupplierLedger/Till/Suppliers — the active suppliers for the till's picker
    public class TillSupplierRow
    {
        public int SuppId { get; set; }
        public string SuppCode { get; set; } = "";
        public string SuppName { get; set; } = "";
    }
}
