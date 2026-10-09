using System.Globalization;
using ItemApi.Models;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace ItemApi.Service
{
    // A4 PDF of a quotation or invoice: company header (logo, name, address), customer, lines, totals, notes, terms,
    // signatures, page numbers. Cancelled documents are stamped CANCELLED. Docs/StockSystem.md §6.11.
    // QuestPDF Community licence: free for businesses with under USD 1M annual gross revenue.
    public class SalesDocPdfService
    {
        private const string Accent = "#1F3A5F";
        private const string Muted = "#6B7280";
        private const string Line = "#D1D5DB";

        private readonly string _uploadsPath;

        static SalesDocPdfService()
        {
            QuestPDF.Settings.License = LicenseType.Community;
        }

        public SalesDocPdfService(IWebHostEnvironment env)
        {
            _uploadsPath = Path.Combine(env.ContentRootPath, "Uploads");
        }

        public string UploadsPath => _uploadsPath;

        public byte[] Build(SalesDocDetail detail, SalesDocSetting company)
        {
            var doc = detail.Doc;
            var isQuotation = doc.DocType == SalesDocType.Quotation;
            var title = isQuotation ? "QUOTATION" : "INVOICE";
            var terms = isQuotation ? company.QuotationTerms : company.InvoiceTerms;
            var hasLineDiscount = doc.Items.Any(i => i.Discount > 0);
            var logo = LogoBytes(company.LogoFile);

            return Document.Create(container =>
            {
                container.Page(page =>
                {
                    page.Size(PageSizes.A4);
                    page.Margin(36);
                    page.DefaultTextStyle(t => t.FontSize(10).FontColor("#111827"));

                    page.Header().Column(col =>
                    {
                        col.Item().Row(row =>
                        {
                            if (logo != null)
                                row.ConstantItem(80).Height(60).AlignLeft().Image(logo).FitArea();
                            row.RelativeItem().PaddingLeft(logo != null ? 10 : 0).Column(c =>
                            {
                                c.Item().Text(company.CompanyName).FontSize(16).Bold().FontColor(Accent);
                                if (company.CompanyAddress != null) c.Item().Text(company.CompanyAddress).FontColor(Muted);
                                var contact = string.Join("  ·  ", new[] { company.CompanyPhone, company.CompanyEmail }.Where(s => !string.IsNullOrEmpty(s)));
                                if (contact.Length > 0) c.Item().Text(contact).FontColor(Muted);
                            });
                            row.ConstantItem(190).AlignRight().Column(c =>
                            {
                                c.Item().AlignRight().Text(title).FontSize(20).Bold().FontColor(Accent);
                                c.Item().AlignRight().Text(t => { t.Span("No: ").FontColor(Muted); t.Span(doc.DocNo).Bold(); });
                                c.Item().AlignRight().Text(t => { t.Span("Date: ").FontColor(Muted); t.Span(Date(doc.DocDate)); });
                                if (isQuotation && doc.ValidUntil.HasValue)
                                    c.Item().AlignRight().Text(t => { t.Span("Valid until: ").FontColor(Muted); t.Span(Date(doc.ValidUntil.Value)); });
                                if (doc.Reference != null)
                                    c.Item().AlignRight().Text(t => { t.Span("Your ref: ").FontColor(Muted); t.Span(doc.Reference); });
                                if (!isQuotation && detail.FromDocNo != null)
                                    c.Item().AlignRight().Text(t => { t.Span("Quotation: ").FontColor(Muted); t.Span(detail.FromDocNo); });
                            });
                        });
                        col.Item().PaddingTop(8).LineHorizontal(1.5f).LineColor(Accent);
                    });

                    page.Content().PaddingTop(12).Column(col =>
                    {
                        if (doc.Status == SalesDocStatus.Cancelled)
                        {
                            col.Item().PaddingBottom(8).Border(1.5f).BorderColor(Colors.Red.Medium).Padding(6).AlignCenter()
                                .Text($"CANCELLED — {doc.CancelReason}").FontSize(12).Bold().FontColor(Colors.Red.Medium);
                        }

                        col.Item().Text(isQuotation ? "Quotation for" : "Bill to").FontSize(9).FontColor(Muted);
                        col.Item().Text(doc.CustName).FontSize(12).Bold();
                        if (doc.CustAddress != null) col.Item().Text(doc.CustAddress);
                        if (doc.CustPhone != null) col.Item().Text(doc.CustPhone);

                        col.Item().PaddingTop(14).Table(table =>
                        {
                            table.ColumnsDefinition(c =>
                            {
                                c.ConstantColumn(28);
                                c.RelativeColumn();
                                c.ConstantColumn(60);
                                c.ConstantColumn(75);
                                if (hasLineDiscount) c.ConstantColumn(65);
                                c.ConstantColumn(85);
                            });

                            table.Header(h =>
                            {
                                HeaderCell(h.Cell(), "#");
                                HeaderCell(h.Cell(), "Description");
                                HeaderCell(h.Cell(), "Qty", right: true);
                                HeaderCell(h.Cell(), "Unit price", right: true);
                                if (hasLineDiscount) HeaderCell(h.Cell(), "Discount", right: true);
                                HeaderCell(h.Cell(), "Amount", right: true);
                            });

                            foreach (var l in doc.Items)
                            {
                                BodyCell(table.Cell()).Text(l.LineNum.ToString()).FontColor(Muted);
                                BodyCell(table.Cell()).Text(l.Descrip);
                                BodyCell(table.Cell()).AlignRight().Text(Qty(l.Qty));
                                BodyCell(table.Cell()).AlignRight().Text(Money(l.UnitPrice));
                                if (hasLineDiscount) BodyCell(table.Cell()).AlignRight().Text(l.Discount > 0 ? Money(l.Discount) : "");
                                BodyCell(table.Cell()).AlignRight().Text(Money(l.Amount));
                            }
                        });

                        col.Item().PaddingTop(8).AlignRight().Width(230).Column(t =>
                        {
                            if (doc.Discount > 0)
                            {
                                TotalRow(t, "Sub total", Money(doc.GrossAmount));
                                TotalRow(t, "Discount", "-" + Money(doc.Discount));
                            }
                            t.Item().PaddingTop(4).LineHorizontal(1).LineColor(Accent);
                            t.Item().PaddingTop(4).Row(r =>
                            {
                                r.RelativeItem().Text("Total (Rs)").FontSize(12).Bold();
                                r.RelativeItem().AlignRight().Text(Money(doc.NetAmount)).FontSize(12).Bold();
                            });
                        });

                        if (doc.Notes != null)
                        {
                            col.Item().PaddingTop(16).Text("Notes").FontSize(9).Bold().FontColor(Muted);
                            col.Item().Text(doc.Notes);
                        }
                        if (terms != null)
                        {
                            col.Item().PaddingTop(12).Text("Terms").FontSize(9).Bold().FontColor(Muted);
                            col.Item().Text(terms).FontSize(9);
                        }

                        col.Item().PaddingTop(50).Row(r =>
                        {
                            r.RelativeItem().Column(c => Signature(c, isQuotation ? "Prepared by" : "Issued by"));
                            r.ConstantItem(60);
                            r.RelativeItem().Column(c => Signature(c, isQuotation ? "Authorised signature" : "Received by (customer)"));
                        });
                    });

                    page.Footer().Row(r =>
                    {
                        r.RelativeItem().Text($"{title} {doc.DocNo}").FontSize(8).FontColor(Muted);
                        r.RelativeItem().AlignRight().Text(t =>
                        {
                            t.DefaultTextStyle(s => s.FontSize(8).FontColor(Muted));
                            t.Span("Page ");
                            t.CurrentPageNumber();
                            t.Span(" of ");
                            t.TotalPages();
                        });
                    });
                });
            }).GeneratePdf();
        }

        private byte[]? LogoBytes(string? logoFile)
        {
            if (string.IsNullOrEmpty(logoFile)) return null;
            var path = Path.Combine(_uploadsPath, logoFile);
            return File.Exists(path) ? File.ReadAllBytes(path) : null;
        }

        private static void HeaderCell(IContainer cell, string text, bool right = false)
        {
            var c = cell.Background(Accent).PaddingVertical(5).PaddingHorizontal(4);
            (right ? c.AlignRight() : c).Text(text).FontSize(9).Bold().FontColor(Colors.White);
        }

        private static IContainer BodyCell(IContainer cell) =>
            cell.BorderBottom(0.5f).BorderColor(Line).PaddingVertical(4).PaddingHorizontal(4);

        private static void TotalRow(ColumnDescriptor col, string label, string value)
        {
            col.Item().PaddingTop(2).Row(r =>
            {
                r.RelativeItem().Text(label).FontColor(Muted);
                r.RelativeItem().AlignRight().Text(value);
            });
        }

        private static void Signature(ColumnDescriptor col, string label)
        {
            col.Item().LineHorizontal(0.75f).LineColor(Muted);
            col.Item().PaddingTop(2).Text(label).FontSize(9).FontColor(Muted);
        }

        private static string Money(decimal v) => v.ToString("#,##0.00", CultureInfo.InvariantCulture);

        // 2 → "2", 1.5 → "1.5", 0.125 → "0.125"
        private static string Qty(decimal v) => v.ToString("#,##0.###", CultureInfo.InvariantCulture);

        private static string Date(DateTime d) => d.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture);
    }
}
