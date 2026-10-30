using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class TempPurchaseSummaryController : ControllerBase
    {
        private readonly ITempPurchaseSummaryRepository _repository;

        private readonly ISystemRepository _systemrepository;

        private readonly IStockLedgerRepository _stockLedgerRepository;

        public TempPurchaseSummaryController(ITempPurchaseSummaryRepository repository, ISystemRepository systemRepository,
            IStockLedgerRepository stockLedgerRepository)
        {
            _repository = repository;
            _systemrepository = systemRepository;
            _stockLedgerRepository = stockLedgerRepository;
        }

        // GET: api/TempPurchaseSummary/GetAll
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

        // GET: api/TempPurchaseSummary/GetById/1
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

        // POST: api/TempPurchaseSummary/Insert — a new GRN. Its number is taken here (z_tb_System.PNO), not the one the
        // page showed: with two tabs / browsers open, or a GRN scan / mobile draft made meanwhile, that one may be used.
        // → data = the saved summary; the page saves the lines with data.grnNo.
        [HttpPost("Insert")]
        public async Task<IActionResult> Insert([FromBody] TempPurchaseSummary summary)
        {
            if (summary == null)
                return BadRequest(new { message = "Invalid request data." });

            try
            {
                summary.GrnNo = await _systemrepository.TakeNextGrnNoAsync("01");
                var result = await _repository.InsertAsync(summary);
                return Ok(new { message = $"{result.GrnNo} saved.", data = result });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // PUT: api/TempPurchaseSummary/Update
        [HttpPut("Update")]
        public async Task<IActionResult> Update([FromBody] TempPurchaseSummary summary)
        {
            if (summary == null || summary.Idx <= 0)
                return BadRequest(new { message = "Invalid request data. Idx is required." });

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

        // DELETE: api/TempPurchaseSummary/Delete/1
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

        // DELETE: api/TempPurchaseSummary/DeleteDraft/GRN00000001 — a GRN draft (suspended / saved, not committed) with its
        // lines; a GRN scan made into it is open again on GRN Scan to correct and make again
        [HttpDelete("DeleteDraft/{grnNo}")]
        public async Task<IActionResult> DeleteDraft([FromRoute] string grnNo)
        {
            if (string.IsNullOrWhiteSpace(grnNo))
                return BadRequest(new { message = "GrnNo is required." });

            try
            {
                return await _repository.DeleteDraftAsync(grnNo.Trim()) switch
                {
                    1 => NotFound(new { message = $"{grnNo} not found." }),
                    2 => BadRequest(new { message = $"{grnNo} is committed to stock - it can't be deleted." }),
                    _ => Ok(new { message = $"{grnNo} deleted." })
                };
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }

        // POST: api/TempPurchaseSummary/Search
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

        // POST: api/TempPurchaseSummary/Commit/GRN00000001?userId=...
        // Posts the GRN lines into stock (z_sp_PostGrn, +Qty) and sets Status = 2. A GRN can only be committed once.
        [HttpPost("Commit/{grnNo}")]
        public async Task<IActionResult> Commit([FromRoute] string grnNo, [FromQuery] string? userId)
        {
            try
            {
                var lines = await _stockLedgerRepository.PostGrnAsync(grnNo, userId);
                return Ok(new { message = "Commit successful.", data = grnNo, lines });
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
    }
}
