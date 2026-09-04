using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Written cheques (z_tb_WrittenCheque) — consolidated from the former ChequeCreateContext.
    public partial class AppDbContext
    {
        public DbSet<ChequeCreate> Cheques { get; set; }

        partial void ConfigureChequeCreate(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<ChequeCreate>().ToTable("z_tb_WrittenCheque");
        }
    }
}
