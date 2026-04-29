using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ISupplierLedgerRepository
    {
        Task<SupplierLedger> AddLedgerAsync(SupplierLedger ledger);
        Task<SupplierLedger> UpdateLedgerAsync(SupplierLedger ledger);
        Task<bool> DeleteLedgerAsync(int ledgerId);
        Task<List<SupplierLedger>> GetLedgerBySuppIdAsync(int suppId);
        Task<List<SupplierLedger>> GetLedgerByDateRangeAsync(int suppId, DateTime fromDate, DateTime toDate);
        Task<SupplierLedgerSummary?> GetSupplierSummaryAsync(int suppId);
    }
}
