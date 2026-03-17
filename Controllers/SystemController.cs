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

        // PUT: api/System/UpdateGrnNo?locaCode=01
        [HttpPut("UpdateGrnNo")]
        public async Task<IActionResult> UpdateGrnNo([FromQuery] string locaCode)
        {
            if (string.IsNullOrWhiteSpace(locaCode))
                return BadRequest(new { message = "LocaCode is required." });

            try
            {
                var updatedGrnNo = await _repository.UpdateNextGrnNoAsync(locaCode);
                return Ok(new { updatedGrnNo });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
