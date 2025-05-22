using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Serilog;

namespace ItemApi.Repositories
{
    public class PurchaseRepository : IPurchaseRepository
    {
        private readonly PurchaseContext _context;

        public PurchaseRepository(PurchaseContext context)
        {
            _context = context;
        }

        public async Task<int> GetPNOByLocaCodeAsync(string locaCode)
        {
            var opb = await _context.GetPNOByLocaCodeAsync(locaCode);

            return opb;
        }

        public async Task UpdatePurchaseItemToTempPurchaseAsync(PurchaseUpdateRequest request)
        {
            await _context.UpdatePurchaseItemToTempPurchaseAsync(request);
        }

        public async Task CommitPurchaseAsync(CommitPurchaseItems request)
        {
            await _context.CommitPurchaseAsync(request);
        }
       
        

       
        

       

     

    }
}
