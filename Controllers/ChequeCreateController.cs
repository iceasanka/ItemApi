using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace ItemApi.Controllers
{

    [ApiController]
    [Route("api/[controller]")]
    public class ChequeCreateController : ControllerBase
    {


        private readonly IChequeCreateRepository _repository;
        

        public ChequeCreateController(IChequeCreateRepository repository)
        {
            _repository = repository;
         
        }

        [HttpPost("AddCheque")]
        public async Task<IActionResult> CreateCheque([FromBody] Cheque cheque)
        {
            if (cheque == null)
            {
                return BadRequest("Cheque data is required.");
            }

            if (await _repository.ChequeNumberExistsAsync(cheque.chequeNumber))
            {
                return Conflict(new
                {
                    code = "DUPLICATE_CHEQUE_NUMBER",
                    message = $"Cheque number {cheque.chequeNumber} already exists."
                });
            }

           

            var billsError = cheque.BillsError();
            if (billsError != null)
                return BadRequest(new { message = billsError });

            // supplier cheque (Docs/StockSystem.md §6.19): + a PAYMENT in the supplier ledger, paying the picked bills
            ChequeCreate chequeCreate;
            try
            {
                chequeCreate = await _repository.WriteChequeAsync(cheque);
            }
            catch (SqlException ex) when (ex.Number >= 50000)
            {
                // the first error is the proc's message; inside our transaction SQL adds "Transaction count ..." ones after it
                return BadRequest(new { message = ex.Errors.Count > 0 ? ex.Errors[0].Message : ex.Message });
            }

            bool isSyncSuccess = false;

            try
            {
                await _repository.SyncPrintedChequeAsync(chequeCreate);
                isSyncSuccess = true;
            }
            catch (Exception syncEx)
            {
                Console.WriteLine($"Cheque sync failed: {syncEx.Message}");
            }

            if (isSyncSuccess)
            {
                chequeCreate.IsSync = 1;
                await _repository.UpdateChequeAsync(chequeCreate);
            }
            //Asanka message

            return CreatedAtAction(nameof(GetChequeById), new { id = chequeCreate.ChequeId }, cheque);
        }

        // GET: api/ChequeCreate/5/bills — the supplier bills this cheque paid
        [HttpGet("{id:int}/bills")]
        public async Task<IActionResult> GetChequeBills(int id)
        {
            var cheque = await _repository.GetByIdAsync(id);
            if (cheque == null)
                return NotFound();
            return Ok(await _repository.GetChequeBillsAsync(id));
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> GetChequeById(int id)
        {
            var cheque = await _repository.GetByIdAsync(id);
            if (cheque == null)
            {
                return NotFound();
            }
            return Ok(cheque);
        }

        [HttpGet("search")]
        public async Task<IActionResult> SearchChequesByDateRange( 
            [FromQuery] DateTime fromDate,
            [FromQuery] DateTime toDate, 
            [FromQuery] int? chequeNumber,
            [FromQuery] string? supplierName,
            [FromQuery] decimal? amount)
        {
            var cheques = await _repository.SearchChequesByDateRangeAsync(fromDate, toDate, chequeNumber, supplierName, amount);
            return Ok(cheques);
        }

        [HttpGet("payee/{payeeId}")]
        public async Task<IActionResult> GetChequesByPayeeId(int payeeId)
        {
            var cheques = await _repository.GetChequesByPayeeIdAsync(payeeId);
            return Ok(cheques);
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> DeleteCheque(int id)
        {
            await _repository.DeleteChequeAsync(id);
            return NoContent();
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> UpdateCheque(int id, [FromBody] ChequeCreate cheque)
        {
            if (cheque == null || cheque.ChequeId != id)
            {
                return BadRequest("Invalid cheque data.");
            }

            var existingCheque = await _repository.GetByIdAsync(id);
            if (existingCheque == null)
            {
                return NotFound();
            }

            // its ledger payment pays bills for exactly this amount
            if (existingCheque.LedgerId != null && existingCheque.Amount != cheque.Amount)
                return BadRequest(new { message = "This cheque is in the supplier ledger — delete it and write it again to change the amount." });

            await _repository.UpdateChequeAsync(cheque);
            return NoContent();
        }


        [HttpPost("sync")]
        public async Task<IActionResult> SyncCheques([FromBody] IEnumerable<ChequeCreate> cheques)
        {
            if (cheques == null || !cheques.Any())
                return BadRequest("No cheque data received.");

        
            //Asanak :TOdo : i one fail what to do DB update
            await _repository.SyncChequesAsync(cheques);

            foreach (var cheque in cheques)
            {
                cheque.IsSync = 1;
                await _repository.UpdateChequeAsync(cheque);
            }
            

            return Ok(new { message = "Cheques synced successfully." });
        }

        [HttpPost("upload")]
        public async Task<IActionResult> UploadFile(IFormFile file)
        {
            if (file == null || file.Length == 0)
                return BadRequest("No file uploaded.");

            var uploadsFolder = Path.Combine(Directory.GetCurrentDirectory(), "Uploads");

            if (!Directory.Exists(uploadsFolder))
                Directory.CreateDirectory(uploadsFolder);

            var filePath = Path.Combine(uploadsFolder, file.FileName);

            using (var stream = new FileStream(filePath, FileMode.Create))
            {
                await file.CopyToAsync(stream);
            }
            var result = await _repository.ProcessFile(filePath);

            return Ok(new
            {
                message = "File uploaded successfully.",
                result
            });
        }

        /// <summary>
        /// Export upload rows (usually result.notUpdated from POST upload) as a CSV file.
        /// </summary>
        [HttpPost("upload/export")]
        public IActionResult ExportUploadRows([FromBody] List<ChequeUploadRow> rows)
        {
            if (rows == null || rows.Count == 0)
                return BadRequest("No rows to export.");

            var bytes = _repository.BuildUploadRowsCsv(rows);
            var fileName = $"Cheques_NotUpdated_{DateTime.Now:yyyyMMdd_HHmmss}.csv";

            return File(bytes, "text/csv", fileName);
        }


    }
}
