using ItemApi.Data;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace ItemApi.Repositories
{
    public class FileLocationRepository : IFileLocationRepository
    {
        private readonly AppDbContext _context;

        public FileLocationRepository(AppDbContext context)
        {
            _context = context;
        }

        public async Task<List<FileLocation>> GetAllAsync()
        {
            return await _context.GetAllFilesAsync();
        }

        public async Task<FileLocation?> GetByIdAsync(int id)
        {
            return await _context.FileLocations.FindAsync(id);
        }

        public async Task AddAsync(FileLocation fileLocation)
        {
            await _context.AddFileAsync(fileLocation);
        }

        public async Task UpdateAsync(FileLocation fileLocation)
        {
            await _context.UpdateFileAsync(fileLocation);
        }

        public async Task DeleteAsync(int id)
        {
            await _context.DeleteFileAsync(id);
        }

        public async Task<List<FileLocation>> SearchFileByNameAsync(string suppName)
        {
            return await _context.SearchFileByNameAsync(suppName);
        }
    }
}
