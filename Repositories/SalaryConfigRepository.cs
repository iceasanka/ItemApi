using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Repositories
{
    public class SalaryConfigRepository : ISalaryConfigRepository
    {
        private readonly SalaryContext _context;

        public SalaryConfigRepository(SalaryContext context)
        {
            _context = context;
        }

        // There is always exactly one config row (seeded by the DB script). Take the first.
        public async Task<SalaryConfig> GetConfigAsync()
        {
            return await _context.SalaryConfigs.OrderBy(c => c.ConfigId).FirstAsync();
        }

        public async Task UpdateConfigAsync(SalaryConfig config)
        {
            var existing = await GetConfigAsync();

            existing.BasicSalary = config.BasicSalary;
            existing.ByShop = config.ByShop;
            existing.AttendanceBonus = config.AttendanceBonus;
            existing.OtRate = config.OtRate;
            existing.MhPay = config.MhPay;
            existing.MhOtRate = config.MhOtRate;
            existing.TargetBonus = config.TargetBonus;
            existing.IsTargetBonusEnabled = config.IsTargetBonusEnabled;
            existing.ModifiedDate = DateTime.Now;

            await _context.SaveChangesAsync();
        }
    }
}
