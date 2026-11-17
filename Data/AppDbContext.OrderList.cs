using System.Data;
using ItemApi.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Data
{
    // Tools > Order Lists (DBScript/41_BackOffice_OrderLists.sql, Updates/U063) - all through the z_sp_OrderList* procs.
    public partial class AppDbContext
    {
        public async Task<List<OrderListDto>> OrderListGetAsync()
        {
            var rows = await Database.SqlQueryRaw<OrderListFlatRow>("EXEC dbo.z_sp_OrderListGet").ToListAsync();
            return rows.GroupBy(r => r.ListId).Select(g => new OrderListDto
            {
                ListId = g.Key,
                Kind = g.First().Kind,
                Sinhala = g.First().Sinhala,
                Name = g.First().ListName,
                Lines = g.Where(r => r.LineId != null).Select(r => new OrderListLineDto
                {
                    LineId = r.LineId!.Value, ItemId = r.ItemId, Descrip = r.Descrip, ItemDescrip = r.ItemDescrip, ItemSinhala = r.ItemSinhala, RefCode = r.RefCode, Barcode = r.Barcode,
                    Active = r.ItemId == null || r.ItemStatus == 1, Note = r.Note
                }).ToList()
            }).ToList();
        }

        // listId null = a new list of kind (1 order, 2 code list); returns the list id
        public async Task<int> OrderListSaveAsync(int? listId, string? name, byte kind = 1) =>
            (await Database.SqlQueryRaw<OrderListIdRow>("EXEC dbo.z_sp_OrderListSave @ListId = @ListId, @Name = @Name, @Kind = @Kind",
                new SqlParameter("@ListId", SqlDbType.Int) { Value = Db(listId) },
                new SqlParameter("@Name", SqlDbType.NVarChar, 50) { Value = Db(Cut(name?.Trim(), 50)) },
                new SqlParameter("@Kind", SqlDbType.TinyInt) { Value = kind == 2 ? (byte)2 : (byte)1 }).ToListAsync()).First().ListId;

        public Task OrderListDeleteAsync(int listId) =>
            Database.ExecuteSqlRawAsync("EXEC dbo.z_sp_OrderListDelete @ListId = @ListId", new SqlParameter("@ListId", listId));

        public async Task<int> OrderListAddLineAsync(int listId, OrderListLineRequest r) =>
            (await Database.SqlQueryRaw<OrderListLineIdRow>(
                "EXEC dbo.z_sp_OrderListAddLine @ListId = @ListId, @ItemId = @ItemId, @Text = @Text, @Note = @Note",
                new SqlParameter("@ListId", listId),
                new SqlParameter("@ItemId", SqlDbType.Int) { Value = Db(r.ItemId is > 0 ? r.ItemId : null) },
                new SqlParameter("@Text", SqlDbType.NVarChar, 100) { Value = Db(Cut(r.Text?.Trim(), 100)) },
                new SqlParameter("@Note", SqlDbType.NVarChar, 50) { Value = Db(Cut(r.Note?.Trim(), 50)) }).ToListAsync()).First().LineId;

        public Task OrderListUpdateLineAsync(int lineId, OrderListLineRequest r) =>
            Database.ExecuteSqlRawAsync("EXEC dbo.z_sp_OrderListUpdateLine @LineId = @LineId, @Text = @Text, @Note = @Note",
                new SqlParameter("@LineId", lineId),
                new SqlParameter("@Text", SqlDbType.NVarChar, 100) { Value = Db(Cut(r.Text?.Trim(), 100)) },
                new SqlParameter("@Note", SqlDbType.NVarChar, 50) { Value = Db(Cut(r.Note?.Trim(), 50)) });

        public Task OrderListRemoveLineAsync(int lineId) =>
            Database.ExecuteSqlRawAsync("EXEC dbo.z_sp_OrderListRemoveLine @LineId = @LineId", new SqlParameter("@LineId", lineId));

        public Task OrderListMoveLineAsync(int lineId, bool up) =>
            Database.ExecuteSqlRawAsync("EXEC dbo.z_sp_OrderListMoveLine @LineId = @LineId, @Up = @Up",
                new SqlParameter("@LineId", lineId), new SqlParameter("@Up", up));

        public Task OrderListSetSinhalaAsync(int listId, bool sinhala) =>
            Database.ExecuteSqlRawAsync("EXEC dbo.z_sp_OrderListSetSinhala @ListId = @ListId, @Sinhala = @Sinhala",
                new SqlParameter("@ListId", listId), new SqlParameter("@Sinhala", sinhala));

        // byCode = by ref code instead of the name
        public Task OrderListSortByNameAsync(int listId, bool byCode = false) =>
            Database.ExecuteSqlRawAsync("EXEC dbo.z_sp_OrderListSortByName @ListId = @ListId, @ByCode = @ByCode",
                new SqlParameter("@ListId", listId), new SqlParameter("@ByCode", byCode));
    }
}
