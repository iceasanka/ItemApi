using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class SalaryEmployeesController : ControllerBase
    {
        private readonly ISalaryEmployeeRepository _repository;

        public SalaryEmployeesController(ISalaryEmployeeRepository repository)
        {
            _repository = repository;
        }

        [HttpGet]
        public async Task<IActionResult> GetAll()
        {
            var employees = await _repository.GetAllActiveAsync();
            return Ok(employees);
        }

        [HttpGet("all")]
        public async Task<IActionResult> GetAllIncludingInactive()
        {
            var employees = await _repository.GetAllAsync();
            return Ok(employees);
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> GetById(int id)
        {
            var employee = await _repository.GetByIdAsync(id);
            if (employee == null)
                return NotFound();

            return Ok(employee);
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] SalaryEmployee employee)
        {
            if (employee == null || string.IsNullOrWhiteSpace(employee.EmployeeName))
                return BadRequest("Employee name is required.");

            await _repository.AddAsync(employee);
            return CreatedAtAction(nameof(GetById), new { id = employee.EmployeeId }, employee);
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] SalaryEmployee employee)
        {
            if (employee == null || employee.EmployeeId != id)
                return BadRequest("Invalid employee data.");

            if (!await _repository.ExistsAsync(id))
                return NotFound();

            await _repository.UpdateAsync(employee);
            return NoContent();
        }

        // Soft delete: matches the design doc ("deactivate"), not a physical row delete,
        // since attendance/advance/payslip rows reference this employee.
        [HttpDelete("{id}")]
        public async Task<IActionResult> Deactivate(int id)
        {
            var existing = await _repository.GetByIdAsync(id);
            if (existing == null)
                return NotFound();

            await _repository.DeactivateAsync(id);
            return NoContent();
        }
    }
}
