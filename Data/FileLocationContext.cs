using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    public class FileLocationContext : DbContext
    {
        public FileLocationContext(DbContextOptions<FileLocationContext> options)
            : base(options)
        {
        }

        public DbSet<FileLocation> FileLocations { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<FileLocation>().ToTable("z_tb_FileLocation");
        }

        // Add a new file
        public async Task AddFileAsync(FileLocation fileLocation)
        {
            FileLocations.Add(fileLocation);
            await SaveChangesAsync();
        }

        // Update an existing file
        public async Task UpdateFileAsync(FileLocation fileLocation)
        {
            FileLocations.Update(fileLocation);
            await SaveChangesAsync();
        }

        // Delete a file by Id
        public async Task DeleteFileAsync(int id)
        {
            var entity = await FileLocations.FindAsync(id);
            if (entity != null)
            {
                FileLocations.Remove(entity);
                await SaveChangesAsync();
            }
        }

        // Search files by Supp_Name
        public async Task<List<FileLocation>> SearchFileByNameAsync(string suppName)
        {
            return await FileLocations
                .Where(f => f.Supp_Name.Contains(suppName))
                .ToListAsync();
        }

        // Get all files
        public async Task<List<FileLocation>> GetAllFilesAsync()
        {
            return await FileLocations.ToListAsync();
        }
    }
}

