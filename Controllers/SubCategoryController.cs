using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class SubCategoryController : ControllerBase
    {
        private readonly ISubCategoryRepository _repository;

        public SubCategoryController(ISubCategoryRepository repository)
        {
            _repository = repository;
        }

        // GET: api/SubCategory
        [HttpGet]
        public async Task<ActionResult<List<SubCategory>>> GetAll()
        {
            try
            {
                var subCategories = await _repository.GetAllAsync();
                return Ok(subCategories);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal server error", error = ex.Message });
            }
        }

        // GET: api/SubCategory/5
        [HttpGet("{id}")]
        public async Task<ActionResult<SubCategory>> GetById(int id)
        {
            try
            {
                var subCategory = await _repository.GetByIdAsync(id);
                if (subCategory == null)
                    return NotFound(new { message = $"SubCategory with Id {id} not found." });

                return Ok(subCategory);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal server error", error = ex.Message });
            }
        }

        // GET: api/SubCategory/code/SC001
        [HttpGet("code/{code}")]
        public async Task<ActionResult<List<SubCategory>>> GetByCode(string code)
        {
            try
            {
                var subCategory = await _repository.GetByCodeAsync(code);
                if (subCategory == null)
                    return NotFound(new { message = $"SubCategory with code '{code}' not found." });

                return Ok(subCategory);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal server error", error = ex.Message });
            }
        }

        // GET: api/SubCategory/category/3
        [HttpGet("category/{catId}")]
        public async Task<ActionResult<List<SubCategory>>> GetByCatId(int catId)
        {
            try
            {
                var subCategories = await _repository.GetByCatIdAsync(catId);
                return Ok(subCategories);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal server error", error = ex.Message });
            }
        }

        // POST: api/SubCategory
        [HttpPost]
        public async Task<ActionResult> Add([FromBody] SubCategory subCategory)
        {
            try
            {
                await _repository.AddAsync(subCategory);
                return CreatedAtAction(nameof(GetById), new { id = subCategory.SubCatId }, subCategory);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal server error", error = ex.Message });
            }
        }

        // PUT: api/SubCategory/5
        [HttpPut("{id}")]
        public async Task<ActionResult> Update(int id, [FromBody] SubCategory subCategory)
        {
            if (id != subCategory.SubCatId)
                return BadRequest(new { message = "ID mismatch." });

            try
            {
                var existing = await _repository.GetByIdAsync(id);
                if (existing == null)
                    return NotFound(new { message = $"SubCategory with Id {id} not found." });

                await _repository.UpdateAsync(subCategory);
                return NoContent();
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal server error", error = ex.Message });
            }
        }

        // DELETE: api/SubCategory/5
        [HttpDelete("{id}")]
        public async Task<ActionResult> Delete(int id)
        {
            try
            {
                var existing = await _repository.GetByIdAsync(id);
                if (existing == null)
                    return NotFound(new { message = $"SubCategory with Id {id} not found." });

                await _repository.DeleteAsync(id);
                return NoContent();
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal server error", error = ex.Message });
            }
        }
    }
}
