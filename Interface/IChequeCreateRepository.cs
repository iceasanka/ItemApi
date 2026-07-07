using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IChequeCreateRepository
    {
        Task AddChequeAsync(ChequeCreate cheque);

        Task<IEnumerable<ChequeCreate>> SearchChequesByDateRangeAsync(DateTime fromDate, DateTime toDate,int? chequeNumber,string? supplierName,decimal? amount);

        Task<IEnumerable<ChequeCreate>> GetChequesByPayeeIdAsync(int payeeId);

        Task<ChequeCreate> GetByIdAsync(int id);
        Task UpdateChequeAsync(ChequeCreate cheque);
        Task DeleteChequeAsync(int id);

        Task SyncChequesAsync(IEnumerable<ChequeCreate> cheques);

        Task SyncPrintedChequeAsync(ChequeCreate cheque);
        Task ProcessFile(string filePath);

        Task<bool> ChequeNumberExistsAsync(int chequeNumber);





    }
}
