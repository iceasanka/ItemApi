using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;

namespace ItemApi.Repositories
{
    public class SupplierLedgerRepository : ISupplierLedgerRepository
    {
        private readonly AppDbContext _context;

        public SupplierLedgerRepository(AppDbContext context)
        {
            _context = context;
        }

        public async Task<SupplierLedgerRow> AddLedgerAsync(SupplierLedger ledger)
        {
            ledger.LedgerId = 0;
            var saved = await _context.SaveLedgerAsync(ledger);
            return await GetRowAsync(ledger.SuppId ?? 0, saved.LedgerId);
        }

        public async Task<SupplierLedgerRow> UpdateLedgerAsync(SupplierLedger ledger)
        {
            var saved = await _context.SaveLedgerAsync(ledger);
            return await GetRowAsync(ledger.SuppId ?? 0, saved.LedgerId);
        }

        public async Task<bool> DeleteLedgerAsync(int ledgerId)
        {
            return await _context.DeleteLedgerAsync(ledgerId);
        }

        public async Task<List<SupplierLedgerRow>> GetLedgerBySuppIdAsync(int suppId)
        {
            return await _context.GetLedgerRowsAsync(suppId);
        }

        public async Task<List<SupplierLedgerRow>> GetLedgerByDateRangeAsync(int suppId, DateTime fromDate, DateTime toDate)
        {
            return await _context.GetLedgerRowsAsync(suppId, fromDate, toDate);
        }

        public async Task<SupplierLedgerSummary?> GetSupplierSummaryAsync(int suppId)
        {
            return await _context.GetSupplierSummaryAsync(suppId);
        }

        public async Task<List<SupplierInvoiceRow>> GetInvoicesAsync(int suppId, bool includePaid)
        {
            return await _context.GetSupplierInvoicesAsync(suppId, includePaid);
        }

        public async Task<List<SupplierPaymentDueRow>> GetPaymentsDueAsync(DateTime? toDate, int? suppId)
        {
            return await _context.GetSupplierPaymentsDueAsync(toDate, suppId);
        }

        // the saved line as the ledger page shows it (with reference, due date and running balance)
        private async Task<SupplierLedgerRow> GetRowAsync(int suppId, int ledgerId)
        {
            var rows = await _context.GetLedgerRowsAsync(suppId);
            return rows.First(r => r.LedgerId == ledgerId);
        }
    }
}
