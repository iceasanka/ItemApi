using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;
using Serilog;

namespace ItemApi.Controllers
{
    // Customers for quotations and invoices. Docs/StockSystem.md §6.11.
    [Route("api/[controller]")]
    [ApiController]
    public class CustomerController : ControllerBase
    {
        private readonly ICustomerRepository _repository;

        public CustomerController(ICustomerRepository repository)
        {
            _repository = repository;
        }

        // GET: api/Customer?text=abc&top=50 — active customers, by name (text matches name or phone)
        [HttpGet]
        public async Task<IActionResult> Search([FromQuery] string? text, [FromQuery] int top = 50)
        {
            if (top is < 1 or > 500)
                return BadRequest(new { message = "Top must be between 1 and 500." });
            return await Run(async () => Ok(await _repository.SearchAsync(text, top)));
        }

        // GET: api/Customer/5
        [HttpGet("{customerId:int}")]
        public async Task<IActionResult> Get(int customerId)
        {
            return await Run(async () =>
            {
                var c = await _repository.GetByIdAsync(customerId);
                return c == null ? NotFound(new { message = "Customer not found." }) : Ok(c);
            });
        }

        // POST: api/Customer { name, address, phone, email, userId }
        [HttpPost]
        public async Task<IActionResult> Add([FromBody] Customer customer)
        {
            if (customer == null) return BadRequest(new { message = "Customer is required." });
            return await Run(async () => Ok(new { message = "Customer saved.", data = await _repository.AddAsync(customer) }));
        }

        // PUT: api/Customer/5 { name, address, phone, email, userId } — documents already made keep the old details
        [HttpPut("{customerId:int}")]
        public async Task<IActionResult> Update(int customerId, [FromBody] Customer customer)
        {
            if (customer == null) return BadRequest(new { message = "Customer is required." });
            return await Run(async () =>
                Ok(new { message = "Customer saved.", data = await _repository.UpdateAsync(customerId, customer) }));
        }

        // DELETE: api/Customer/5?userId=3 — Status 0; old documents are not changed
        [HttpDelete("{customerId:int}")]
        public async Task<IActionResult> Delete(int customerId, [FromQuery] int? userId)
        {
            return await Run(async () =>
            {
                await _repository.DeleteAsync(customerId, userId);
                return Ok(new { message = "Customer deleted." });
            });
        }

        private async Task<IActionResult> Run(Func<Task<IActionResult>> action)
        {
            try
            {
                return await action();
            }
            catch (SalesDocException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (KeyNotFoundException)
            {
                return NotFound(new { message = "Customer not found." });
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
