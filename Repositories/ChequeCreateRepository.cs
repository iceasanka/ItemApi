using CsvHelper;
using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.EntityFrameworkCore;
using System.Globalization;

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

        // Search cheques with optional filters
        public async Task<IEnumerable<ChequeCreate>> SearchChequesByDateRangeAsync(
            DateTime fromDate,
            DateTime toDate,
            int? chequeNumber,
            string? supplierName,
            decimal? amount)
        {
            var query = _context.Cheques.Where(c => c.ChequeDate >= fromDate && c.ChequeDate <= toDate);

            if (chequeNumber.HasValue)
                query = query.Where(c => c.ChequeNumber == chequeNumber.Value);

            if (!string.IsNullOrWhiteSpace(supplierName))
                query = query.Where(c => c.SupplierName.Contains(supplierName));

            if (amount.HasValue)
                query = query.Where(c => c.Amount == amount.Value);

            return await query.ToListAsync();
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

        public async Task ProcessFile(string filePath)
        {
            try
            {
                if (!File.Exists(filePath))
                    throw new Exception("File not found.");

                var chequeListFromFile = new List<(int ChequeNumber, decimal Amount)>();

                var lines = await File.ReadAllLinesAsync(filePath);

                foreach (var line in lines.Skip(3))
                {
                    if (string.IsNullOrWhiteSpace(line))
                        continue;

                    var columns = ParseCsvLine(line);

                    if (columns.Count < 8)
                        continue;

                    string debitStr = columns[6];
                    string chequeNoStr = columns.Last();

                    if (string.IsNullOrWhiteSpace(chequeNoStr))
                        continue;

                    if (!int.TryParse(chequeNoStr, out int chequeNo))
                        continue;

                    debitStr = debitStr.Replace(",", "");

                    if (!decimal.TryParse(debitStr, out decimal amount))
                        continue;

                    chequeListFromFile.Add((chequeNo, amount));
                }

                if (!chequeListFromFile.Any())
                    return;

                foreach (var fileCheque in chequeListFromFile)
                {
                    var dbCheque = await _context.Cheques
                        .FirstOrDefaultAsync(c => c.ChequeNumber == fileCheque.ChequeNumber
                                               && c.IsDebited == 0);

                    if (dbCheque != null)
                    {
                        // 🔎 DOUBLE CHECK AMOUNT
                        if (dbCheque.Amount == fileCheque.Amount)
                        {
                            dbCheque.IsDebited = 1;
                            await _googleSheetService.MarkChequeAsDebitedAsync(dbCheque);
                        }
                        else
                        {
                            // Optional: log mismatch
                            Console.WriteLine($"Amount mismatch for Cheque {fileCheque.ChequeNumber} | DB: {dbCheque.Amount} | File: {fileCheque.Amount}");
                        }
                    }
                }

                await _context.SaveChangesAsync();
            }
            catch (Exception ex)
            {
                throw ex;
            }
        }

        private List<string> ParseCsvLine(string line)
        {
            var result = new List<string>();
            bool inQuotes = false;
            string current = "";

            foreach (char c in line)
            {
                if (c == '"')
                {
                    inQuotes = !inQuotes;
                }
                else if (c == ',' && !inQuotes)
                {
                    result.Add(current);
                    current = "";
                }
                else
                {
                    current += c;
                }
            }

            result.Add(current);

            return result;
        }



    }
}
