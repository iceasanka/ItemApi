using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class SalaryAttendanceController : ControllerBase
    {
        private readonly ISalaryAttendanceRepository _repository;
        private readonly ISalaryHolidayRepository _holidayRepository;

        public SalaryAttendanceController(
            ISalaryAttendanceRepository repository,
            ISalaryHolidayRepository holidayRepository)
        {
            _repository = repository;
            _holidayRepository = holidayRepository;
        }

        [HttpGet]
        public async Task<IActionResult> GetMonth([FromQuery] int month, [FromQuery] int year)
        {
            var entries = await _repository.GetByMonthAsync(month, year);
            return Ok(entries);
        }

        [HttpPost("bulk")]
        public async Task<IActionResult> SaveBulk([FromBody] List<SalaryAttendance> entries)
        {
            if (entries == null || entries.Count == 0)
                return BadRequest("No attendance entries received.");

            await _repository.SaveBulkAsync(entries);
            return Ok(new { message = "Attendance saved successfully." });
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] SalaryAttendance entry)
        {
            if (entry == null || entry.AttendanceId != id)
                return BadRequest("Invalid attendance data.");

            if (!await _repository.ExistsAsync(id))
                return NotFound();

            await _repository.UpdateAsync(entry);
            return NoContent();
        }

        [HttpGet("~/api/holidays")]
        public async Task<IActionResult> GetHolidays([FromQuery] int month, [FromQuery] int year)
        {
            var holidays = await _holidayRepository.GetByMonthAsync(month, year);
            return Ok(holidays);
        }

        [HttpPost("~/api/holidays")]
        public async Task<IActionResult> AddHoliday([FromBody] SalaryHoliday holiday)
        {
            if (holiday == null)
                return BadRequest("Holiday data is required.");

            await _holidayRepository.AddAsync(holiday);
            return Ok(holiday);
        }

        [HttpDelete("~/api/holidays/{id}")]
        public async Task<IActionResult> DeleteHoliday(int id)
        {
            await _holidayRepository.DeleteAsync(id);
            return NoContent();
        }
    }
}
