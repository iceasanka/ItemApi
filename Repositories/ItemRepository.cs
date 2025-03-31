using ItemApi.Data;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using System.Threading.Tasks;
namespace ItemApi.Repositories
{

    public class ItemRepository : IItemRepository
    {
        private readonly ItemContext _context;

        public ItemRepository(ItemContext context)
        {
            _context = context;
        }

        public async Task<ItemWithDetails> GetItemWithDetailsByItemCodeAsync(string itemcode)
        {
            return await _context.GetItemWithDetailsByItemCodeAsync(itemcode);
        }

        public async Task<ItemWithDetails> GetItemWithDetailsByBarcodeAsync(string barcode)
        {
            return await _context.GetItemWithDetailsByBarcodeAsync(barcode);
        } 
        public async Task<ItemWithDetails> GetItemWithDetailsByRefCodeAsync(string barcode)
        {
            return await _context.GetItemWithDetailsByRefCodeAsync(barcode);
        }

        public async Task<List<PriceLink>> GetPriceLink(string itemCode)
        {
            return await _context.GetPriceLink(itemCode);
        }

        public async Task<int> UpdatePriceLink(PriceLinkUpdateDTO dto)
        {
            return await _context.UpdatePriceLink(dto);
        }
    }
}
