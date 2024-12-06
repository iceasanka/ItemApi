using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ISupplierRepository
    {
        Task<IEnumerable<Supplier>> GetAllSuppliersAsync();
        Task<IEnumerable<Supplier>> SearchSuppliersAsync(string query);
    }
}
