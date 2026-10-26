using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    // Back office Day Reports (api/DayReport) — rows of the z_sp_DayReport* procs (DBScript/21_BackOffice_DayReports.sql).
    // Bills and cash movements count by their own date (till clock), the Zs by their business date.

    public class DayReport
    {
        public DateTime Date { get; set; }
        public int? TerminalId { get; set; }
        public List<DayTill> Tills { get; set; } = new();
        public List<DayZ> ZReports { get; set; } = new();
        public List<DayCashMovement> CashMovements { get; set; } = new();
    }

    // z_sp_DayReportTills — one row per till. Payments: refunds negative. ExpectedCash = opening + cash + paid in − paid out.
    public class DayTill
    {
        public int TerminalId { get; set; }
        public string TerminalCode { get; set; } = "";
        public string? TerminalName { get; set; }
        public DateTime? LastSyncAt { get; set; }
        public int Bills { get; set; }
        public int Refunds { get; set; }
        public int Voided { get; set; }
        public decimal SalesBeforeDiscount { get; set; }
        public decimal ItemDiscount { get; set; }
        public decimal BillDiscount { get; set; }
        public decimal SalesAmount { get; set; }
        public decimal RefundAmount { get; set; }
        public decimal NetSales { get; set; }
        public decimal Cash { get; set; }
        public decimal Card { get; set; }
        public decimal Bank { get; set; }
        public decimal Cheque { get; set; }
        public decimal OtherPay { get; set; }
        public decimal OpeningCash { get; set; }
        public decimal PaidIn { get; set; }
        public decimal PaidOut { get; set; }
        public decimal ExpectedCash { get; set; }
        public DateTime? FirstBillAt { get; set; }
        public DateTime? LastBillAt { get; set; }
        public DateTime? LastMoveAt { get; set; }
    }

    // z_sp_DayReportZ — Status 2 received, 3 reconciled, 4 mismatch
    public class DayZ
    {
        public int ZId { get; set; }
        public int TerminalId { get; set; }
        public string TerminalCode { get; set; } = "";
        public int ZNo { get; set; }
        public DateTime BusinessDate { get; set; }
        public string? CashierId { get; set; }
        public string? CashierName { get; set; }
        public DateTime? OpenedAt { get; set; }
        public DateTime? ClosedAt { get; set; }
        public int InvoiceCount { get; set; }
        public decimal SalesAmount { get; set; }
        public decimal RefundAmount { get; set; }
        public decimal NetSales { get; set; }
        public decimal CashAmount { get; set; }
        public decimal CardAmount { get; set; }
        public decimal OtherAmount { get; set; }
        public decimal? BankAmount { get; set; }
        public decimal? ChequeAmount { get; set; }
        public decimal ItemDiscount { get; set; }
        public decimal BillDiscount { get; set; }
        public decimal OpeningCash { get; set; }
        public decimal PaidIn { get; set; }
        public decimal PaidOut { get; set; }
        public decimal ExpectedCash { get; set; }
        // false = the till sent no cash in / out for this Z (none made, or a till without U018)
        public bool HasCashMovements { get; set; }
        public int Status { get; set; }
        public string? MismatchNote { get; set; }
    }

    // z_sp_DayReportCash — Kind 1 opening cash, 2 paid in, 3 paid out; Status 1 active, 9 replaced
    public class DayCashMovement
    {
        public int TerminalId { get; set; }
        public string TerminalCode { get; set; } = "";
        public int ZNo { get; set; }
        public int MoveId { get; set; }
        public int Kind { get; set; }
        public decimal Amount { get; set; }
        public string? Reason { get; set; }
        public string? CashierId { get; set; }
        public string? CashierName { get; set; }
        public DateTime CreatedAt { get; set; }
        public int Status { get; set; }
    }

    // z_sp_DayReportItems — Net* = sold − refunded; amounts after the item discount, before the bill discount
    public class DayItem
    {
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        public string? Name { get; set; }
        public bool IsOther { get; set; }
        public decimal SoldQty { get; set; }
        public decimal RefundQty { get; set; }
        public decimal NetQty { get; set; }
        public decimal SoldAmount { get; set; }
        public decimal RefundAmount { get; set; }
        public decimal NetAmount { get; set; }
        public decimal Discount { get; set; }
        public int Bills { get; set; }
        public decimal MinPrice { get; set; }
        public decimal MaxPrice { get; set; }
        // after the bill discount share, lines with a cost only (NULL = none has one); UncostedQty = net qty left out
        public decimal? Cost { get; set; }
        public decimal? Profit { get; set; }
        public decimal UncostedQty { get; set; }
    }

    // z_sp_DayReportBills / z_sp_DayReportBill
    public class DayBill
    {
        public int InvoiceId { get; set; }
        public string InvoiceNo { get; set; } = "";
        public int TerminalId { get; set; }
        public string TerminalCode { get; set; } = "";
        public int ZNo { get; set; }
        public int InvType { get; set; }
        public DateTime InvDate { get; set; }
        public string? CashierId { get; set; }
        public string? CashierName { get; set; }
        public decimal GrossAmount { get; set; }
        public decimal Discount { get; set; }
        public decimal NetAmount { get; set; }
        public int Status { get; set; }
        public int PriceType { get; set; }
        public int Lines { get; set; }
        public decimal ItemDiscount { get; set; }
        public decimal Cash { get; set; }
        public decimal Card { get; set; }
        public decimal OtherPay { get; set; }
        // refunds negative, NULL on a voided bill or when no line has a cost; UncostedLines = lines left out
        public decimal? Cost { get; set; }
        public decimal? Profit { get; set; }
        public int UncostedLines { get; set; }
    }

    // GET api/DayReport/Bill/{invoiceNo} — everything a bill copy shows
    public class DayBillDetail
    {
        public int InvoiceId { get; set; }
        public string InvoiceNo { get; set; } = "";
        public int TerminalId { get; set; }
        public string TerminalCode { get; set; } = "";
        public string? TerminalName { get; set; }
        public int ZNo { get; set; }
        public int InvType { get; set; }
        public DateTime InvDate { get; set; }
        public string? CashierId { get; set; }
        public string? CashierName { get; set; }
        public decimal GrossAmount { get; set; }
        public decimal Discount { get; set; }
        public decimal NetAmount { get; set; }
        public int Status { get; set; }
        public int PriceType { get; set; }
        public decimal ItemDiscount { get; set; }
        public decimal TotalQty { get; set; }
        // filled by separate procs (SqlQuery can't read lists)
        [NotMapped] public List<DayBillLine> Lines { get; set; } = new();
        [NotMapped] public List<DayBillPayment> Payments { get; set; } = new();
    }

    public class DayBillLine
    {
        public int LineNum { get; set; }
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        public string? Name { get; set; }
        public decimal Qty { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal Discount { get; set; }
        public decimal Amount { get; set; }
        public int PriceType { get; set; }
    }

    // PayType 1 cash, 2 card, 3 credit, 4 voucher, 5 bank transfer, 6 cheque
    public class DayBillPayment
    {
        public int LineNum { get; set; }
        public int PayType { get; set; }
        public decimal Amount { get; set; }
        public string? RefNo { get; set; }
    }

    // ─── upload from the tills (POST api/Sync/CashMovements) ────────────────────

    public class SyncCashMovementBatch
    {
        public int TerminalId { get; set; }
        public List<SyncCashMovement> Movements { get; set; } = new();
    }

    // zf_tb_CashMovement row of the till
    public class SyncCashMovement
    {
        public int MoveId { get; set; }
        public int ZNo { get; set; }
        public int Kind { get; set; }
        public decimal Amount { get; set; }
        public string? Reason { get; set; }
        public string? CashierId { get; set; }
        public DateTime CreatedAt { get; set; }
        public int Status { get; set; } = 1;
    }

    public class SyncCashMovementResult
    {
        public int Received { get; set; }
    }

    // ─── Voids & No Sale (api/DayReport/Loss, DBScript/22_BackOffice_VoidReport.sql) ─────────

    public class DayLoss
    {
        public DateTime Date { get; set; }
        public int? TerminalId { get; set; }
        public List<DayLossCashier> Cashiers { get; set; } = new();
        public List<DayVoidLine> Voids { get; set; } = new();
        public List<DayNoSale> NoSales { get; set; } = new();
    }

    // z_sp_DayReportLossCashiers — voids leave out lines of refund bills. VoidPercent = voids / (sales + voids) × 100
    public class DayLossCashier
    {
        public string? CashierId { get; set; }
        public string? CashierName { get; set; }
        public int Bills { get; set; }
        public decimal SalesAmount { get; set; }
        public int VoidLines { get; set; }
        public decimal VoidLineAmount { get; set; }
        public int VoidBills { get; set; }
        public decimal VoidBillAmount { get; set; }
        public int QtyCuts { get; set; }
        public decimal QtyCutAmount { get; set; }
        public decimal VoidTotal { get; set; }
        public decimal VoidPercent { get; set; }
        public int NoSales { get; set; }
        public int DrawerFailed { get; set; }
        public int Refunds { get; set; }
        public decimal RefundAmount { get; set; }
        public int VoidedBills { get; set; }
        public decimal VoidedAmount { get; set; }
    }

    // z_sp_DayReportVoids — Kind 1 void line, 2 void bill (same GroupNo), 3 qty made smaller
    public class DayVoidLine
    {
        public int TerminalId { get; set; }
        public string TerminalCode { get; set; } = "";
        public int VoidId { get; set; }
        public int GroupNo { get; set; }
        public DateTime LoggedAt { get; set; }
        public int Kind { get; set; }
        public int? ZNo { get; set; }
        public string? CashierId { get; set; }
        public string? CashierName { get; set; }
        public bool Refund { get; set; }
        public int ItemId { get; set; }
        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        public string? Name { get; set; }
        public decimal Qty { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal Amount { get; set; }
    }

    // z_sp_DayReportNoSales — Opened false = the drawer did not open
    public class DayNoSale
    {
        public int TerminalId { get; set; }
        public string TerminalCode { get; set; } = "";
        public int DrawerLogId { get; set; }
        public DateTime OpenedAt { get; set; }
        public string? CashierId { get; set; }
        public string? CashierName { get; set; }
        public string? Reason { get; set; }
        public bool Opened { get; set; }
    }

    // ─── upload from the tills (POST api/Sync/TillLog) ──────────────────────────

    public class SyncTillLogBatch
    {
        public int TerminalId { get; set; }
        public List<SyncVoidLog> Voids { get; set; } = new();
        public List<SyncDrawerLog> Drawer { get; set; } = new();
    }

    // zf_tb_VoidLog row of the till
    public class SyncVoidLog
    {
        public int VoidId { get; set; }
        public int GroupNo { get; set; }
        public DateTime LoggedAt { get; set; }
        public int Kind { get; set; }
        public int? ZNo { get; set; }
        public string? CashierId { get; set; }
        public bool Refund { get; set; }
        public int ItemId { get; set; }
        public string? Descrip { get; set; }
        public decimal Qty { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal Amount { get; set; }
    }

    // zf_tb_DrawerLog row of the till
    public class SyncDrawerLog
    {
        public int DrawerLogId { get; set; }
        public DateTime OpenedAt { get; set; }
        public int Kind { get; set; }
        public string? InvoiceNo { get; set; }
        public string? CashierId { get; set; }
        public string? Reason { get; set; }
        public bool Opened { get; set; }
    }

    public class SyncTillLogResult
    {
        public int Voids { get; set; }
        public int Drawer { get; set; }
    }
}
