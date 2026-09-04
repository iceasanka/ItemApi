using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Payees (z_tb_Payee) — consolidated from the former PayeeContext.
    public partial class AppDbContext
    {
        public DbSet<Models.Payee> Payees { get; set; }

        partial void ConfigurePayee(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Models.Payee>().ToTable("z_tb_Payee");
        }
    }
}
