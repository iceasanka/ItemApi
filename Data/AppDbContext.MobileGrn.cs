using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Mobile GRN drafts (U017). All reads and writes go through the z_sp_MobileGrn procs; nothing here moves stock —
    // the back office commits the GRN on the GRN Entry page.
    public partial class AppDbContext
    {
        public async Task<List<MobileGrnLine>> GetMobileGrnAsync(int suppId, int locationId)
        {
            return await Database.SqlQueryRaw<MobileGrnLine>(
                "EXEC dbo.z_sp_MobileGrnGet @SuppId = @SuppId, @LocationId = @LocationId",
                new SqlParameter("@SuppId", suppId),
                new SqlParameter("@LocationId", locationId)).ToListAsync();
        }

        public async Task<MobileGrnLineRef> AddMobileGrnLineAsync(MobileGrnAddRequest r, int locationId)
        {
            var rows = await Database.SqlQueryRaw<MobileGrnLineRef>(
                "EXEC dbo.z_sp_MobileGrnAddLine @SuppId = @SuppId, @ItemId = @ItemId, @Qty = @Qty, @CostPrice = @CostPrice, " +
                "@SellPrice = @SellPrice, @LocationId = @LocationId",
                new SqlParameter("@SuppId", r.SuppId),
                new SqlParameter("@ItemId", r.ItemId),
                Dec("@Qty", r.Qty, 3),
                Dec("@CostPrice", r.CostPrice),
                Dec("@SellPrice", r.SellPrice),
                new SqlParameter("@LocationId", locationId)).ToListAsync();
            return rows.First();
        }

        public async Task<MobileGrnLineRef> UpdateMobileGrnLineAsync(int idx, MobileGrnUpdateRequest r)
        {
            var rows = await Database.SqlQueryRaw<MobileGrnLineRef>(
                "EXEC dbo.z_sp_MobileGrnUpdateLine @Idx = @Idx, @Qty = @Qty, @CostPrice = @CostPrice, @SellPrice = @SellPrice",
                new SqlParameter("@Idx", idx),
                Dec("@Qty", r.Qty, 3),
                Dec("@CostPrice", r.CostPrice),
                Dec("@SellPrice", r.SellPrice)).ToListAsync();
            return rows.First();
        }

        public async Task<MobileGrnDeleteResult> DeleteMobileGrnLineAsync(int idx)
        {
            var rows = await Database.SqlQueryRaw<MobileGrnDeleteResult>(
                "EXEC dbo.z_sp_MobileGrnDeleteLine @Idx = @Idx",
                new SqlParameter("@Idx", idx)).ToListAsync();
            return rows.First();
        }
    }
}
