using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ISubCategoryRepository
    {
        Task<List<SubCategory>> GetAllAsync();
        Task<SubCategory?> GetByIdAsync(int id);
        Task<List<SubCategory>> GetByCodeAsync(string code);
        Task<List<SubCategory>> GetByCatIdAsync(int catId);
        Task AddAsync(SubCategory subCategory);
        Task UpdateAsync(SubCategory subCategory);
        Task DeleteAsync(int id);
    }
}
