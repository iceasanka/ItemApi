using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Repositories;
using Microsoft.AspNetCore.Mvc;
using Serilog;

namespace ItemApi.Controllers
{
    // File exports to a folder on the API server — the back office "Exports" page. First export: SCALE
    // (weighing scale item file). Docs/StockSystem.md §6.10, DBScript/05_BackOffice_Export.sql.
    [Route("api/[controller]")]
    [ApiController]
    public class ExportController : ControllerBase
    {
        private readonly IExportRepository _repository;

        public ExportController(IExportRepository repository)
        {
            _repository = repository;
        }

        // GET: api/Export — every export with its folder, file name and last export
        [HttpGet]
        public async Task<IActionResult> GetAll()
        {
            return await Run(async () => Ok(await _repository.GetSettingsAsync()));
        }

        // GET: api/Export/SCALE
        [HttpGet("{exportCode}")]
        public async Task<IActionResult> Get(string exportCode)
        {
            return await Run(async () =>
            {
                var setting = await _repository.GetSettingAsync(exportCode);
                return setting == null ? NotFound(new { message = $"Unknown export '{exportCode}'." }) : Ok(setting);
            });
        }

        // PUT: api/Export/SCALE { folderPath, fileName, nameMaxLength, userId } — the folder must exist on the server
        [HttpPut("{exportCode}")]
        public async Task<IActionResult> UpdateSetting(string exportCode, [FromBody] ExportSettingUpdate request)
        {
            if (request == null)
                return BadRequest(new { message = "Settings are required." });
            return await Run(async () =>
                Ok(new { message = "Export settings saved.", data = await _repository.UpdateSettingAsync(exportCode, request) }));
        }

        // GET: api/Export/SCALE/Preview — the lines the file would have now, what changed since the last export,
        // and the scale items that are left out (with the reason)
        [HttpGet("{exportCode}/Preview")]
        public async Task<IActionResult> Preview(string exportCode)
        {
            if (!IsScale(exportCode)) return UnknownExport(exportCode);
            return await Run(async () => Ok(await _repository.GetScalePreviewAsync()));
        }

        // POST: api/Export/SCALE/Run { userId } — writes the file to the folder
        [HttpPost("{exportCode}/Run")]
        public async Task<IActionResult> RunExport(string exportCode, [FromBody] ExportRunRequest? request)
        {
            if (!IsScale(exportCode)) return UnknownExport(exportCode);
            return await Run(async () =>
            {
                var result = await _repository.RunScaleExportAsync(request?.UserId);
                return Ok(new { message = $"{result.LineCount} items written to {result.FilePath}.", data = result });
            });
        }

        // GET: api/Export/SCALE/Download — the same file to the browser. Does NOT count as an export
        // (the "changed since last export" list stays as it is).
        [HttpGet("{exportCode}/Download")]
        public async Task<IActionResult> Download(string exportCode)
        {
            if (!IsScale(exportCode)) return UnknownExport(exportCode);
            return await Run(async () =>
            {
                var (fileName, content) = await _repository.BuildScaleFileAsync();
                return File(content, "text/plain", fileName);
            });
        }

        // GET: api/Export/SCALE/Log?top=20
        [HttpGet("{exportCode}/Log")]
        public async Task<IActionResult> GetLog(string exportCode, [FromQuery] int top = 20)
        {
            if (top is < 1 or > 200)
                return BadRequest(new { message = "Top must be between 1 and 200." });
            return await Run(async () => Ok(await _repository.GetLogAsync(exportCode, top)));
        }

        private static bool IsScale(string exportCode) =>
            string.Equals(exportCode, ExportRepository.Scale, StringComparison.OrdinalIgnoreCase);

        private NotFoundObjectResult UnknownExport(string exportCode) =>
            NotFound(new { message = $"Unknown export '{exportCode}'." });

        private async Task<IActionResult> Run(Func<Task<IActionResult>> action)
        {
            try
            {
                return await action();
            }
            catch (ExportException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
            catch (KeyNotFoundException)
            {
                return NotFound(new { message = "Unknown export. Run DBScript/05_BackOffice_Export.sql." });
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                return StatusCode(500, new { message = "Internal Server Error", error = ex.Message });
            }
        }
    }
}
