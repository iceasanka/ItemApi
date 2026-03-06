using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Repositories;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class CategoryController : ControllerBase
    {

        private readonly ICategoryRepository _repository;

        public CategoryController(ICategoryRepository repository)
        {
            _repository = repository;
        }

        [HttpGet]
        public async Task<IActionResult> GetAll()
        {
            var categories = await _repository.GetAllAsync();
            return Ok(categories);
        }

        [HttpGet]
        [Route("{id}")]
        public async Task<IActionResult> GetById(int id)
        {
            var category = await _repository.GetByIdAsync(id);
            if (category == null)
                return NotFound();
            return Ok(category);
        }

        [HttpPost]
        public async Task<IActionResult> Create(Category category)
        {
            await _repository.AddAsync(category);
            return CreatedAtAction(nameof(GetById), new { id = category.CatId }, category);
        }

        [HttpPut]
        [Route("{id}")]
        public async Task<IActionResult> Update(int id, Category category)
        {
            if (id != category.CatId)
                return BadRequest();

                //var existingCategory = await _repository.GetByIdAsync(id);
                //if (existingCategory == null)
                //    return NotFound();

            await _repository.UpdateAsync(category);
            return NoContent();
        }

        [HttpDelete]
        [Route("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            var existingCategory = await _repository.GetByIdAsync(id);
            if (existingCategory == null)
                return NotFound();

            await _repository.DeleteAsync(id);
            return NoContent();
        }

        [HttpGet]
        [Route("search/{catName}")]
        public async Task<IActionResult> SearchByName(string catName)
        {
            var categories = await _repository.SearchCategoryByNameAsync(catName);
            return Ok(categories);
        }

    }
}
