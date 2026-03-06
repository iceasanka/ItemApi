using ItemApi.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace ItemApi.Repositories
{
    public interface ISupplierzRepository
    {
        Task<List<SupplierEntity>> GetAllAsync();
        Task<SupplierEntity?> GetByIdAsync(int id);
        Task AddAsync(SupplierEntity supplier);
        Task UpdateAsync(SupplierEntity supplier);
        Task DeleteAsync(int id);
        Task<List<SupplierEntity>> SearchSupplierByNameAsync(string suppName);
    }
}
