using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Categories (z_tb_Category) — consolidated from the former CategoryContext.
    public partial class AppDbContext
    {
        public DbSet<Category> Categories { get; set; }

        partial void ConfigureCategory(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Category>().ToTable("z_tb_Category");
        }
    }
}
