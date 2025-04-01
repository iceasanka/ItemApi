using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IPosCountedStockRepository
    {
        Task<double> GetSumQtyAsync(string itemCode);

       Task AddPosCountedStock(PosCountedStock posCountedStock);

        //implement delete method
        Task DeletePosCountedStock(string itemCode);

        //implement delete all the table data in the database table
        Task DeleteAllPosCountedStock();
    }
}
