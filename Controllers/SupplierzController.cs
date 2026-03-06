using ItemApi.Models;
using ItemApi.Repositories;
using Microsoft.AspNetCore.Mvc;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class SupplierzController : ControllerBase
    {
        private readonly ISupplierzRepository _repository;

        public SupplierzController(ISupplierzRepository repository)
        {
            _repository = repository;
        }

        // GET: api/Supplierz
        [HttpGet]
        public async Task<ActionResult<List<SupplierEntity>>> GetAll()
        {
            return await _repository.GetAllAsync();
        }

        // GET: api/Supplierz/{id}
        [HttpGet("{id}")]
        public async Task<ActionResult<SupplierEntity>> GetById(int id)
        {
            var supplier = await _repository.GetByIdAsync(id);
            if (supplier == null)
                return NotFound();
            return supplier;
        }

        // POST: api/Supplierz
        [HttpPost]
        public async Task<ActionResult> Add(SupplierEntity supplier)
        {
            await _repository.AddAsync(supplier);
            return CreatedAtAction(nameof(GetById), new { id = supplier.SuppId }, supplier);
        }

        // PUT: api/Supplierz/{id}
        [HttpPut("{id}")]
        public async Task<ActionResult> Update(int id, SupplierEntity supplier)
        {
            if (id != supplier.SuppId)
                return BadRequest();

            await _repository.UpdateAsync(supplier);
            return NoContent();
        }

        // DELETE: api/Supplierz/{id}
        [HttpDelete("{id}")]
        public async Task<ActionResult> Delete(int id)
        {
            await _repository.DeleteAsync(id);
            return NoContent();
        }

        // GET: api/Supplierz/search/{suppName}
        [HttpGet("search/{suppName}")]
        public async Task<ActionResult<List<SupplierEntity>>> SearchByName(string suppName)
        {
            return await _repository.SearchSupplierByNameAsync(suppName);
        }
    }
}
