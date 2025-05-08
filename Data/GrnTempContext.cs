using ItemApi.Models;
using Microsoft.EntityFrameworkCore;
using Serilog;
using System;
using System.Linq;
using System.Threading.Tasks;

namespace ItemApi.Data
{
    public class GrnTempContext : DbContext
    {
        public GrnTempContext(DbContextOptions<GrnTempContext> options) : base(options) { }
        public DbSet<GrnTemp> _grnTemp { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<GrnTemp>().ToTable("z_tb_GrnTemp");
            base.OnModelCreating(modelBuilder);
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
                throw ;
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
                throw ;
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
                throw ;
            }
        }

        //get ist of grnitems by  GrnReference and status
        public async Task<IQueryable<GrnTemp>> GetGrnTempByGrnReferenceAndStatusAsync(string grnReference, int status)
        {
            try
            {
                var grnItems = _grnTemp.Where(x => x.GrnReference == grnReference && x.Status == status);
                return await Task.FromResult(grnItems);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw ;
            }
        }
        
        //update status of grnitems by Id
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
                throw ;
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
