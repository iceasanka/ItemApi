using ItemApi.Interface;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class SystemController : ControllerBase
    {
        private readonly ISystemRepository _repository;

        public SystemController(ISystemRepository repository)
        {
            _repository = repository;
        }

        // GET: api/System/GenerateGrnNo?locaCode=01
        [HttpGet("GenerateGrnNo")]
        public async Task<IActionResult> GenerateGrnNo([FromQuery] string locaCode)
        {
            if (string.IsNullOrWhiteSpace(locaCode))
                return BadRequest(new { message = "LocaCode is required." });

            try
            {
                var grnNo = await _repository.GenerateNextGrnNoAsync(locaCode);
                return Ok(new { grnNo });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
