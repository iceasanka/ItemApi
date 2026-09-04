using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Temp purchase (z_tb_TempPurchase) — consolidated from the former TempPurchaseContext.
    public partial class AppDbContext
    {
        public DbSet<TempPurchase> TempPurchases { get; set; }

        partial void ConfigureTempPurchase(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<TempPurchase>().ToTable("z_tb_TempPurchase");
        }
    }
}
