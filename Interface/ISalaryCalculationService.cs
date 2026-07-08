using ItemApi.Models;

namespace ItemApi.Interface
{
    public interface ISalaryCalculationService
    {
        /// <summary>
        /// Computes payslips for every active employee for the given month/year,
        /// persists them (Draft status) and returns the computed list.
        /// </summary>
        Task<List<SalaryPayslip>> CalculateAndSaveMonthAsync(int month, int year);
    }
}
