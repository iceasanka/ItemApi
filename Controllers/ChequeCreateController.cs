using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;

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

           

            ChequeCreate chequeCreate = new ChequeCreate();
            chequeCreate.Amount = cheque.amount;
            chequeCreate.ChequeDate = cheque.chequeDate;
            chequeCreate.PayeeId = cheque.payeeId;
            chequeCreate.SupplierName = cheque.supplierName;
            chequeCreate.ChequeNumber = cheque.chequeNumber;
            chequeCreate.IsSync = 0;

            await _repository.AddChequeAsync(chequeCreate);

            bool isSyncSuccess = false;

            try
            {
               // await _repository.SyncPrintedChequeAsync(chequeCreate);
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
            await _repository.ProcessFile(filePath);

            return Ok(new { message = "File uploaded successfully." });
        }


    }
}
