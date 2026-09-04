using ItemApi.Data;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Serilog;
namespace ItemApi.Repositories
{

    public class ReturnRepository : IReturnRepository
    {
        private readonly AppDbContext _context;

        public ReturnRepository(AppDbContext context)
        {
            _context = context;
        }

        public async Task<List<ReturnItem>> GetAllItemsAsync()
        {
            return await _context.ReturnItems.ToListAsync();
        }

        public async Task<List<ReturnItem>> GetAllItemsWithSuppliersAsync()
        {
            try
            {
                var query = from returnItem in _context.ReturnItems
                            join supplier in _context.Suppliers
                                on returnItem.Supp_Code equals supplier.Supp_Code into supplierGroup
                            from supplier in supplierGroup.DefaultIfEmpty()
                            where returnItem.Status != 3// Left join for missing suppliers
                            select new ReturnItem
                            {
                                Id = returnItem.Id,
                                Item_Code = returnItem.Item_Code,
                                Ref_Code = returnItem.Ref_Code,
                                Barcode = returnItem.Barcode,
                                Descrip = returnItem.Descrip,
                                Supp_Code = returnItem.Supp_Code,
                                Supp_Name = supplier != null ? supplier.Supp_Name : "Unknown Supplier",
                                Status = returnItem.Status,
                                Date = returnItem.Date,
                                Cost_Price = returnItem.Cost_Price,
                                ERet_Price = returnItem.ERet_Price,
                                Qty = returnItem.Qty
                            };

                return await query.ToListAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw ex;
            }
        }

        public async Task<ReturnItem> GetItemByCodeAsync(string itemCode)
        {
            return await _context.ReturnItems.FirstOrDefaultAsync(i => i.Item_Code == itemCode);
        }

        public async Task<List<ReturnItem>> GetItemsBySuppCodeAsync(string suppCode)
        {
            return await _context.ReturnItems.Where(i => i.Supp_Code == suppCode && i.Status != 3).ToListAsync(); ;
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
            try
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
            catch (Exception ex)
            {
                Log.Error($"Error : {ex.Message}");
                throw ex;
            }
        }

        public async Task UpdateItemStatusAsync(int id, int status)
        {
            try
            {
                var item = await _context.ReturnItems.FirstOrDefaultAsync(i => i.Id == id);
                if (item != null)
                {
                    item.Status = status;
                    _context.ReturnItems.Update(item);
                    await _context.SaveChangesAsync();
                }
            }
            catch (Exception ex)
            {
                Log.Error($"Error details: {ex.Message}");
                throw ex;
            }
        }

        public async Task DeleteItemAsync(int id)
        {
            try
            {
                var item = await _context.ReturnItems.FindAsync(id);
                if (item != null)
                {
                    _context.ReturnItems.Remove(item);
                    await _context.SaveChangesAsync();
                }
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw ex;
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
        }
        public async Task DeleteTempPurchaseAsync(DeleteTempPurchaseRequest request)
        {
            await _context.DeleteTempPurchaseAsync(request);
        }


    }
}
