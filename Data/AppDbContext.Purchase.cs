using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Serilog;

namespace ItemApi.Data
{
    // Purchase commit/staging stored-procedure calls — consolidated from the former PurchaseContext.
    // No dedicated entities/DbSets of its own; everything here goes through raw SQL / stored procs.
    public partial class AppDbContext
    {
        public async Task<int> GetPNOByLocaCodeAsync(string locaCode)
        {
            try
            {
                string sql = @"
                SELECT PNO
                FROM tb_System
                WHERE LocaCode = {0}";

                var result = await this.Database.SqlQueryRaw<int>(sql, locaCode).ToListAsync();
                return result.FirstOrDefault();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw;
            }

        }

        public async Task UpdatePurchaseItemToTempPurchaseAsync(PurchaseUpdateRequest request)
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
        @Tax = {24},
        @ManufactureDate = {25}";


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
                    request.Tax,
                    request.ManufactureDate
                );

            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }

        public async Task CommitPurchaseAsync(CommitPurchaseItems request)
        {
            try
            {
                var sql = @"
                            EXEC [dbo].[sp_UPDATE_PURCHASE]
                                @SerialNo = {0},
                                @RefNo = {1},
                                @RefNo2 = {2},
                                @PNDate = {3},
                                @SuppCode = {4},
                                @SuppName = {5},
                                @PODNo = {6},
                                @PType = {7},
                                @PMode = {8},
                                @GrossAmount = {9},
                                @TotDiscount = {10},
                                @Tax = {11},
                                @Advance = {12},
                                @AdvPMode = {13},
                                @SubTotDiscount = {14},
                                @NetAmount = {15},
                                @UserName = {16},
                                @LocaCode = {17},
                                @Status = {18},
                                @Returns = {19},
                                @UpdPrice = {20},
                                @RefAmount = {21},
                                @IsExp = {22},
                                @Disc = {23},
                                @Nbt = {24},
                                @RoundingDiff = {25}";

                await this.Database.ExecuteSqlRawAsync(sql,
                    request.SerialNo,
                    request.RefNo,
                    request.RefNo2,
                    request.PNDate,
                    request.SuppCode,
                    request.SuppName,
                    request.PODNo,
                    request.PType,
                    request.PMode,
                    request.GrossAmount,
                    request.TotDiscount,
                    request.Tax,
                    request.Advance,
                    request.AdvPMode,
                    request.SubTotDiscount,
                    request.NetAmount,
                    request.UserName,
                    request.LocaCode,
                    request.Status,
                    request.Returns,
                    request.UpdPrice,
                    request.RefAmount,
                    request.IsExp,
                    request.Disc,
                    request.Nbt,
                    request.RoundingDiff
                );
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex.Message}");
                throw;
            }
        }
    }
}
