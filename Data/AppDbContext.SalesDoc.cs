using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Customers, quotations and invoices (DBScript/06_BackOffice_SalesDoc.sql).
    public partial class AppDbContext
    {
        public DbSet<Customer> Customers { get; set; }
        public DbSet<SalesDoc> SalesDocs { get; set; }
        public DbSet<SalesDocItem> SalesDocItems { get; set; }
        public DbSet<SalesDocCounter> SalesDocCounters { get; set; }
        public DbSet<SalesDocSetting> SalesDocSettings { get; set; }

        partial void ConfigureSalesDoc(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Customer>().ToTable("z_tb_Customer");
            modelBuilder.Entity<SalesDoc>().ToTable("z_tb_SalesDoc")
                .HasMany(d => d.Items).WithOne().HasForeignKey(i => i.DocId);
            modelBuilder.Entity<SalesDoc>().Property(d => d.DocDate).HasColumnType("date");
            modelBuilder.Entity<SalesDoc>().Property(d => d.ValidUntil).HasColumnType("date");
            modelBuilder.Entity<SalesDocItem>().ToTable("z_tb_SalesDocItem");
            modelBuilder.Entity<SalesDocCounter>().ToTable("z_tb_SalesDocCounter");
            modelBuilder.Entity<SalesDocSetting>().ToTable("z_tb_SalesDocSetting");
        }

        // Next number for a document type, e.g. QT000001. Call inside the save transaction: the row stays locked
        // until commit, so two saves at once never get the same number (a rolled-back save leaves a gap).
        public async Task<string> NextSalesDocNoAsync(int docType)
        {
            var rows = await Database.SqlQueryRaw<SalesDocCounter>(@"
                UPDATE dbo.z_tb_SalesDocCounter SET LastNo = LastNo + 1
                OUTPUT inserted.DocType, inserted.Prefix, inserted.LastNo
                WHERE DocType = @DocType",
                new SqlParameter("@DocType", docType)).ToListAsync();
            var c = rows.FirstOrDefault() ?? throw new InvalidOperationException(
                $"No number counter for document type {docType}. Run DBScript/06_BackOffice_SalesDoc.sql.");
            return c.Prefix + c.LastNo.ToString("000000");
        }
    }
}
