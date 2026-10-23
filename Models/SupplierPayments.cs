using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ItemApi.Models
{
    // Supplier bills -> cheques (Docs/StockSystem.md §6.19, DBScript/Updates/U007_BackOffice_SupplierPayments.sql)

    // z_tb_SupplierPaymentAlloc: a PAYMENT / RETURN ledger row pays (part of) a bill (PURCHASE ledger row)
    [Table("z_tb_SupplierPaymentAlloc")]
    public class SupplierPaymentAlloc
    {
        [Key]
        public int AllocId { get; set; }
        public int PaymentLedgerId { get; set; }
        public int InvoiceLedgerId { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal Amount { get; set; }
        // the cheque whose writing made this row (null = set on the ledger page)
        public int? ChequeId { get; set; }
        public DateTime CDate { get; set; }
    }

    // a bill and how much of it a payment / cheque pays (z_tt_SupplierAlloc)
    public class SupplierAllocation
    {
        public int LedgerId { get; set; }
        // paid by this payment / cheque ("cheque pay")
        public decimal Amount { get; set; }
        // cheques only: taken off the bill for returns — Amount + Deduction is settled, so a bill paid
        // "less returns" is Paid. Set against the supplier's open returns, else a new RETURN row.
        public decimal Deduction { get; set; }
    }

    // z_sp_SaveSupplierLedger / z_sp_LinkWrittenCheque
    public class SupplierLedgerSaveResult
    {
        public int LedgerId { get; set; }
        public string? ReferenceId { get; set; }
    }

    // z_Sp_GetSupplierLedger: one ledger line with the running balance
    public class SupplierLedgerRow
    {
        public int LedgerId { get; set; }
        public int? SuppId { get; set; }
        public DateTime TxnDate { get; set; }
        public int Type { get; set; }
        public string? TypeName { get; set; }
        public string? ReferenceId { get; set; }
        public string? InvoiceNo { get; set; }
        public string? Remark { get; set; }
        public decimal DebitAmount { get; set; }
        public decimal CreditAmount { get; set; }
        public DateTime? DueDate { get; set; }
        public int? ChequeId { get; set; }
        public int? ChequeNumber { get; set; }
        public DateTime? ChequeDate { get; set; }
        public int? ChequeDebited { get; set; }
        // bill: paid so far. payment / return: how much of it pays bills
        public decimal AllocatedAmount { get; set; }
        // bill: still to pay (0 for payments)
        public decimal OpenAmount { get; set; }
        public decimal? RunningBalance { get; set; }
        public int? UserId { get; set; }
        public DateTime? CDate { get; set; }
        public DateTime? UDate { get; set; }
    }

    // z_sp_GetSupplierInvoices: a supplier's bills for the cheque writer
    public class SupplierInvoiceRow
    {
        public int LedgerId { get; set; }
        public int? SuppId { get; set; }
        public DateTime TxnDate { get; set; }
        public string? ReferenceId { get; set; }
        public string? InvoiceNo { get; set; }
        public string? Remark { get; set; }
        public DateTime? DueDate { get; set; }
        public int? DaysToDue { get; set; }
        public decimal Amount { get; set; }
        public decimal PaidAmount { get; set; }
        // part of PaidAmount settled by returns
        public decimal DeductedAmount { get; set; }
        public decimal OpenAmount { get; set; }
        // Open / Part paid / Paid
        public string? Status { get; set; }
        // "900001 (23,000.00), RETURN SUP001-00004 (2,000.00), PAYMENT SUP001-00005 (500.00)"
        public string? PaidBy { get; set; }
    }

    // z_sp_GetSupplierPaymentsDue: open bills due on or before a date (overdue too)
    public class SupplierPaymentDueRow
    {
        public int LedgerId { get; set; }
        public int SuppId { get; set; }
        public string? SuppCode { get; set; }
        public string? SuppName { get; set; }
        public string? PayeeName { get; set; }
        public int? CreditDays { get; set; }
        public DateTime TxnDate { get; set; }
        public string? ReferenceId { get; set; }
        public string? InvoiceNo { get; set; }
        public DateTime? DueDate { get; set; }
        public int? DaysToDue { get; set; }
        public decimal Amount { get; set; }
        public decimal PaidAmount { get; set; }
        public decimal OpenAmount { get; set; }
    }

    // z_sp_GetSupplierLedgerOverview (U015): one supplier on the Supplier Ledger overview
    public class SupplierLedgerOverviewRow
    {
        public int SuppId { get; set; }
        public string? SuppCode { get; set; }
        public string? SuppName { get; set; }
        public int? CreditDays { get; set; }
        public decimal Purchases { get; set; }
        public decimal Payments { get; set; }
        public decimal Returns { get; set; }
        public decimal Balance { get; set; }
        public int OpenBills { get; set; }
        public decimal OpenAmount { get; set; }
        // open bills not past their due date (or with no due date)
        public decimal NotDue { get; set; }
        public decimal Overdue { get; set; }
        // open bills due today .. today + 7
        public decimal DueIn7 { get; set; }
        // overdue by 1-30 / 31-60 / 61-90 / over 90 days
        public decimal Over1To30 { get; set; }
        public decimal Over31To60 { get; set; }
        public decimal Over61To90 { get; set; }
        public decimal Over90 { get; set; }
        public DateTime? OldestDueDate { get; set; }
        // payments + returns not set against a bill (Balance = OpenAmount - Unallocated)
        public decimal Unallocated { get; set; }
        // days from bill to payment, weighted by the amount paid
        public decimal? AvgDaysToPay { get; set; }
        public int Entries { get; set; }
        public DateTime? LastPurchaseDate { get; set; }
        public DateTime? LastPaymentDate { get; set; }
    }

    // z_sp_GetSupplierLedgerMonthly (U015)
    public class SupplierLedgerMonthRow
    {
        public DateTime MonthStart { get; set; }
        public decimal Purchases { get; set; }
        public decimal Payments { get; set; }
        public decimal Returns { get; set; }
    }

    // GET api/ChequeCreate/{id}/bills: what a cheque paid
    public class ChequeBillRow
    {
        public int LedgerId { get; set; }
        public DateTime TxnDate { get; set; }
        public string? ReferenceId { get; set; }
        public string? InvoiceNo { get; set; }
        public decimal BillAmount { get; set; }
        public decimal PaidByCheque { get; set; }
        // returns taken off this bill when the cheque was written
        public decimal Deducted { get; set; }
    }
}
