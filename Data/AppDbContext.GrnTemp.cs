using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Serilog;

namespace ItemApi.Data
{
    // GRN temp staging (z_tb_GrnTemp) — consolidated from the former GrnTempContext.
    // Joins against the shared ItemDetails DbSet declared in AppDbContext.Item.cs.
    public partial class AppDbContext
    {
        public DbSet<GrnTemp> _grnTemp { get; set; }

        partial void ConfigureGrnTemp(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<GrnTemp>().ToTable("z_tb_GrnTemp");
        }

        public async Task<GrnTemp> InsertGrnTempAsync(GrnTemp grnRef)
        {
            try
            {
                _grnTemp.Add(grnRef);
                await SaveChangesAsync();
                return grnRef; // return the inserted entity
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw;
            }
        }

        public async Task<GrnTemp> UpdateGrnTempAsync(GrnTemp grnRef)
        {
            try
            {
                _grnTemp.Update(grnRef);
                await SaveChangesAsync();
                return grnRef; // return the updated entity
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw;
            }
        }

        public async Task<GrnTemp> DeleteGrnTempAsync(int id)
        {
            try
            {
                var grnRef = await _grnTemp.FindAsync(id);
                if (grnRef != null)
                {
                    _grnTemp.Remove(grnRef);
                    await SaveChangesAsync();
                    return grnRef; // return the deleted entity
                }
                return null; // if not found, return nul
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw;
            }
        }

        // get list of grn items by GrnReference and status
        public async Task<List<GrnTemp>> GetGrnTempByGrnReferenceAndStatusAsync(string grnReference, int status)
        {
            try
            {
                var query = from grn in _grnTemp
                            join det in ItemDetails
                                on grn.ItemCode equals det.Item_Code
                            where grn.GrnReference == grnReference
                                  && grn.Status == status
                                  && det.Loca_Code == "01"
                            select new GrnTemp
                            {
                                Id = grn.Id,
                                BarCode = grn.BarCode,
                                ItemCode = grn.ItemCode,
                                ItemRefCode = grn.ItemRefCode,
                                GrnReference = grn.GrnReference,
                                Descrip = grn.Descrip,
                                Qty = grn.Qty,
                                Date = grn.Date,
                                Status = grn.Status,
                                CostPrice = grn.CostPrice,
                                ERetPrice = grn.ERetPrice,

                                // From tb_ItemDet
                                itemCostPrice = det.Cost_Price,
                                itemERetPrice = det.ERet_Price
                            };

                return await query.ToListAsync();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw;
            }
        }

        // update status of grn items by Id
        public async Task<GrnTemp> UpdateGrnTempStatusAsync(int id, int status)
        {
            try
            {
                var grnRef = await _grnTemp.FindAsync(id);
                if (grnRef != null)
                {
                    grnRef.Status = status;
                    _grnTemp.Update(grnRef);
                    await SaveChangesAsync();
                    return grnRef; // return the updated entity
                }
                return null; // if not found, return null
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw;
            }
        }

        public async Task<GrnTemp> GetGrnTempByIdAsync(int id)
        {
            try
            {
                var grnRef = await _grnTemp.FindAsync(id);
                return grnRef; // return the found entity or null if not found
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw;
            }
        }
    }
}
