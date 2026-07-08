using ItemApi.Interface;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class SalaryPayslipController : ControllerBase
    {
        private readonly ISalaryCalculationService _calculationService;
        private readonly ISalaryPayslipRepository _payslipRepository;

        public SalaryPayslipController(
            ISalaryCalculationService calculationService,
            ISalaryPayslipRepository payslipRepository)
        {
            _calculationService = calculationService;
            _payslipRepository = payslipRepository;
        }

        // Computes payslips for every active employee for the month and persists them (Draft).
        [HttpGet]
        public async Task<IActionResult> GetMonth([FromQuery] int month, [FromQuery] int year)
        {
            if (month < 1 || month > 12)
                return BadRequest("Month must be between 1 and 12.");

            var payslips = await _calculationService.CalculateAndSaveMonthAsync(month, year);
            return Ok(payslips);
        }

        [HttpGet("{employeeId}")]
        public async Task<IActionResult> GetForEmployee(int employeeId, [FromQuery] int month, [FromQuery] int year)
        {
            var payslip = await _payslipRepository.GetByEmployeeAndMonthAsync(employeeId, month, year);
            if (payslip == null)
                return NotFound();

            return Ok(payslip);
        }
    }
}
