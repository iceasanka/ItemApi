using ItemApi.Models;
using ItemApi.Repositories;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class FileLocationController : ControllerBase
    {
        private readonly IFileLocationRepository _repository;

        public FileLocationController(IFileLocationRepository repository)
        {
            _repository = repository;
        }

        // GET: api/FileLocation
        [HttpGet]
        public async Task<ActionResult<List<FileLocation>>> GetAll()
        {
            return await _repository.GetAllAsync();
        }

        // GET: api/FileLocation/{id}
        [HttpGet("{id}")]
        public async Task<ActionResult<FileLocation>> GetById(int id)
        {
            var file = await _repository.GetByIdAsync(id);
            if (file == null)
                return NotFound();
            return file;
        }

        // POST: api/FileLocation
        [HttpPost]
        public async Task<ActionResult> Add(FileLocation fileLocation)
        {
            await _repository.AddAsync(fileLocation);
            return CreatedAtAction(nameof(GetById), new { id = fileLocation.Id }, fileLocation);
        }

        // PUT: api/FileLocation/{id}
        [HttpPut("{id}")]
        public async Task<ActionResult> Update(int id, FileLocation fileLocation)
        {
            if (id != fileLocation.Id)
                return BadRequest();

            await _repository.UpdateAsync(fileLocation);
            return NoContent();
        }

        // DELETE: api/FileLocation/{id}
        [HttpDelete("{id}")]
        public async Task<ActionResult> Delete(int id)
        {
            await _repository.DeleteAsync(id);
            return NoContent();
        }

        // GET: api/FileLocation/search/{suppName}
        [HttpGet("search/{suppName}")]
        public async Task<ActionResult<List<FileLocation>>> SearchByName(string suppName)
        {
            return await _repository.SearchFileByNameAsync(suppName);
        }
    }
}
