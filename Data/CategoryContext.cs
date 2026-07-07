using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    public class CategoryContext : DbContext
    {

        public CategoryContext(DbContextOptions<CategoryContext> options)
          : base(options)
        {
        }

        public DbSet<Category> Categories { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Category>().ToTable("z_tb_Category");
        }
    }
}
