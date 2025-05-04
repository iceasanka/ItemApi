using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
namespace ItemApi.Repositories
{
    public class GrnTempRepository: IGrnTempRepository
    {
        private readonly GrnTempContext _context;

        public GrnTempRepository(GrnTempContext context)
        {
            _context = context;
        }

        public async Task<GrnTemp> InsertGrnTempAsync(GrnTemp grnRef)
        {
            return await _context.InsertGrnTempAsync(grnRef);
        }

        public async Task<GrnTemp> UpdateGrnTempAsync(GrnTemp grnRef)
        {
            return await _context.UpdateGrnTempAsync(grnRef);
        }

        public async Task<GrnTemp> DeleteGrnTempAsync(int id)
        {
            return await _context.DeleteGrnTempAsync(id);
        }

        //get ist of grnitems by  GrnReference and status
        public async Task<IQueryable<GrnTemp>> GetGrnTempByGrnReferenceAndStatusAsync(string grnReference, int status)
        {
            return await _context.GetGrnTempByGrnReferenceAndStatusAsync(grnReference, status);
        }

        public async Task<GrnTemp> UpdateGrnTempStatusAsync(int id, int status)
        {
            return await _context.UpdateGrnTempStatusAsync(id, status);
        }

    }
}
