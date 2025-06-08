using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{

    [ApiController]
    [Route("api/[controller]")]
    public class GrnTempController : ControllerBase
    {
        private readonly GrnTempContext _context;
        private readonly IGrnTempRepository _repository;

        public GrnTempController(GrnTempContext context, IGrnTempRepository repository)
        {
            _context = context;
            _repository = repository;
        }

        [HttpPost("AddGrnTemp")]
        public async Task<IActionResult> AddGrnTemp([FromBody] GrnTemp grnTemp)
        {
            if (grnTemp == null || string.IsNullOrEmpty(grnTemp.ItemCode))
            {
                return BadRequest("Invalid request data.");
            }

            try
            {
                var insertedGrnTemp = await _repository.InsertGrnTempAsync(grnTemp);

                return Ok(new { message = "GrnTemp added successfully.", data = insertedGrnTemp });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        [HttpPut("UpdateGrnTemp")]
        public async Task<IActionResult> UpdateGrnTemp([FromBody] GrnTemp grnTemp)
        {
            if (grnTemp == null || grnTemp.Id <= 0)
            {
                return BadRequest("Invalid request data.");
            }

            try
            {
                var updatedGrnTemp = await _repository.UpdateGrnTempAsync(grnTemp);

                return Ok(new { message = "GrnTemp updated successfully.", data = updatedGrnTemp });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        [HttpDelete("DeleteGrnTemp/{id}")]
        public async Task<IActionResult> DeleteGrnTemp(int id)
        {
            if (id <= 0)
            {
                return BadRequest("Invalid ID.");
            }

            try
            {
                var deletedGrnTemp = await _repository.DeleteGrnTempAsync(id);

                if (deletedGrnTemp == null)
                {
                    return NotFound(new { message = "No record found to delete.",status=false });
                }

                return Ok(new { message = "GrnTemp deleted successfully.", data = deletedGrnTemp, status = true });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        [HttpGet("GetGrnTempByGrnReferenceAndStatus")]
        public async Task<IActionResult> GetGrnTempByGrnReferenceAndStatus(string grnReference, int status)
        {
            if (string.IsNullOrEmpty(grnReference) || status < 0)
            {
                return BadRequest("Invalid request data.");
            }

            try
            {
                var grnItems = await _repository.GetGrnTempByGrnReferenceAndStatusAsync(grnReference, status);

                if (grnItems == null || !grnItems.Any())
                {
                    return Ok(new { message = "No records found", data = grnItems }); 
                }

                return Ok(new { message = "GrnTemp records retrieved successfully.", data = grnItems });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        [HttpPut("UpdateGrnTempStatus/{id}/{status}")]
        public async Task<IActionResult> UpdateGrnTempStatus(int id, int status)
        {
            if (id <= 0 || status < 0)
            {
                return BadRequest("Invalid request data.");
            }

            try
            {
                var updatedGrnTemp = await _repository.UpdateGrnTempStatusAsync(id, status);

                if (updatedGrnTemp == null)
                {
                    return Ok(new { message = "No records found", data = updatedGrnTemp });
                }

                return Ok(new { message = "GrnTemp status updated successfully.", data = updatedGrnTemp });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

            


    }


}
