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
        private readonly AppDbContext _context;
        private readonly IGoogleSheetService _googleSheetService;
        public ChequeCreateRepository(AppDbContext context, IGoogleSheetService googleSheetService)
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

        // A cheque written / printed on the Cheque Writer. With a supplier it also goes to the supplier ledger
        // (Docs/StockSystem.md §6.19). The proc's SqlException (Number >= 50000) is the reason it was refused.
        public async Task<ChequeCreate> WriteChequeAsync(Cheque cheque)
        {
            var chequeCreate = new ChequeCreate
            {
                Amount = cheque.amount,
                ChequeDate = cheque.chequeDate,
                PayeeId = cheque.payeeId is > 0 ? cheque.payeeId : null,
                SupplierName = cheque.supplierName,
                PayeeName = string.IsNullOrWhiteSpace(cheque.payee) ? null : cheque.payee.Trim(),
                ChequeNumber = cheque.chequeNumber,
                IsSync = 0
            };
            if ((cheque.suppId ?? 0) > 0)
                await AddChequeForSupplierAsync(chequeCreate, cheque.suppId!.Value, cheque.allocations);
            else
                await AddChequeAsync(chequeCreate);
            return chequeCreate;
        }

        // A cheque for a supplier: the cheque, its PAYMENT row in the supplier ledger and the bills it pays —
        // all or nothing (z_sp_LinkWrittenCheque)
        public async Task AddChequeForSupplierAsync(ChequeCreate cheque, int suppId, List<SupplierAllocation>? allocations)
        {
            await using var tx = await _context.Database.BeginTransactionAsync();
            await _context.Cheques.AddAsync(cheque);
            await _context.SaveChangesAsync();
            var link = await _context.LinkWrittenChequeAsync(cheque.ChequeId, suppId, null, allocations);
            await tx.CommitAsync();
            cheque.SuppId = suppId;
            cheque.LedgerId = link.LedgerId;
        }

        // The bills a cheque paid (supplier ledger PURCHASE rows)
        public async Task<List<ChequeBillRow>> GetChequeBillsAsync(int chequeId)
        {
            // every allocation the cheque's writing made: from its payment row (paid by the cheque) and from
            // returns (deducted)
            var rows = await (from a in _context.SupplierPaymentAllocs
                              join p in _context.SupplierLedgers on a.PaymentLedgerId equals p.LedgerId
                              join l in _context.SupplierLedgers on a.InvoiceLedgerId equals l.LedgerId
                              where a.ChequeId == chequeId
                              select new { l.LedgerId, l.TxnDate, l.ReferenceId, l.InvoiceNo, l.DebitAmount, p.Type, a.Amount })
                             .ToListAsync();
            return rows
                .GroupBy(r => new { r.LedgerId, r.TxnDate, r.ReferenceId, r.InvoiceNo, r.DebitAmount })
                .OrderBy(g => g.Key.TxnDate).ThenBy(g => g.Key.LedgerId)
                .Select(g => new ChequeBillRow
                {
                    LedgerId = g.Key.LedgerId,
                    TxnDate = g.Key.TxnDate,
                    ReferenceId = g.Key.ReferenceId,
                    InvoiceNo = g.Key.InvoiceNo,
                    BillAmount = g.Key.DebitAmount,
                    PaidByCheque = g.Where(r => r.Type != 3).Sum(r => r.Amount),
                    Deducted = g.Where(r => r.Type == 3).Sum(r => r.Amount)
                })
                .ToList();
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
                // a supplier cheque takes its ledger payment with it (its bills are open again)
                await using var tx = await _context.Database.BeginTransactionAsync();
                await _context.UnlinkWrittenChequeAsync(id);
                _context.Cheques.Remove(cheque);
                await _context.SaveChangesAsync();
                await tx.CommitAsync();
            }
        }

        // Optional: Update cheque
        public async Task UpdateChequeAsync(ChequeCreate cheque)
        {
            var entity = await _context.Cheques.FindAsync(cheque.ChequeId);
            if (entity == null) return;
            if (!ReferenceEquals(entity, cheque))
            {
                // the supplier link is made only by z_sp_LinkWrittenCheque: a page that sends the cheque back
                // without it (sync, edit) keeps it
                var (suppId, ledgerId, payeeName) = (entity.SuppId, entity.LedgerId, entity.PayeeName);
                _context.Entry(entity).CurrentValues.SetValues(cheque);
                entity.SuppId = suppId;
                entity.LedgerId = ledgerId;
                entity.PayeeName = cheque.PayeeName ?? payeeName;
            }
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

        public async Task<ChequeUploadResult> ProcessFile(string filePath)
        {
            try
            {
                if (!File.Exists(filePath))
                    throw new Exception("File not found.");

                var result = new ChequeUploadResult { FileName = Path.GetFileName(filePath) };
                var chequeListFromFile = new List<ChequeUploadRow>();

                var lines = await File.ReadAllLinesAsync(filePath);

                for (int i = 3; i < lines.Length; i++)
                {
                    var line = lines[i];
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

                    chequeListFromFile.Add(new ChequeUploadRow
                    {
                        LineNo = i + 1,
                        BankDate = columns[0].Trim(),
                        ChequeNumber = chequeNo,
                        BankAmount = amount
                    });
                }

                result.TotalRows = chequeListFromFile.Count;

                if (!chequeListFromFile.Any())
                    return result;

                foreach (var fileCheque in chequeListFromFile)
                {
                    // Not yet debited first; else any cheque with this number (already debited)
                    var dbCheque = await _context.Cheques
                        .OrderBy(c => c.IsDebited)
                        .FirstOrDefaultAsync(c => c.ChequeNumber == fileCheque.ChequeNumber);

                    if (dbCheque == null)
                    {
                        fileCheque.Status = "NotFound";
                        fileCheque.Message = "Debited by the bank but not in the database.";
                        result.NotFound.Add(fileCheque);
                        continue;
                    }

                    fileCheque.DbAmount = dbCheque.Amount;
                    fileCheque.SupplierName = dbCheque.SupplierName;
                    fileCheque.ChequeDate = dbCheque.ChequeDate;

                    if (dbCheque.IsDebited == 1)
                    {
                        fileCheque.Status = "AlreadyDebited";
                        fileCheque.Message = "Already marked as debited.";
                        result.AlreadyDebited.Add(fileCheque);
                    }
                    // 🔎 DOUBLE CHECK AMOUNT
                    else if (dbCheque.Amount == fileCheque.BankAmount)
                    {
                        dbCheque.IsDebited = 1;
                        await _googleSheetService.MarkChequeAsDebitedAsync(dbCheque);
                        fileCheque.Status = "Debited";
                        fileCheque.Message = "Marked as debited.";
                        result.Debited.Add(fileCheque);
                    }
                    else
                    {
                        fileCheque.Status = "AmountMismatch";
                        fileCheque.Message = $"Amount differs: database {dbCheque.Amount:N2}, bank {fileCheque.BankAmount:N2}.";
                        result.AmountMismatch.Add(fileCheque);
                    }
                }

                await _context.SaveChangesAsync();

                return result;
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

        public byte[] BuildUploadRowsCsv(IEnumerable<ChequeUploadRow> rows)
        {
            using var stream = new MemoryStream();
            using (var writer = new StreamWriter(stream, new System.Text.UTF8Encoding(true)))
            using (var csv = new CsvWriter(writer, CultureInfo.InvariantCulture))
            {
                foreach (var header in new[] { "Line No", "Bank Date", "Cheque No", "Bank Amount", "DB Amount",
                                               "Supplier", "Cheque Date", "Status", "Message" })
                    csv.WriteField(header);
                csv.NextRecord();

                foreach (var r in rows.OrderBy(r => r.LineNo))
                {
                    csv.WriteField(r.LineNo);
                    csv.WriteField(r.BankDate);
                    csv.WriteField(r.ChequeNumber);
                    csv.WriteField(r.BankAmount.ToString("0.00", CultureInfo.InvariantCulture));
                    csv.WriteField(r.DbAmount?.ToString("0.00", CultureInfo.InvariantCulture) ?? "");
                    csv.WriteField(r.SupplierName ?? "");
                    csv.WriteField(r.ChequeDate?.ToString("yyyy-MM-dd") ?? "");
                    csv.WriteField(r.Status);
                    csv.WriteField(r.Message);
                    csv.NextRecord();
                }
            }
            return stream.ToArray();
        }

        public async Task<bool> ChequeNumberExistsAsync(int chequeNumber)
        {
            return await _context.Cheques
                .AnyAsync(c => c.ChequeNumber == chequeNumber);
        }

    }
}
