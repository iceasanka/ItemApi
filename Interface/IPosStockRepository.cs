using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IPosStockRepository
    {

        Task<decimal> GetSumQtyAsync(string itemCode);
    }
}
