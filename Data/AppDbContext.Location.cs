using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Locations (z_tb_Location) — used for multi-location support (see Category.LocationId).
    public partial class AppDbContext
    {
        public DbSet<Location> Locations { get; set; }

        partial void ConfigureLocation(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Location>().ToTable("z_tb_Location");
        }
    }
}
