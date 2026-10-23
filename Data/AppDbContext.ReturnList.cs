using System.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Return Items list on the new system (z_tb_ReturnList, U016). All reads and writes go through the z_sp_ procs;
    // Process makes a PRN and can post it to stock (z_sp_ReturnListToPrn -> z_sp_PostPrn).
    public partial class AppDbContext
    {
        // open rows (Added + Ready) when status is null; 3 = PRN made in the last `days` days
        public async Task<List<ReturnListRow>> GetReturnListAsync(int? suppId, int? status, int days)
        {
            return await Database.SqlQueryRaw<ReturnListRow>(
                "EXEC dbo.z_sp_GetReturnList @SuppId = @SuppId, @Status = @Status, @Days = @Days",
                new SqlParameter("@SuppId", SqlDbType.Int) { Value = Db(suppId is > 0 ? suppId : null) },
                new SqlParameter("@Status", SqlDbType.Int) { Value = Db(status) },
                new SqlParameter("@Days", days)).ToListAsync();
        }

        public async Task<int> AddReturnListItemAsync(ReturnListAddRequest r)
        {
            var ids = await Database.SqlQueryRaw<int>(
                "EXEC dbo.z_sp_AddReturnListItem @ItemId = @ItemId, @SuppId = @SuppId, @Qty = @Qty, @Reason = @Reason, " +
                "@Remark = @Remark, @Source = @Source, @UserId = @UserId, @LocationId = @LocationId",
                new SqlParameter("@ItemId", r.ItemId),
                new SqlParameter("@SuppId", r.SuppId),
                Dec("@Qty", r.Qty, 3),
                new SqlParameter("@Reason", SqlDbType.NVarChar, 50) { Value = Db(r.Reason) },
                new SqlParameter("@Remark", SqlDbType.NVarChar, 200) { Value = Db(r.Remark) },
                new SqlParameter("@Source", SqlDbType.TinyInt) { Value = r.Source == 1 ? (byte)1 : (byte)2 },
                new SqlParameter("@UserId", SqlDbType.NVarChar, 50) { Value = Db(r.UserId) },
                new SqlParameter("@LocationId", r.LocationId ?? 1)).ToListAsync();
            return ids.First();
        }

        public async Task UpdateReturnListItemAsync(int returnId, ReturnListUpdateRequest r)
        {
            await Database.ExecuteSqlRawAsync(
                "EXEC dbo.z_sp_UpdateReturnListItem @ReturnId = @ReturnId, @Qty = @Qty, @SuppId = @SuppId, @Reason = @Reason, " +
                "@Remark = @Remark, @UserId = @UserId",
                new SqlParameter("@ReturnId", returnId),
                Dec("@Qty", r.Qty, 3),
                new SqlParameter("@SuppId", r.SuppId),
                new SqlParameter("@Reason", SqlDbType.NVarChar, 50) { Value = Db(r.Reason) },
                new SqlParameter("@Remark", SqlDbType.NVarChar, 200) { Value = Db(r.Remark) },
                new SqlParameter("@UserId", SqlDbType.NVarChar, 50) { Value = Db(r.UserId) });
        }

        // Added (1) <-> Ready (2); rows with a PRN are left alone. Returns how many changed.
        public async Task<int> SetReturnListStatusAsync(IEnumerable<int> ids, int status, string? userId)
        {
            var n = await Database.SqlQueryRaw<int>(
                "EXEC dbo.z_sp_SetReturnListStatus @Ids = @Ids, @Status = @Status, @UserId = @UserId",
                Tvp("@Ids", "dbo.z_tt_IdList", IdTable(ids)),
                new SqlParameter("@Status", status),
                new SqlParameter("@UserId", SqlDbType.NVarChar, 50) { Value = Db(userId) }).ToListAsync();
            return n.FirstOrDefault();
        }

        // rows without a PRN only. Returns how many were deleted.
        public async Task<int> DeleteReturnListItemsAsync(IEnumerable<int> ids)
        {
            var n = await Database.SqlQueryRaw<int>(
                "EXEC dbo.z_sp_DeleteReturnListItems @Ids = @Ids",
                Tvp("@Ids", "dbo.z_tt_IdList", IdTable(ids))).ToListAsync();
            return n.FirstOrDefault();
        }

        public async Task<ReturnListPrnResult> ReturnListToPrnAsync(ReturnListProcessRequest r)
        {
            var rows = await Database.SqlQueryRaw<ReturnListPrnResult>(
                "EXEC dbo.z_sp_ReturnListToPrn @Ids = @Ids, @UserId = @UserId, @Post = @Post, @RefNo = @RefNo, @Remark = @Remark",
                Tvp("@Ids", "dbo.z_tt_IdList", IdTable(r.Ids)),
                new SqlParameter("@UserId", SqlDbType.VarChar, 20) { Value = Db(r.UserId?.Length > 20 ? r.UserId[..20] : r.UserId) },
                new SqlParameter("@Post", r.Post),
                new SqlParameter("@RefNo", SqlDbType.VarChar, 30) { Value = Db(r.RefNo) },
                new SqlParameter("@Remark", SqlDbType.VarChar, 200) { Value = Db(r.Remark) }).ToListAsync();
            return rows.First();
        }

        private static DataTable IdTable(IEnumerable<int> ids)
        {
            var t = new DataTable();
            t.Columns.Add("Id", typeof(int));
            foreach (var id in ids.Distinct())
                t.Rows.Add(id);
            return t;
        }
    }
}
