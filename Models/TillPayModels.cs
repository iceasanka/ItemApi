namespace ItemApi.Models
{
    // Supplier bills paid in cash from a till (DBScript/26_BackOffice_TillPayments.sql, Updates/U032, StockSystem.md 6.32).

    // POST api/SupplierLedger/TillPay — a request from the Supplier Ledger page
    public class TillPayRequestCreate
    {
        public int SuppId { get; set; }
        // the till to pay it; null = any till
        public int? TerminalId { get; set; }
        // the cash to pay (the bills less the returns, or less = a part payment)
        public decimal Amount { get; set; }
        // the paid out reason on the till; empty = "Supplier <name>"
        public string? Remark { get; set; }
        public int? UserId { get; set; }
        // bills (PURCHASE) and returns (RETURN) picked, with the amount of each to settle / use
        public List<TillPayLine> Lines { get; set; } = new();
    }

    public class TillPayLine
    {
        public int LedgerId { get; set; }
        public decimal Amount { get; set; }
    }

    // z_sp_GetTillPayRequests. Status 0 waiting, 1 paid, 2 cancelled.
    public class TillPayRequestRow
    {
        public int RequestId { get; set; }
        public int SuppId { get; set; }
        public string? SuppName { get; set; }
        public int? TerminalId { get; set; }
        public string? TerminalCode { get; set; }
        public decimal Amount { get; set; }
        public string Remark { get; set; } = "";
        public int Status { get; set; }
        public DateTime CreatedAt { get; set; }
        public int? CreatedBy { get; set; }
        public DateTime? CancelledAt { get; set; }
        public DateTime? PaidAt { get; set; }
        public int? PaidTerminalId { get; set; }
        public string? PaidTerminalCode { get; set; }
        public int? PaidMoveId { get; set; }
        public string? PaidCashierId { get; set; }
        public decimal? PaidAmount { get; set; }
        public int? PaymentLedgerId { get; set; }
        public string? PaymentRef { get; set; }
        public decimal BillsAmount { get; set; }
        public decimal ReturnsAmount { get; set; }
        public string? Refs { get; set; }
    }

    public class TillPayRequestId { public int RequestId { get; set; } }

    // ─── till sync ───

    // GET api/Sync/TillPayRequests?terminalId= — what this till may pay now (copy in TillService/Models/TillModels.cs)
    public class SyncTillPayRequest
    {
        public int RequestId { get; set; }
        public string? SuppName { get; set; }
        public decimal Amount { get; set; }
        public string Remark { get; set; } = "";
        public DateTime? CreatedAt { get; set; }
    }

    // POST api/Sync/TillPayRequests — the paid outs a till made for requests
    public class SyncTillPayPaidBatch
    {
        public int TerminalId { get; set; }
        public List<SyncTillPayPaid> Rows { get; set; } = new();
    }

    public class SyncTillPayPaid
    {
        public int RequestId { get; set; }
        public int MoveId { get; set; }
        public int? ZNo { get; set; }
        public decimal Amount { get; set; }
        public string? CashierId { get; set; }
        public DateTime PaidAt { get; set; }
    }

    public class SyncTillPayPaidResult { public int Received { get; set; } }
}
