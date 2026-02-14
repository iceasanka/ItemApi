using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    public class ChequeCreateRepository : IChequeCreateRepository
    {
        private readonly ChequeCreateContext _context;
        private readonly IGoogleSheetService _googleSheetService;
        public ChequeCreateRepository(ChequeCreateContext context, IGoogleSheetService googleSheetService)
        {
            _context = context;
            _googleSheetService = googleSheetService;
        }

        public async Task AddChequeAsync(ChequeCreate cheque)
        {
            try
            {
                await _context.Cheques.AddAsync(cheque);
                await _context.SaveChangesAsync();
            }
            catch (Exception ex)
            {

                throw ex;
            }
           
        }

        // Search cheques by a date range
        public async Task<IEnumerable<ChequeCreate>> SearchChequesByDateRangeAsync(DateTime fromDate, DateTime toDate)
        {
            return await _context.Cheques
                .Where(c => c.ChequeDate >= fromDate && c.ChequeDate <= toDate)
                .ToListAsync();
        }

        // Get all cheques for a specific payee
        public async Task<IEnumerable<ChequeCreate>> GetChequesByPayeeIdAsync(int payeeId)
        {
            return await _context.Cheques
                .Where(c => c.PayeeId == payeeId)
                .ToListAsync();
        }

        // Optional: Get single cheque by ID
        public async Task<ChequeCreate> GetByIdAsync(int id)
        {
            return await _context.Cheques.FindAsync(id);
        }

        // Optional: Delete cheque by ID
        public async Task DeleteChequeAsync(int id)
        {
            var cheque = await _context.Cheques.FindAsync(id);
            if (cheque != null)
            {
                _context.Cheques.Remove(cheque);
                await _context.SaveChangesAsync();
            }
        }

        // Optional: Update cheque
        public async Task UpdateChequeAsync(ChequeCreate cheque)
        {
            _context.Cheques.Update(cheque);
            await _context.SaveChangesAsync();
        }

        public async Task SyncChequesAsync(IEnumerable<ChequeCreate> cheques)
        {
            foreach (var cheque in cheques)
            {
                
                await _googleSheetService.InsertOrUpdateChequeAsync(cheque);
            }
        }

        public async Task SyncPrintedChequeAsync(ChequeCreate cheque)
        {
                await _googleSheetService.InsertOrUpdateChequeAsync(cheque);
        }




    }
}
