using ItemApi.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using System.Threading.Tasks;
namespace ItemApi.Repositories
{

    public class ReturnRepository : IReturnRepository
    {
        private readonly ReturnContext _context;

        public ReturnRepository(ReturnContext context)
        {
            _context = context;
        }

        public async Task<List<ReturnItem>> GetAllItemsAsync()
        {
            return await _context.ReturnItems.ToListAsync();
        }

        public async Task<ReturnItem> GetItemByCodeAsync(string itemCode)
        {
            return await _context.ReturnItems.FirstOrDefaultAsync(i => i.Item_Code == itemCode);
        }

        public async Task<List<ReturnItem>> GetItemsBySuppCodeAsync(string suppCode)
        {
            return await _context.ReturnItems.Where(i => i.Supp_Code == suppCode && i.Status !=3).ToListAsync(); ;
        }

        public async Task<List<ReturnItem>> SearchItemsAsync(string description, string suppCode)
        {
            return await _context.ReturnItems
                .Where(i => (description == null || i.Descrip.Contains(description)) &&
                            (suppCode == null || i.Supp_Code == suppCode))
                .ToListAsync();
        }

        public async Task AddItemAsync(ReturnItem item)
        {
            await _context.ReturnItems.AddAsync(item);
            await _context.SaveChangesAsync();
        }

        public async Task UpdateItemAsync(int id, ReturnItem updatedItem)
        {
            var item = await _context.ReturnItems.FirstOrDefaultAsync(i => i.Id == id);
            if (item != null)
            {
                item.Ref_Code = updatedItem.Ref_Code;
                item.Barcode = updatedItem.Barcode;
                item.Descrip = updatedItem.Descrip;
                item.Supp_Code = updatedItem.Supp_Code;
                item.Status = updatedItem.Status;
                item.Date = updatedItem.Date;
                item.Cost_Price = updatedItem.Cost_Price;
                item.ERet_Price = updatedItem.ERet_Price;

                _context.ReturnItems.Update(item);
                await _context.SaveChangesAsync();
            }
        }

        public async Task UpdateItemStatusAsync(int id, int status)
        {
            var item = await _context.ReturnItems.FirstOrDefaultAsync(i => i.Id == id);
            if (item != null)
            {
                item.Status = status;
                _context.ReturnItems.Update(item);
                await _context.SaveChangesAsync();
            }
        }

        public async Task DeleteItemAsync(int id)
        {
            var item = await _context.ReturnItems.FindAsync(id);
            if (item != null)
            {
                _context.ReturnItems.Remove(item);
                await _context.SaveChangesAsync();
            }
        }

        public async Task<List<IGrouping<string, ReturnItem>>> GroupBySuppCodeAsync()
        {
            return await _context.ReturnItems
                .GroupBy(i => i.Supp_Code)
                .ToListAsync();
        }


        public async Task<int> GetPRNOByLocaCodeAsync(string locaCode)
        {
            var opb = await _context.GetPRNOByLocaCodeAsync(locaCode);

            return opb;
        }


        public async Task<List<PurchaseType>> GetPurchaseTypesAsync()
        {
            var opb = await _context.GetPurchaseTypesAsync();

            return opb;
        }

        public async Task<List<ReturnMode>> GetReturnModesAsync()
        {
            var opb = await _context.GetReturnModesAsync();

            return opb;
        }

        public async Task<Supplier> GetSupplierByCodeAsync(string suppCode)
        {
            var opb = await _context.GetSupplierByCodeAsync(suppCode);

            return opb;
        }

        public async Task UpdateReturnItemToTempPurchaseAsync(ReturnUpdateRequest request)
        {
            await _context.UpdateReturnItemToTempPurchaseAsync(request);
        } 
        
        public async Task CommitReturnToPurchaseAsync(CommitReturnItems request)
        {
            await _context.CommitReturnToPurchaseAsync(request);
        }public async Task DeleteTempPurchaseAsync(DeleteTempPurchaseRequest request)
        {
            await _context.DeleteTempPurchaseAsync(request);
        }


    }
}
