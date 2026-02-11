using ItemApi.Interface;
using ItemApi.Models;
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

        [HttpPost]
        public async Task<IActionResult> CreateCheque([FromBody] ChequeCreate cheque)
        {
            if (cheque == null)
            {
                return BadRequest("Cheque data is required.");
            }

            await _repository.AddChequeAsync(cheque);
            return CreatedAtAction(nameof(GetChequeById), new { id = cheque.ChequeId }, cheque);
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
        public async Task<IActionResult> SearchChequesByDateRange( [FromQuery] DateTime fromDate,[FromQuery] DateTime toDate )
        {
            var cheques = await _repository.SearchChequesByDateRangeAsync(fromDate, toDate);
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




    }
}
