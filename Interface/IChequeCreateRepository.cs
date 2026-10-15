using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface IChequeCreateRepository
    {
        Task AddChequeAsync(ChequeCreate cheque);

        Task<ChequeCreate> WriteChequeAsync(Cheque cheque);

        Task AddChequeForSupplierAsync(ChequeCreate cheque, int suppId, List<SupplierAllocation>? allocations);

        Task<List<ChequeBillRow>> GetChequeBillsAsync(int chequeId);

        Task<IEnumerable<ChequeCreate>> SearchChequesByDateRangeAsync(DateTime fromDate, DateTime toDate,int? chequeNumber,string? supplierName,decimal? amount);

        Task<IEnumerable<ChequeCreate>> GetChequesByPayeeIdAsync(int payeeId);

        Task<ChequeCreate> GetByIdAsync(int id);
        Task UpdateChequeAsync(ChequeCreate cheque);
        Task DeleteChequeAsync(int id);

        Task SyncChequesAsync(IEnumerable<ChequeCreate> cheques);

        Task SyncPrintedChequeAsync(ChequeCreate cheque);
        Task<ChequeUploadResult> ProcessFile(string filePath);

        byte[] BuildUploadRowsCsv(IEnumerable<ChequeUploadRow> rows);

        Task<bool> ChequeNumberExistsAsync(int chequeNumber);





    }
}
