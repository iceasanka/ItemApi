using Microsoft.EntityFrameworkCore;
using ItemApi.Models;

namespace ItemApi.Data
{
    public class StockContext : DbContext
    {
        public StockContext(DbContextOptions<StockContext> options) : base(options) { }

        public DbSet<StockCountResult> dbStocks { get; set; }

        public DbSet<SpHasExistsSrlNewResult> SpHasExistsSrlNewResults { get; set; }


        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<StockCountResult>().HasNoKey();
            modelBuilder.Entity<SpHasExistsSrlNewResult>().HasNoKey();
        }

        public async Task<StockCountResult> GetStockByItemcodeAsync(string itemcode)
        {
            var query = @"
            SELECT Isnull(Cast(Sum(CASE [id]
                         WHEN 'OPB' THEN ( packsize * qty )
                         WHEN 'PCH' THEN ( packsize * qty )
                         WHEN 'PRN' THEN -( packsize * qty )
                         WHEN 'INV' THEN -( packsize * qty )
                         WHEN 'MKR' THEN ( packsize * qty )
                         WHEN 'DMG' THEN -( packsize * qty )
                         WHEN 'PRD' THEN -( packsize * qty )
                         WHEN 'DSC' THEN -( packsize * qty )
                         WHEN 'ADD' THEN ( packsize * qty )
                         WHEN 'TOG' THEN -( packsize * qty )
                         WHEN 'IN1' THEN ( packsize * qty )
                         WHEN 'IN2' THEN ( packsize * qty )
                         WHEN 'AOD' THEN -( packsize * qty )
                         ELSE 0
                       END) AS DECIMAL(18, 3)), 0) AS Stock
            FROM   tb_stock
            WHERE  locacode = '01'
                   AND status = 1
                   AND tb_stock.itemcode = {0}";

            return await dbStocks.FromSqlRaw(query, itemcode).FirstOrDefaultAsync();
        }

        public async Task<int> GetOpbByLocaCodeAsync(string locaCode)
        {
            string sql = @"
                SELECT OPB
                FROM tb_System
                WHERE LocaCode = {0}";

            var result = await this.Database.SqlQueryRaw<int>(sql, locaCode).ToListAsync();
            return result.FirstOrDefault();

        }

        public async Task<List<SpHasExistsSrlNewResult>> ExecuteSpHasExistsSrlNewAsync(string locaCode, string itemCode, string serialCode, decimal qty, int type, string fromLoca, string toLoca, string id, string serialNo)
        {
            try
            {
                string sql = "EXEC SP_HAS_EXISTS_SRL_NEW @LocaCode = {0}, @ItemCode = {1}, @SerialCode = {2}, @Qty = {3}, @Type = {4}, @FromLoca = {5}, @ToLoca = {6}, @Id = {7}, @SerialNo = {8}";

                return await SpHasExistsSrlNewResults.FromSqlRaw(sql, locaCode, itemCode, serialCode, qty, type, fromLoca, toLoca, id, serialNo).ToListAsync();

            }
            catch (Exception ex)
            {
                // Log the exception if necessary
                Console.WriteLine($"Error committing stock adjustment: {ex.Message}");
                throw; // Rethrow the exception if you want to propagate it
            }
        }

        public async Task UpdateStockAsync(UpdateStockParams updateStockParams)
        {
            try
            {
                await this.Database.ExecuteSqlRawAsync(
                        "EXEC Sp_UPDATE_TEMP_ADJUST @SERIALNO = {0}, @ID = {1}, @ITEMCODE = {2}, @SUPPCODE = {3}, @ITEMDESCRIP = {4}, @SCALE = {5}, @PACKSIZE = {6}, @COSTPRICE = {7}, @RETPRICE = {8}, @STOCK = {9}, @COSTVALUE = {10}, @RETVALUE = {11}, @REMARK = {12}, @UPDATION = {13}, @REMARKEXP = {14}, @BARCODESRL = {15}, @CSCODE = {16}, @CSNAME = {17}, @LOCACODE = {18}",
                        updateStockParams.SerialNo, updateStockParams.Id, updateStockParams.ItemCode, updateStockParams.SuppCode, updateStockParams.ItemDescrip, updateStockParams.Scale, updateStockParams.PackSize, updateStockParams.CostPrice, updateStockParams.RetPrice, updateStockParams.Stock, updateStockParams.CostValue, updateStockParams.RetValue, updateStockParams.Remark, updateStockParams.Updation, updateStockParams.RemarkExp, updateStockParams.BarcodeSrl, updateStockParams.CsCode, updateStockParams.CsName, updateStockParams.LocaCode
                    );

            }
            catch (Exception ex)
            {
                // Log the exception if necessary
                Console.WriteLine($"Error committing stock adjustment: {ex.Message}");
                throw; // Rethrow the exception if you want to propagate it
            }
        }

        public async Task CommitStockAdjustmentAsync(CommitStockAdjustmentParams commitStockAdjustmentParams)
        {
            try
            {
                await this.Database.ExecuteSqlRawAsync(
                    "EXEC sp_UPDATE_STADJUST @SERIALNO = {0}, @REFNO = {1}, @LOCACODE = {2}, @IDATE = {3}, @COSTVALUE = {4}, @RETVALUE = {5}, @ID = {6}, @USERNAME = {7}, @STATUS = {8}, @TYPE = {9}, @ISEXP = {10}",
                    commitStockAdjustmentParams.SerialNo, commitStockAdjustmentParams.RefNo, commitStockAdjustmentParams.LocaCode, commitStockAdjustmentParams.IDate, commitStockAdjustmentParams.CostValue, commitStockAdjustmentParams.RetValue, commitStockAdjustmentParams.Id, commitStockAdjustmentParams.UserName, commitStockAdjustmentParams.Status, commitStockAdjustmentParams.Type, commitStockAdjustmentParams.IsExp
                );
            }
            catch (Exception ex)
            {
                // Log the exception if necessary
                Console.WriteLine($"Error committing stock adjustment: {ex.Message}");
                throw; // Rethrow the exception if you want to propagate it
            }
        }
    }
}
