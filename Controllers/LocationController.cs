using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Repositories;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class LocationController : ControllerBase
    {

        private readonly ILocationRepository _repository;

        public LocationController(ILocationRepository repository)
        {
            _repository = repository;
        }

        [HttpGet]
        public async Task<IActionResult> GetAll()
        {
            var locations = await _repository.GetAllAsync();
            return Ok(locations);
        }

        [HttpGet]
        [Route("{id}")]
        public async Task<IActionResult> GetById(int id)
        {
            var location = await _repository.GetByIdAsync(id);
            if (location == null)
                return NotFound();
            return Ok(location);
        }

        [HttpPost]
        public async Task<IActionResult> Create(Location location)
        {
            await _repository.AddAsync(location);
            return CreatedAtAction(nameof(GetById), new { id = location.LocationId }, location);
        }

        [HttpPut]
        [Route("{id}")]
        public async Task<IActionResult> Update(int id, Location location)
        {
            if (id != location.LocationId)
                return BadRequest();

            var existingLocation = await _repository.GetByIdAsync(id);
            if (existingLocation == null)
                return NotFound();

            await _repository.UpdateAsync(location);
            return NoContent();
        }

        [HttpDelete]
        [Route("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            var existingLocation = await _repository.GetByIdAsync(id);
            if (existingLocation == null)
                return NotFound();

            await _repository.DeleteAsync(id);
            return NoContent();
        }

    }
}
