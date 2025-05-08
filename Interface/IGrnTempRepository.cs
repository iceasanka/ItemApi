using ItemApi.Models;
using ItemApi.Repositories;

namespace ItemApi.Interface
{
    public interface IGrnTempRepository
    { 
        Task<GrnTemp> InsertGrnTempAsync(GrnTemp grnRef);
        Task<GrnTemp> UpdateGrnTempAsync(GrnTemp grnRef);
        Task<GrnTemp> DeleteGrnTempAsync(int id);

        Task<IQueryable<GrnTemp>> GetGrnTempByGrnReferenceAndStatusAsync(string grnReference, int status);

        Task<GrnTemp> UpdateGrnTempStatusAsync(int id, int status);


    }
}
