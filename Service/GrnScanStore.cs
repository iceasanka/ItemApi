using System.Text.Json;
using ItemApi.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Service
{
    // Saved scans (z_tb_GrnScan, U031, Docs/StockSystem.md 6.31): every read is kept with the page's work (fixes, picks,
    // lines left out), so the matching can go on another day without reading the photo again. The photos stay in the
    // read's folder (GrnScan:SaveFolder). Flush = the row and its photo folder are deleted.
    public class GrnScanStore
    {
        private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

        private readonly AppDbContext _db;
        private readonly GrnScanReader _reader;
        private readonly ILogger<GrnScanStore> _log;

        public GrnScanStore(AppDbContext db, GrnScanReader reader, ILogger<GrnScanStore> log)
        {
            _db = db;
            _reader = reader;
            _log = log;
        }

        // a new read; null when the db has no U031 yet (the read still works, it is just not kept)
        public async Task<int?> AddAsync(GrnScanResult result, int? suppId, int? userId)
        {
            var doc = new GrnScanDoc
            {
                SuppId = suppId > 0 ? suppId : null, Folder = result.SavedAs, Pages = result.Images,
                CreatedAt = DateTime.Now, CreatedBy = userId
            };
            Fill(doc, result, new GrnScanState());
            _db.GrnScanDocs.Add(doc);
            try
            {
                await _db.SaveChangesAsync();
            }
            catch (DbUpdateException ex) when (ex.InnerException is SqlException { Number: 208 })
            {
                _db.Entry(doc).State = EntityState.Detached;
                _log.LogWarning("GrnScan: the read is not kept - run U031_BackOffice_GrnScanStore.sql");
                return null;
            }
            return doc.ScanId;
        }

        public async Task SaveStateAsync(int scanId, GrnScanSaveStateRequest r, int? userId)
        {
            var doc = await _db.GrnScanDocs.FirstOrDefaultAsync(d => d.ScanId == scanId) ?? throw new KeyNotFoundException();
            if (r.SupplierId > 0) doc.SuppId = r.SupplierId;
            r.Result.ScanId = scanId;
            Fill(doc, r.Result, r.State);
            doc.UpdatedAt = DateTime.Now;
            doc.UpdatedBy = userId;
            await _db.SaveChangesAsync();
        }

        public async Task MarkDraftAsync(int scanId, string grnNo, int? userId)
        {
            var doc = await _db.GrnScanDocs.FirstOrDefaultAsync(d => d.ScanId == scanId);
            if (doc == null) return;
            doc.Status = 1;
            doc.GrnNo = grnNo;
            doc.UpdatedAt = DateTime.Now;
            doc.UpdatedBy = userId;
            await _db.SaveChangesAsync();
        }

        // The GRN draft made from a scan is deleted (something to correct): the suspended GRN and its lines go, the scan is
        // open again so it can be fixed and made into a GRN again. Refused once the GRN is committed to stock (Status 2).
        // → the GRN no deleted
        public async Task<string> DeleteDraftAsync(int scanId, int? userId)
        {
            var doc = await _db.GrnScanDocs.FirstOrDefaultAsync(d => d.ScanId == scanId) ?? throw new KeyNotFoundException();
            if (doc.Status != 1 || string.IsNullOrEmpty(doc.GrnNo)) throw new GrnScanException("No GRN draft is made from this scan.");
            var grnNo = doc.GrnNo;
            await using var tx = await _db.Database.BeginTransactionAsync();
            var posted = await _db.Database.SqlQueryRaw<int>(
                "SELECT COUNT(*) AS Value FROM dbo.z_tb_TempPurchaseSummary WITH (UPDLOCK, HOLDLOCK) WHERE GrnNo = @p0 AND Status = 2",
                grnNo).SingleAsync();
            if (posted > 0) throw new GrnScanException($"{grnNo} is committed to stock - it can't be deleted.");
            await _db.Database.ExecuteSqlRawAsync("DELETE FROM dbo.z_tb_TempPurchase WHERE GrnNo = @p0 AND ISNULL(Status, 0) <> 2", grnNo);
            await _db.Database.ExecuteSqlRawAsync("DELETE FROM dbo.z_tb_TempPurchaseSummary WHERE GrnNo = @p0 AND ISNULL(Status, 0) <> 2", grnNo);
            doc.Status = 0;
            doc.GrnNo = null;
            doc.UpdatedAt = DateTime.Now;
            doc.UpdatedBy = userId;
            await _db.SaveChangesAsync();
            await tx.CommitAsync();
            return grnNo;
        }

        // newest first: open ones = not made into a GRN yet, or its GRN not committed to stock yet (still a draft, or the
        // draft deleted on GRN Entry); all = also those whose GRN is committed
        public async Task<List<GrnScanListRow>> ListAsync(bool all)
        {
            var q = from d in _db.GrnScanDocs.AsNoTracking()
                    join s in _db.SupplierEntities on d.SuppId equals s.SuppId into sup
                    from s in sup.DefaultIfEmpty()
                    let grnStatus = _db.TempPurchaseSummaries.Where(t => t.GrnNo == d.GrnNo).Select(t => t.Status).FirstOrDefault()
                    where all || d.Status == 0 || grnStatus == null || grnStatus != 2
                    orderby d.CreatedAt descending
                    select new GrnScanListRow
                    {
                        ScanId = d.ScanId, SuppId = d.SuppId, SuppName = s != null ? s.SuppName : null, InvoiceNo = d.InvoiceNo,
                        InvoiceDate = d.InvoiceDate, Pages = d.Pages, Lines = d.Lines, Matched = d.Matched, Status = d.Status,
                        GrnNo = d.GrnNo, GrnStatus = d.Status == 1 ? grnStatus : null, CreatedAt = d.CreatedAt, UpdatedAt = d.UpdatedAt
                    };
            return await q.Take(200).ToListAsync();
        }

        public async Task<GrnScanOpen?> GetAsync(int scanId)
        {
            var doc = await _db.GrnScanDocs.AsNoTracking().FirstOrDefaultAsync(d => d.ScanId == scanId);
            if (doc == null) return null;
            var supp = doc.SuppId == null ? null : await _db.SupplierEntities.AsNoTracking().FirstOrDefaultAsync(s => s.SuppId == doc.SuppId);
            var result = JsonSerializer.Deserialize<GrnScanResult>(doc.ResultJson, Json) ?? new GrnScanResult();
            result.ScanId = doc.ScanId;
            var grnStatus = doc.Status == 1 && doc.GrnNo != null
                ? await _db.TempPurchaseSummaries.AsNoTracking().Where(t => t.GrnNo == doc.GrnNo).Select(t => t.Status).FirstOrDefaultAsync()
                : null;
            return new GrnScanOpen
            {
                ScanId = doc.ScanId, SuppId = doc.SuppId, SuppName = supp?.SuppName, Status = doc.Status, GrnNo = doc.GrnNo, GrnStatus = grnStatus,
                Pages = PhotoFiles(doc.Folder).Count, Result = result,
                State = string.IsNullOrEmpty(doc.StateJson) ? new GrnScanState() : JsonSerializer.Deserialize<GrnScanState>(doc.StateJson, Json) ?? new GrnScanState()
            };
        }

        // page = 1, 2, ...; null = no such photo
        public async Task<string?> PhotoAsync(int scanId, int page)
        {
            var folder = await _db.GrnScanDocs.AsNoTracking().Where(d => d.ScanId == scanId).Select(d => d.Folder).FirstOrDefaultAsync();
            var files = PhotoFiles(folder);
            return page >= 1 && page <= files.Count ? files[page - 1] : null;
        }

        // deletes the scans and their photo folders → how many
        public async Task<int> FlushAsync(List<int> scanIds)
        {
            var docs = await _db.GrnScanDocs.Where(d => scanIds.Contains(d.ScanId)).ToListAsync();
            foreach (var d in docs)
            {
                var dir = _reader.ScanFolder(d.Folder);
                try
                {
                    if (dir != null && Directory.Exists(dir)) Directory.Delete(dir, true);
                }
                catch (Exception ex)
                {
                    // the row still goes; a folder left behind holds only the photos
                    _log.LogWarning(ex, "GrnScan: photos of scan {ScanId} not deleted ({Dir})", d.ScanId, dir);
                }
            }
            _db.GrnScanDocs.RemoveRange(docs);
            await _db.SaveChangesAsync();
            return docs.Count;
        }

        private List<string> PhotoFiles(string? folder)
        {
            var dir = _reader.ScanFolder(folder);
            if (dir == null || !Directory.Exists(dir)) return new List<string>();
            return Directory.GetFiles(dir, "page*.*")
                .Where(f => GrnScanReader.ImageType(f) != null)
                .OrderBy(f => int.TryParse(Path.GetFileNameWithoutExtension(f)[4..], out var n) ? n : 99)
                .ToList();
        }

        private static void Fill(GrnScanDoc doc, GrnScanResult result, GrnScanState state)
        {
            doc.InvoiceNo = Cut(result.Header.InvoiceNo, 50);
            doc.InvoiceDate = Cut(result.Header.InvoiceDate, 20);
            doc.Lines = result.Lines.Count;
            doc.Matched = result.Lines.Where((l, i) => l.ItemId != null || state.Picks.ContainsKey(i)).Count();
            doc.ResultJson = JsonSerializer.Serialize(result, Json);
            doc.StateJson = JsonSerializer.Serialize(state, Json);
        }

        private static string? Cut(string? s, int max) => s == null ? null : s.Length > max ? s[..max] : s;
    }
}
