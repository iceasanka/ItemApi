using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Repositories;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class TempPurchaseReturnController : ControllerBase
    {
        private readonly ITempPurchaseReturnRepository _repository;

        public TempPurchaseReturnController(ITempPurchaseReturnRepository repository)
        {
            _repository = repository;
        }

        // POST: api/TempPurchaseReturn/Insert
        [HttpPost("Insert")]
        public async Task<IActionResult> Insert([FromBody] TempPurchase tempPurchase)
        {
            if (tempPurchase == null || string.IsNullOrEmpty(tempPurchase.GrnNo))
                return BadRequest(new { message = "Invalid request data. PRN No (GrnNo) is required." });

            if (!tempPurchase.GrnNo.StartsWith(TempPurchaseReturnRepository.PrnPrefix))
                return BadRequest(new { message = "Invalid PRN No. It must start with 'PRN'." });

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

        // PUT: api/TempPurchaseReturn/Update
        [HttpPut("Update")]
        public async Task<IActionResult> Update([FromBody] TempPurchase tempPurchase)
        {
            if (tempPurchase == null || tempPurchase.Idx <= 0)
                return BadRequest(new { message = "Invalid request data. Idx is required." });

            if (string.IsNullOrEmpty(tempPurchase.GrnNo) || !tempPurchase.GrnNo.StartsWith(TempPurchaseReturnRepository.PrnPrefix))
                return BadRequest(new { message = "Invalid PRN No. It must start with 'PRN'." });

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

        // DELETE: api/TempPurchaseReturn/Delete/1
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

        // GET: api/TempPurchaseReturn/GetByPrnNo?prnNo=PRN00000001
        [HttpGet("GetByPrnNo")]
        public async Task<IActionResult> GetByPrnNo([FromQuery] string prnNo)
        {
            if (string.IsNullOrWhiteSpace(prnNo))
                return BadRequest(new { message = "PrnNo is required." });

            try
            {
                var result = await _repository.GetByPrnNoAsync(prnNo);
                return Ok(result);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
