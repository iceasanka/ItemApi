using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Serilog;

namespace ItemApi.Repositories
{
    public class SupplierLedgerRepository : ISupplierLedgerRepository
    {
        private readonly AppDbContext _context;

        public SupplierLedgerRepository(AppDbContext context)
        {
            _context = context;
        }

        public async Task<SupplierLedger> AddLedgerAsync(SupplierLedger ledger)
        {
            return await _context.AddLedgerAsync(ledger);
        }

        public async Task<SupplierLedger> UpdateLedgerAsync(SupplierLedger ledger)
        {
            return await _context.UpdateLedgerAsync(ledger);
        }

        public async Task<bool> DeleteLedgerAsync(int ledgerId)
        {
            return await _context.DeleteLedgerAsync(ledgerId);
        }

        public async Task<List<SupplierLedger>> GetLedgerBySuppIdAsync(int suppId)
        {
            return await _context.GetLedgerBySuppIdAsync(suppId);
        }

        public async Task<List<SupplierLedger>> GetLedgerByDateRangeAsync(int suppId, DateTime fromDate, DateTime toDate)
        {
            return await _context.GetLedgerByDateRangeAsync(suppId, fromDate, toDate);
        }

        public async Task<SupplierLedgerSummary?> GetSupplierSummaryAsync(int suppId)
        {
            return await _context.GetSupplierSummaryAsync(suppId);
        }
    }
}
