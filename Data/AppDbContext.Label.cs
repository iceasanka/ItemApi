using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Barcode label layouts (z_tb_LabelLayout — DBScript/16_BackOffice_LabelLayout.sql).
    public partial class AppDbContext
    {
        public DbSet<LabelLayout> LabelLayouts { get; set; }

        partial void ConfigureLabel(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<LabelLayout>().ToTable("z_tb_LabelLayout");
        }
    }
}
