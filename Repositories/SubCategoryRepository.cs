using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    public class SubCategoryRepository : ISubCategoryRepository
    {
        private readonly AppDbContext _context;

        public SubCategoryRepository(AppDbContext context)
        {
            _context = context;
        }

        // Get all
        public async Task<List<SubCategory>> GetAllAsync()
        {
            return await _context.SubCategories.ToListAsync();
        }

        // Get by Id
        public async Task<SubCategory?> GetByIdAsync(int id)
        {
            return await _context.SubCategories.FindAsync(id);
        }

        // Search by code or name
        public async Task<List<SubCategory>> GetByCodeAsync(string code)
        {
            return await _context.SubCategories
                .Where(s =>
                    s.SubCatCode.Contains(code) ||
                    s.SubCatName.Contains(code))
                .ToListAsync();
        }

        // Get by Category Id
        public async Task<List<SubCategory>> GetByCatIdAsync(int catId)
        {
            return await _context.SubCategories
                .Where(s => s.CatId == catId)
                .ToListAsync();
        }

        // Add
        public async Task AddAsync(SubCategory subCategory)
        {
            await _context.SubCategories.AddAsync(subCategory);
            await _context.SaveChangesAsync();
        }

        // Update
        public async Task UpdateAsync(SubCategory subCategory)
        {
            _context.SubCategories.Update(subCategory);
            await _context.SaveChangesAsync();
        }

        // Delete
        public async Task DeleteAsync(int id)
        {
            var entity = await _context.SubCategories.FindAsync(id);

            if (entity == null)
                return;

            _context.SubCategories.Remove(entity);
            await _context.SaveChangesAsync();
        }
    }
}