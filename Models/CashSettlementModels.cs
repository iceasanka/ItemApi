namespace ItemApi.Models
{
    // Cash Management saved (z_tb_CashSettlement, DBScript U055): one till's cash counted in the back office. Its slip
    // barcode CS-<till code>-<id> is scanned on that till at day end (counted cash) and at the next opening cash.
    public class CashSettlementRow
    {
        public int SettlementId { get; set; }
        public int TerminalId { get; set; }
        public string? TerminalCode { get; set; }
        public string? CashierId { get; set; }
        public string? CashierName { get; set; }
        public decimal CountedCash { get; set; }
        public decimal CashIn { get; set; }
        public decimal CashOut { get; set; }
        public decimal CashierCash { get; set; }
        public decimal ReturnedCoins { get; set; }
        public decimal ReturnedCash { get; set; }
        public decimal BankCash { get; set; }
        public string? Detail { get; set; }
        public int? ZNo { get; set; }
        public DateTime? BusinessDate { get; set; }
        public DateTime? ZLinkedAt { get; set; }
        public int Status { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? CancelledBy { get; set; }
        public DateTime? CancelledAt { get; set; }
        public bool OpeningUsed { get; set; }

        // what the slip barcode holds (the till parses it the same way)
        public string Barcode => $"CS-{TerminalCode}-{SettlementId}";
    }

    // POST api/CashSettlement - the Cash Management page: the tables as on Print, plus the till and the cashier
    public class CashSettlementSaveRequest
    {
        public int TerminalId { get; set; }
        public string? CashierId { get; set; }
        public TableData CashTable { get; set; } = new();     // rows { cash, qty }
        public TableData CreditTable { get; set; } = new();   // rows { credit, amount } - cash in
        public TableData DebitTable { get; set; } = new();    // rows { debit, amount } - cash out
        public decimal CashierCash { get; set; }
        public bool Print { get; set; } = true;
    }

    // POST api/CashSettlement answer
    public class CashSettlementSaveResponse
    {
        public CashSettlementRow Settlement { get; set; } = new();
        public bool Printed { get; set; }
        public string? PrintError { get; set; }
    }

    // GET api/Sync/CashSettlement/{id} - what the till needs from a scanned slip
    public class TillCashSettlement
    {
        public int SettlementId { get; set; }
        public int TerminalId { get; set; }
        public string? TerminalCode { get; set; }
        public decimal CountedCash { get; set; }
        public decimal ReturnedCash { get; set; }
        public decimal BankCash { get; set; }
        public int? ZNo { get; set; }
        public int Status { get; set; }
        public bool OpeningUsed { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class CashierOption
    {
        public string LoginName { get; set; } = "";
        public string? UserName { get; set; }
    }
}
