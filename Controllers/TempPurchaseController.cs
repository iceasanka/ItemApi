using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class TempPurchaseController : ControllerBase
    {
        private readonly ITempPurchaseRepository _repository;

        public TempPurchaseController(ITempPurchaseRepository repository)
        {
            _repository = repository;
        }

        // POST: api/TempPurchase/Insert
        [HttpPost("Insert")]
        public async Task<IActionResult> Insert([FromBody] TempPurchase tempPurchase)
        {
            if (tempPurchase == null || string.IsNullOrEmpty(tempPurchase.GrnNo))
                return BadRequest(new { message = "Invalid request data. GrnNo is required." });

            try
            {
                var result = await _repository.InsertAsync(tempPurchase);
                return Ok(new { message = "Record inserted successfully.", data = result });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // PUT: api/TempPurchase/Update
        [HttpPut("Update")]
        public async Task<IActionResult> Update([FromBody] TempPurchase tempPurchase)
        {
            if (tempPurchase == null || tempPurchase.Idx <= 0)
                return BadRequest(new { message = "Invalid request data. Idx is required." });

            try
            {
                var result = await _repository.UpdateAsync(tempPurchase);
                return Ok(new { message = "Record updated successfully.", data = result });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // DELETE: api/TempPurchase/Delete/1
        [HttpDelete("Delete/{idx}")]
        public async Task<IActionResult> Delete(int idx)
        {
            if (idx <= 0)
                return BadRequest(new { message = "Invalid Idx." });

            try
            {
                var deleted = await _repository.DeleteAsync(idx);
                if (!deleted)
                    return NotFound(new { message = $"Record with Idx {idx} not found.", status = false });

                return Ok(new { message = "Record deleted successfully.", status = true });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/TempPurchase/GetByGrnNo?grnNo=GRN001
        [HttpGet("GetByGrnNo")]
        public async Task<IActionResult> GetByGrnNo([FromQuery] string grnNo)
        {
            if (string.IsNullOrWhiteSpace(grnNo))
                return BadRequest(new { message = "GrnNo is required." });

            try
            {
                var result = await _repository.GetByGrnNoAsync(grnNo);
                return Ok(result);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
