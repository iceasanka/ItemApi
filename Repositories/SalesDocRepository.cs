using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace ItemApi.Repositories
{
    // Back office quotations and invoices — DOCUMENT ONLY: no stock movement, no customer balance, no tax.
    //   - quotation: editable while open; "Make invoice" copies it into a new invoice and marks it invoiced (once).
    //   - invoice: editable while open (not cancelled). Cancelling an invoice made from a quotation opens the
    //     quotation again, so it can be invoiced again. An invoiced quotation is frozen — change its invoice.
    // Customer details are copied onto the document so a reprint never changes. Docs/StockSystem.md §6.11.
    public class SalesDocRepository : ISalesDocRepository
    {
        private const int MaxLines = 200;

        private readonly AppDbContext _context;
        private readonly int _locationId;

        public SalesDocRepository(AppDbContext context, IOptions<AppSettings> appSettings)
        {
            _context = context;
            _locationId = appSettings.Value.LocationId;
        }

        public async Task<SalesDocSearchResult> SearchAsync(SalesDocSearchRequest r)
        {
            var q = _context.SalesDocs.AsNoTracking().Where(d => d.LocationId == _locationId);
            if (r.DocType.HasValue) q = q.Where(d => d.DocType == r.DocType);
            if (r.FromDate.HasValue) q = q.Where(d => d.DocDate >= r.FromDate.Value.Date);
            if (r.ToDate.HasValue) q = q.Where(d => d.DocDate <= r.ToDate.Value.Date);
            if (r.CustomerId.HasValue) q = q.Where(d => d.CustomerId == r.CustomerId);
            if (r.Status.HasValue) q = q.Where(d => d.Status == r.Status);
            var t = (r.Text ?? "").Trim();
            if (t.Length > 0)
                q = q.Where(d => d.DocNo.Contains(t) || d.CustName.Contains(t) || (d.Reference != null && d.Reference.Contains(t)));

            var pageSize = Math.Clamp(r.PageSize, 1, 200);
            var page = Math.Max(r.Page, 1);
            var total = await q.CountAsync();
            // production easyway runs on SQL Server 2008 R2: no OFFSET/FETCH, so TOP (page * pageSize) and skip here
            var rows = (await q
                .OrderByDescending(d => d.DocDate).ThenByDescending(d => d.DocId)
                .Take(page * pageSize)
                .Select(d => new SalesDocRow
                {
                    DocId = d.DocId, DocType = d.DocType, DocNo = d.DocNo, DocDate = d.DocDate, ValidUntil = d.ValidUntil,
                    CustomerId = d.CustomerId, CustName = d.CustName, Reference = d.Reference,
                    LineCount = d.Items.Count, NetAmount = d.NetAmount, Status = d.Status, FromDocId = d.FromDocId,
                    FromDocNo = _context.SalesDocs.Where(f => f.DocId == d.FromDocId).Select(f => f.DocNo).FirstOrDefault(),
                    InvoiceDocNo = _context.SalesDocs
                        .Where(i => i.FromDocId == d.DocId && i.Status != SalesDocStatus.Cancelled)
                        .Select(i => i.DocNo).FirstOrDefault(),
                    CDate = d.CDate
                })
                .ToListAsync()).Skip((page - 1) * pageSize).ToList();
            return new SalesDocSearchResult { Total = total, Rows = rows };
        }

        public async Task<SalesDocDetail?> GetAsync(int docId)
        {
            var doc = await _context.SalesDocs.AsNoTracking().Include(d => d.Items)
                .FirstOrDefaultAsync(d => d.DocId == docId && d.LocationId == _locationId);
            if (doc == null) return null;
            doc.Items = doc.Items.OrderBy(i => i.LineNum).ToList();

            var detail = new SalesDocDetail { Doc = doc };
            if (doc.FromDocId.HasValue)
                detail.FromDocNo = await _context.SalesDocs.Where(d => d.DocId == doc.FromDocId).Select(d => d.DocNo).FirstOrDefaultAsync();
            var invoice = await _context.SalesDocs.AsNoTracking()
                .Where(i => i.FromDocId == doc.DocId && i.Status != SalesDocStatus.Cancelled)
                .Select(i => new { i.DocId, i.DocNo }).FirstOrDefaultAsync();
            detail.InvoiceDocId = invoice?.DocId;
            detail.InvoiceDocNo = invoice?.DocNo;
            return detail;
        }

        public async Task<SalesDoc> CreateAsync(SalesDocRequest request)
        {
            if (request.DocType != SalesDocType.Quotation && request.DocType != SalesDocType.Invoice)
                throw new SalesDocException("Document type must be 1 (quotation) or 2 (invoice).");

            var doc = new SalesDoc { DocType = request.DocType, LocationId = _locationId, Status = SalesDocStatus.Open };
            await FillAsync(doc, request);

            await using var tx = await _context.Database.BeginTransactionAsync();
            doc.DocNo = await _context.NextSalesDocNoAsync(doc.DocType);
            doc.CDate = doc.UDate = DateTime.Now;
            _context.SalesDocs.Add(doc);
            await _context.SaveChangesAsync();
            await tx.CommitAsync();
            return doc;
        }

        // Quotations and invoices, while open. The number, type and quotation link never change.
        public async Task<SalesDoc> UpdateAsync(int docId, SalesDocRequest request)
        {
            var doc = await LoadAsync(docId);
            if (doc.Status == SalesDocStatus.Cancelled)
                throw new SalesDocException($"{doc.DocNo} is cancelled and can't be changed.");
            if (doc.Status == SalesDocStatus.Invoiced)
                throw new SalesDocException($"{doc.DocNo} is already invoiced — change the invoice instead.");

            _context.SalesDocItems.RemoveRange(doc.Items);
            doc.Items = new List<SalesDocItem>();
            await FillAsync(doc, request);
            doc.UDate = DateTime.Now;
            await _context.SaveChangesAsync();
            return doc;
        }

        public async Task<SalesDoc> CancelAsync(int docId, SalesDocCancelRequest request)
        {
            var doc = await LoadAsync(docId);
            if (doc.Status == SalesDocStatus.Cancelled)
                throw new SalesDocException($"{doc.DocNo} is already cancelled.");
            if (doc.Status == SalesDocStatus.Invoiced)
                throw new SalesDocException($"{doc.DocNo} is invoiced. Cancel the invoice first.");
            var reason = (request.Reason ?? "").Trim();
            if (reason.Length == 0) throw new SalesDocException("Give a reason for cancelling.");
            if (reason.Length > 200) throw new SalesDocException("Reason: max 200 characters.");

            await using var tx = await _context.Database.BeginTransactionAsync();
            doc.Status = SalesDocStatus.Cancelled;
            doc.CancelReason = reason;
            doc.UserId = request.UserId;
            doc.UDate = DateTime.Now;

            // the quotation this invoice came from can be invoiced again
            if (doc.FromDocId.HasValue)
            {
                var quotation = await _context.SalesDocs.FirstOrDefaultAsync(d => d.DocId == doc.FromDocId);
                if (quotation is { Status: SalesDocStatus.Invoiced })
                {
                    quotation.Status = SalesDocStatus.Open;
                    quotation.UDate = DateTime.Now;
                }
            }
            await _context.SaveChangesAsync();
            await tx.CommitAsync();
            return doc;
        }

        public async Task<SalesDoc> ToInvoiceAsync(int quotationId, SalesDocToInvoiceRequest request)
        {
            var q = await LoadAsync(quotationId);
            if (q.DocType != SalesDocType.Quotation) throw new SalesDocException($"{q.DocNo} is not a quotation.");
            if (q.Status == SalesDocStatus.Invoiced) throw new SalesDocException($"{q.DocNo} is already invoiced.");
            if (q.Status == SalesDocStatus.Cancelled) throw new SalesDocException($"{q.DocNo} is cancelled.");

            var now = DateTime.Now;
            var invoice = new SalesDoc
            {
                DocType = SalesDocType.Invoice,
                DocDate = PlainDate(request.DocDate ?? DateTime.Today),
                CustomerId = q.CustomerId, CustName = q.CustName, CustAddress = q.CustAddress, CustPhone = q.CustPhone,
                Reference = q.Reference, Notes = q.Notes,
                GrossAmount = q.GrossAmount, Discount = q.Discount, NetAmount = q.NetAmount,
                Status = SalesDocStatus.Open, FromDocId = q.DocId, LocationId = q.LocationId, UserId = request.UserId,
                CDate = now, UDate = now,
                Items = q.Items.OrderBy(i => i.LineNum).Select(i => new SalesDocItem
                {
                    LineNum = i.LineNum, ItemId = i.ItemId, Descrip = i.Descrip, Qty = i.Qty,
                    UnitPrice = i.UnitPrice, Discount = i.Discount, Amount = i.Amount
                }).ToList()
            };

            await using var tx = await _context.Database.BeginTransactionAsync();
            invoice.DocNo = await _context.NextSalesDocNoAsync(SalesDocType.Invoice);
            _context.SalesDocs.Add(invoice);
            q.Status = SalesDocStatus.Invoiced;
            q.UDate = now;
            await _context.SaveChangesAsync();
            await tx.CommitAsync();
            return invoice;
        }

        // ─── Settings (company details on the PDF) ───

        public async Task<SalesDocSetting> GetSettingAsync()
        {
            return await _context.SalesDocSettings.AsNoTracking().FirstOrDefaultAsync(s => s.Id == 1)
                   ?? throw new InvalidOperationException("Run DBScript/06_BackOffice_SalesDoc.sql (no z_tb_SalesDocSetting row).");
        }

        public async Task<SalesDocSetting> UpdateSettingAsync(SalesDocSetting r)
        {
            var s = await _context.SalesDocSettings.FirstAsync(x => x.Id == 1);
            var name = (r.CompanyName ?? "").Trim();
            if (name.Length == 0) throw new SalesDocException("Company name is required.");
            if (name.Length > 100) throw new SalesDocException("Company name: max 100 characters.");
            if (r.QuotationValidDays is < 1 or > 365) throw new SalesDocException("Quotation valid days must be 1 to 365.");
            CheckLength(r.CompanyAddress, 200, "Company address");
            CheckLength(r.CompanyPhone, 50, "Company phone");
            CheckLength(r.CompanyEmail, 100, "Company email");
            CheckLength(r.QuotationTerms, 1000, "Quotation terms");
            CheckLength(r.InvoiceTerms, 1000, "Invoice terms");

            s.CompanyName = name;
            s.CompanyAddress = Blank(r.CompanyAddress);
            s.CompanyPhone = Blank(r.CompanyPhone);
            s.CompanyEmail = Blank(r.CompanyEmail);
            s.QuotationValidDays = r.QuotationValidDays;
            s.QuotationTerms = Blank(r.QuotationTerms);
            s.InvoiceTerms = Blank(r.InvoiceTerms);
            s.UserId = r.UserId;
            s.UDate = DateTime.Now;
            await _context.SaveChangesAsync();
            return s;
        }

        public async Task<SalesDocSetting> SetLogoAsync(string? logoFile, int? userId)
        {
            var s = await _context.SalesDocSettings.FirstAsync(x => x.Id == 1);
            s.LogoFile = logoFile;
            s.UserId = userId;
            s.UDate = DateTime.Now;
            await _context.SaveChangesAsync();
            return s;
        }

        // ─── Rules ───

        private async Task<SalesDoc> LoadAsync(int docId)
        {
            return await _context.SalesDocs.Include(d => d.Items)
                       .FirstOrDefaultAsync(d => d.DocId == docId && d.LocationId == _locationId)
                   ?? throw new KeyNotFoundException();
        }

        // Customer, dates, lines and totals from the request (shared by create and quotation edit)
        private async Task FillAsync(SalesDoc doc, SalesDocRequest r)
        {
            if (r.CustomerId.HasValue)
            {
                var c = await _context.Customers.AsNoTracking()
                            .FirstOrDefaultAsync(x => x.CustomerId == r.CustomerId && x.Status == 1)
                        ?? throw new SalesDocException("Customer not found.");
                doc.CustomerId = c.CustomerId;
                doc.CustName = c.Name;
                doc.CustAddress = c.Address;
                doc.CustPhone = c.Phone;
            }
            else
            {
                // one-off customer, typed on the document
                var name = (r.CustName ?? "").Trim();
                if (name.Length == 0) throw new SalesDocException("Choose a customer or type the customer name.");
                CheckLength(name, 100, "Customer name");
                CheckLength(r.CustAddress, 200, "Customer address");
                CheckLength(r.CustPhone, 20, "Customer phone");
                doc.CustomerId = null;
                doc.CustName = name;
                doc.CustAddress = Blank(r.CustAddress);
                doc.CustPhone = Blank(r.CustPhone);
            }

            CheckLength(r.Reference, 50, "Reference");
            CheckLength(r.Notes, 500, "Notes");
            doc.Reference = Blank(r.Reference);
            doc.Notes = Blank(r.Notes);
            doc.UserId = r.UserId;

            doc.DocDate = PlainDate(r.DocDate ?? DateTime.Today);
            if (doc.DocType == SalesDocType.Quotation)
            {
                if (r.ValidUntil.HasValue)
                    doc.ValidUntil = PlainDate(r.ValidUntil.Value);
                else
                    doc.ValidUntil = doc.DocDate.AddDays((await GetSettingAsync()).QuotationValidDays);
                if (doc.ValidUntil < doc.DocDate)
                    throw new SalesDocException("Valid until must be on or after the quotation date.");
            }
            else
            {
                doc.ValidUntil = null;
            }

            if (r.Items == null || r.Items.Count == 0) throw new SalesDocException("Add at least one line.");
            if (r.Items.Count > MaxLines) throw new SalesDocException($"At most {MaxLines} lines.");

            // one query per item: easyway is at compatibility level 100, where EF's list.Contains (OPENJSON) fails
            var items = new Dictionary<int, string?>();
            foreach (var id in r.Items.Where(i => i.ItemId > 0).Select(i => i.ItemId).Distinct())
            {
                var found = await _context.Itemzs.AsNoTracking().Where(i => i.ItemId == id)
                    .Select(i => new { i.Descrip }).FirstOrDefaultAsync();
                if (found != null) items[id] = found.Descrip;
            }

            var lines = new List<SalesDocItem>();
            var lineNum = 0;
            foreach (var l in r.Items)
            {
                lineNum++;
                var where = $"Line {lineNum}";
                if (l.ItemId < 0) throw new SalesDocException($"{where}: bad item.");
                if (l.ItemId > 0 && !items.ContainsKey(l.ItemId)) throw new SalesDocException($"{where}: item not found.");
                var descrip = (l.Descrip ?? "").Trim();
                if (descrip.Length == 0 && l.ItemId > 0) descrip = (items[l.ItemId] ?? "").Trim();
                if (descrip.Length == 0) throw new SalesDocException($"{where}: description is required.");
                if (descrip.Length > 200) throw new SalesDocException($"{where}: description max 200 characters.");
                if (l.Qty <= 0) throw new SalesDocException($"{where}: quantity must be more than 0.");
                if (decimal.Round(l.Qty, 3) != l.Qty) throw new SalesDocException($"{where}: quantity has at most 3 decimals.");
                if (l.UnitPrice < 0) throw new SalesDocException($"{where}: price can't be negative.");
                if (decimal.Round(l.UnitPrice, 2) != l.UnitPrice) throw new SalesDocException($"{where}: price has at most 2 decimals.");
                var gross = Money(l.Qty * l.UnitPrice);
                if (l.Discount < 0 || l.Discount > gross)
                    throw new SalesDocException($"{where}: discount must be between 0 and {gross:0.00}.");

                lines.Add(new SalesDocItem
                {
                    LineNum = lineNum, ItemId = l.ItemId, Descrip = descrip, Qty = l.Qty, UnitPrice = l.UnitPrice,
                    Discount = Money(l.Discount), Amount = gross - Money(l.Discount)
                });
            }

            doc.Items = lines;
            doc.GrossAmount = lines.Sum(l => l.Amount);
            var discount = Money(r.Discount);
            if (discount < 0 || discount > doc.GrossAmount)
                throw new SalesDocException($"Discount must be between 0 and {doc.GrossAmount:0.00}.");
            doc.Discount = discount;
            doc.NetAmount = doc.GrossAmount - discount;
        }

        private static decimal Money(decimal v) => decimal.Round(v, 2, MidpointRounding.AwayFromZero);

        // a plain date (no time zone), the same as what comes back from the date column
        private static DateTime PlainDate(DateTime d) => DateTime.SpecifyKind(d.Date, DateTimeKind.Unspecified);

        private static void CheckLength(string? s, int max, string what)
        {
            if (s != null && s.Trim().Length > max) throw new SalesDocException($"{what}: max {max} characters.");
        }

        private static string? Blank(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
    }
}
