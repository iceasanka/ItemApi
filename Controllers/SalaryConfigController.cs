using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class SalaryConfigController : ControllerBase
    {
        private readonly ISalaryConfigRepository _repository;

        public SalaryConfigController(ISalaryConfigRepository repository)
        {
            _repository = repository;
        }

        [HttpGet]
        public async Task<IActionResult> GetConfig()
        {
            var config = await _repository.GetConfigAsync();
            return Ok(config);
        }

        [HttpPut]
        public async Task<IActionResult> UpdateConfig([FromBody] SalaryConfig config)
        {
            if (config == null)
                return BadRequest("Config data is required.");

            await _repository.UpdateConfigAsync(config);
            return Ok(await _repository.GetConfigAsync());
        }
    }
}
