using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Repositories;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class TempPurchaseReturnSummaryController : ControllerBase
    {
        private readonly ITempPurchaseReturnSummaryRepository _repository;

        private readonly ISystemRepository _systemrepository;

        public TempPurchaseReturnSummaryController(ITempPurchaseReturnSummaryRepository repository, ISystemRepository systemRepository)
        {
            _repository = repository;
            _systemrepository = systemRepository;
        }

        // GET: api/TempPurchaseReturnSummary/GetAll
        [HttpGet("GetAll")]
        public async Task<IActionResult> GetAll()
        {
            try
            {
                var result = await _repository.GetAllAsync();
                return Ok(result);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GET: api/TempPurchaseReturnSummary/GetById/1
        [HttpGet("GetById/{idx}")]
        public async Task<IActionResult> GetById(int idx)
        {
            try
            {
                var result = await _repository.GetByIdAsync(idx);
                if (result == null)
                    return NotFound(new { message = $"Record with Idx {idx} not found.", status = false });

                return Ok(result);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // POST: api/TempPurchaseReturnSummary/Insert
        [HttpPost("Insert")]
        public async Task<IActionResult> Insert([FromBody] TempPurchaseSummary summary)
        {
            var error = Validate(summary);
            if (error != null)
                return BadRequest(new { message = error });

            try
            {
                var result = await _repository.InsertAsync(summary);
                var updatePrnNo = await _systemrepository.UpdateNextPrnNoAsync("01");
                return Ok(new { message = "Record inserted successfully.", data = result });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // PUT: api/TempPurchaseReturnSummary/Update
        [HttpPut("Update")]
        public async Task<IActionResult> Update([FromBody] TempPurchaseSummary summary)
        {
            if (summary == null || summary.Idx <= 0)
                return BadRequest(new { message = "Invalid request data. Idx is required." });

            var error = Validate(summary);
            if (error != null)
                return BadRequest(new { message = error });

            try
            {
                var result = await _repository.UpdateAsync(summary);
                return Ok(new { message = "Record updated successfully.", data = result });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // DELETE: api/TempPurchaseReturnSummary/Delete/1
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

        // POST: api/TempPurchaseReturnSummary/Search
        [HttpPost("Search")]
        public async Task<IActionResult> Search([FromBody] TempPurchaseSummarySearchRequest request)
        {
            try
            {
                var result = await _repository.SearchAsync(request);
                return Ok(result);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // GrnNo carries the PRN no (PRN00000001) and Type must be 2 (sent from UI)
        private static string? Validate(TempPurchaseSummary summary)
        {
            if (summary == null || string.IsNullOrEmpty(summary.GrnNo))
                return "Invalid request data. PRN No (GrnNo) is required.";

            if (!summary.GrnNo.StartsWith(TempPurchaseReturnRepository.PrnPrefix))
                return "Invalid PRN No. It must start with 'PRN'.";

            if (summary.Type != TempPurchaseReturnSummaryRepository.ReturnType)
                return $"Invalid Type. Purchase return Type must be {TempPurchaseReturnSummaryRepository.ReturnType}.";

            return null;
        }
    }
}
