using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class PayeeController : ControllerBase
    {

        private readonly IPayeeRepository _repository;

        public PayeeController(IPayeeRepository repository)
        {
            _repository = repository;
        }

        [HttpGet("name/{name}")]
        public async Task<ActionResult<List<Payee>>> GetPayeeBySupplierNameAsync(string name)
        {
            var payee = await _repository.GetPayeesByNameAsync(name);
            if (payee == null)
            {
                return NotFound();
            }
            return Ok(payee);
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<Payee>>> GetAllPayeesAsync()
        {
            var payees = await _repository.GetAllPayeesAsync();
            return Ok(payees);
        }

        [HttpPost]
        public async Task<ActionResult<Payee>> CreatePayeeAsync(Payee payee)
        {
            await _repository.AddPayeeAsync(payee);

            return CreatedAtAction(nameof(GetById), new { id = payee.PayeeId }, payee);

        }

        [HttpPut("{id}")]
        public async Task<ActionResult> UpdatePayeeAsync(int id, Payee payee)
        {
            if (id != payee.PayeeId)
            {
                return BadRequest();
            }

            await _repository.UpdatePayeeAsync(payee);
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<ActionResult> DeletePayeeAsync(int id)
        {
            var payee = await _repository.GetById(id);
            if (payee == null)
            {
                return NotFound();
            }

            await _repository.DeletePayeeAsync(id);
            return NoContent();
        }


        [HttpGet("{id}")]
        public async Task<ActionResult<Payee>> GetById(int id)
        {
            var payee = await _repository.GetById(id);

            if (payee == null)
                return NotFound();

            return Ok(payee);
        }


    }
}
