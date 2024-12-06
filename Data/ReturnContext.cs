using Microsoft.EntityFrameworkCore;
using ItemApi.Models;
using Microsoft.Data.SqlClient;

namespace ItemApi.Data
{
    public class ReturnContext : DbContext
    {
        public ReturnContext(DbContextOptions<ReturnContext> options) : base(options) { }

        public DbSet<ReturnItem> ReturnItems { get; set; }

        public DbSet<ReturnMode> ReturnModes { get; set; }
        public DbSet<PurchaseType> PurchaseTypes { get; set; }

        public DbSet<Supplier> Suppliers { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            // Map the ReturnItem entity to the z_tb_ReturnItem table
            modelBuilder.Entity<ReturnItem>().ToTable("z_tb_ReturnItem");

            modelBuilder.Entity<ReturnMode>().ToTable("tb_ReturnMode");
            modelBuilder.Entity<PurchaseType>().ToTable("tb_PurchaseType");

            modelBuilder.Entity<Supplier>().ToTable("TB_SUPPLIER");
        }

        public async Task<int> GetPRNOByLocaCodeAsync(string locaCode)
        {
            string sql = @"
                SELECT PRNO
                FROM tb_System
                WHERE LocaCode = {0}";

            var result = await this.Database.SqlQueryRaw<int>(sql, locaCode).ToListAsync();
            return result.FirstOrDefault();

        }

        public async Task<List<ReturnMode>> GetReturnModesAsync()
        {
            string sql = @"
        SELECT TypeId, TypeName
        FROM tb_ReturnMode";

            var result = await this.Database.SqlQueryRaw<ReturnMode>(sql).ToListAsync();
            return result;
        }

        public async Task<List<PurchaseType>> GetPurchaseTypesAsync()
        {
            string sql = @"
        SELECT TypeId, TypeName
        FROM tb_PurchaseType";

            var result = await this.Database.SqlQueryRaw<PurchaseType>(sql).ToListAsync();
            return result;
        }

        public async Task<Supplier> GetSupplierByCodeAsync(string suppCode)
        {
            string sql = @"
        SELECT Supp_Code, Supp_Name
        FROM dbo.TB_SUPPLIER
        WHERE Supp_Code = {0}";

            var result = await this.Database.SqlQueryRaw<Supplier>(sql, suppCode).ToListAsync();
            return result.FirstOrDefault();
        }

        public async Task UpdateReturnItemToTempPurchaseAsync(ReturnUpdateRequest request)
        {
            try
            {

                var sql = @"
        EXEC [dbo].[Sp_UPDATE_TEMP_PURCHASE]
        @UpdateStatus = {0},
        @SerialNo = {1},
        @SuppCode = {2},
        @ItemCode = {3},
        @Descrip = {4},
        @LocaCode = {5},
        @PackScale = {6},
        @Unit = {7},
        @Cost = {8},
        @Rate = {9},
        @ERate = {10},
        @Qty = {11},
        @DiscP = {12},
        @Discount = {13},
        @Amount = {14},
        @Id = {15},
        @UserName = {16},
        @PackSize = {17},
        @Remark = {18},
        @BarcodeSrl = {19},
        @CSCode = {20},
        @CSName = {21},
        @RowNo = {22},
        @Nbt = {23},
        @Tax = {24}";

                await this.Database.ExecuteSqlRawAsync(
                    sql,
                    request.UpdateStatus,
                    request.SerialNo,
                    request.SuppCode,
                    request.ItemCode,
                    request.Descrip,
                    request.LocaCode,
                    request.PackScale,
                    request.Unit,
                    request.Cost,
                    request.Rate,
                    request.ERate,
                    request.Qty,
                    request.DiscP,
                    request.Discount,
                    request.Amount,
                    request.Id,
                    request.UserName,
                    request.PackSize,
                    request.Remark,
                    request.BarcodeSrl,
                    request.CSCode,
                    request.CSName,
                    request.RowNo,
                    request.Nbt,
                    request.Tax
                );

            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error committing stock adjustment: {ex.Message}");
                throw; 
            }
        }

        public async Task CommitReturnToPurchaseAsync(CommitReturnItems request)
        {
            var sql = @"
        EXEC [dbo].[sp_UPDATE_PURCHASE_RTN] 
            @SerialNo = {0}, 
            @RefNo = {1}, 
            @PNDate = {2}, 
            @SuppCode = {3}, 
            @SuppName = {4}, 
            @PODNo = {5}, 
            @PType = {6}, 
            @PMode = {7}, 
            @GrossAmount = {8}, 
            @TotDiscount = {9}, 
            @SubTotDiscount = {10}, 
            @Tax = {11}, 
            @Advance = {12}, 
            @NetAmount = {13}, 
            @UserName = {14}, 
            @LocaCode = {15}, 
            @Status = {16}, 
            @IsExp = {17}, 
            @Nbt = {18}, 
            @Disc = {19}";

            await this.Database.ExecuteSqlRawAsync(sql,
                request.SerialNo,
                request.RefNo,
                request.PNDate,
                request.SuppCode,
                request.SuppName,
                request.PODNo,
                request.PType,
                request.PMode,
                request.GrossAmount,
                request.TotDiscount,
                request.SubTotDiscount,
                request.Tax,
                request.Advance,
                request.NetAmount,
                request.UserName,
                request.LocaCode,
                request.Status,
                request.IsExp,
                request.Nbt,
                request.Disc);
        }

        public async Task DeleteTempPurchaseAsync(DeleteTempPurchaseRequest request)
        {
            var sql = @"
EXEC [dbo].[Sp_DELETE_TEMP_PURCHASE]
    @SerialNo = {0}, 
    @ID = {1}, 
    @LocaCode = {2}, 
    @UserName = {3}, 
    @ItemCode = {4}, 
    @Cost = {5}, 
    @IdNo = {6}, 
    @CancelAll = {7}";

            await this.Database.ExecuteSqlRawAsync(sql,
                request.SerialNo,
                request.ID,
                request.LocaCode,
                request.UserName,
                request.ItemCode,
                request.Cost,
                request.IdNo,
                request.CancelAll);
        }






    }
}
