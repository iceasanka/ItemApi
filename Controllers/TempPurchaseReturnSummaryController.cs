using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Repositories;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class TempPurchaseReturnSummaryController : ControllerBase
    {
        private readonly ITempPurchaseReturnSummaryRepository _repository;

        private readonly ISystemRepository _systemrepository;

        private readonly IStockLedgerRepository _stockLedgerRepository;

        public TempPurchaseReturnSummaryController(ITempPurchaseReturnSummaryRepository repository, ISystemRepository systemRepository,
            IStockLedgerRepository stockLedgerRepository)
        {
            _repository = repository;
            _systemrepository = systemRepository;
            _stockLedgerRepository = stockLedgerRepository;
        }

        // POST: api/TempPurchaseReturnSummary/Commit/PRN00000001?userId=...
        // Takes the PRN lines out of stock (z_sp_PostPrn, -Qty) and sets Status = 2. A PRN can only be committed once.
        [HttpPost("Commit/{prnNo}")]
        public async Task<IActionResult> Commit([FromRoute] string prnNo, [FromQuery] string? userId)
        {
            try
            {
                var lines = await _stockLedgerRepository.PostPrnAsync(prnNo, userId);
                return Ok(new { message = "Commit successful.", data = prnNo, lines });
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                // not found / already posted / no lines — raised by z_sp_PostPurchaseDoc
                return BadRequest(new { message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
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
        public async Task<IActionResult> Insert([FromBody] TempPurchaseReturnSummary summary)
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
        public async Task<IActionResult> Update([FromBody] TempPurchaseReturnSummary summary)
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
        public async Task<IActionResult> Search([FromBody] TempPurchaseReturnSummarySearchRequest request)
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

        // PrnNo must be a PRN no (PRN00000001). Type is always saved as 2 by the repository.
        private static string? Validate(TempPurchaseReturnSummary summary)
        {
            if (summary == null || string.IsNullOrEmpty(summary.PrnNo))
                return "Invalid request data. PrnNo is required.";

            if (!summary.PrnNo.StartsWith(TempPurchaseReturnRepository.PrnPrefix))
                return "Invalid PRN No. It must start with 'PRN'.";

            return null;
        }
    }
}
