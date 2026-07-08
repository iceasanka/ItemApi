using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class SalaryAdvancesController : ControllerBase
    {
        private readonly ISalaryAdvanceRepository _repository;

        public SalaryAdvancesController(ISalaryAdvanceRepository repository)
        {
            _repository = repository;
        }

        [HttpGet]
        public async Task<IActionResult> Get([FromQuery(Name = "emp")] int? employeeId, [FromQuery] int month, [FromQuery] int year)
        {
            var advances = await _repository.GetByEmployeeAndMonthAsync(employeeId, month, year);
            return Ok(advances);
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] SalaryAdvance advance)
        {
            if (advance == null || advance.Amount <= 0)
                return BadRequest("A valid advance amount is required.");

            await _repository.AddAsync(advance);
            return Ok(advance);
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            await _repository.DeleteAsync(id);
            return NoContent();
        }
    }
}
