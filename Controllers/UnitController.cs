using ItemApi.Interface;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class UnitController : ControllerBase
    {
        private readonly IUnitRepository _repository;

        public UnitController(IUnitRepository repository)
        {
            _repository = repository;
        }

        [HttpGet("GetAllUnits")]
        public async Task<IActionResult> GetAllUnits()
        {
            try
            {
                var units = await _repository.GetAllUnitsAsync();
                return Ok(units);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
