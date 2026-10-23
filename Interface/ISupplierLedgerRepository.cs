using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ISupplierLedgerRepository
    {
        Task<SupplierLedgerRow> AddLedgerAsync(SupplierLedger ledger);
        Task<SupplierLedgerRow> UpdateLedgerAsync(SupplierLedger ledger);
        Task<bool> DeleteLedgerAsync(int ledgerId);
        Task<List<SupplierLedgerRow>> GetLedgerBySuppIdAsync(int suppId);
        Task<List<SupplierLedgerRow>> GetLedgerByDateRangeAsync(int suppId, DateTime fromDate, DateTime toDate);
        Task<SupplierLedgerSummary?> GetSupplierSummaryAsync(int suppId);
        Task<List<SupplierInvoiceRow>> GetInvoicesAsync(int suppId, bool includePaid);
        Task<List<SupplierPaymentDueRow>> GetPaymentsDueAsync(DateTime? toDate, int? suppId);
        Task<List<SupplierLedgerOverviewRow>> GetOverviewAsync();
        Task<List<SupplierLedgerMonthRow>> GetMonthlyAsync(int? suppId, int months);
    }
}
