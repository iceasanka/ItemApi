using ItemApi.Interface;
using ItemApi.Models;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    // Back office Payments & Cash > Cheque Planner (DBScript/28_BackOffice_ChequePlanner.sql, U048). From the database
    // only - the Google sheet update of the Cheque Writer is a separate process and is not touched here.
    [ApiController]
    [Route("api/[controller]")]
    public class ChequePlannerController : ControllerBase
    {
        private readonly IChequePlannerRepository _repo;

        public ChequePlannerController(IChequePlannerRepository repo) => _repo = repo;

        // GET api/ChequePlanner?from=2026-11-01&to=2027-01-05 -> { today, config, days, cheques }
        [HttpGet]
        public Task<IActionResult> Get([FromQuery] DateTime from, [FromQuery] DateTime to) =>
            Run(async () => (object)await _repo.GetPlanAsync(from, to));

        // PUT api/ChequePlanner/config { avgCash, avgCard, keepMin, bankBalance, todayNotBanked, overdueDays }
        [HttpPut("config")]
        public Task<IActionResult> SaveConfig([FromBody] ChequePlanConfigSave config) =>
            Run(async () => { await _repo.SaveConfigAsync(config); return new { ok = true }; });

        // PUT api/ChequePlanner/day/2026-11-20 { expectedCash, expectedCard, note } - all empty = back to the average
        [HttpPut("day/{date}")]
        public Task<IActionResult> SaveDay(DateTime date, [FromBody] ChequePlanDaySave day) =>
            Run(async () => { await _repo.SaveDayAsync(date, day); return new { ok = true }; });

        // POST api/ChequePlanner/cheque { date, supplierName, suppId, amount, note } -> { planId }
        [HttpPost("cheque")]
        public Task<IActionResult> AddCheque([FromBody] ChequePlanChequeSave cheque) =>
            Run(async () => new { planId = await _repo.AddChequeAsync(cheque) });

        [HttpPut("cheque/{id:int}")]
        public Task<IActionResult> UpdateCheque(int id, [FromBody] ChequePlanChequeSave cheque) =>
            Run(async () => { await _repo.UpdateChequeAsync(id, cheque); return new { ok = true }; });

        [HttpDelete("cheque/{id:int}")]
        public Task<IActionResult> RemoveCheque(int id) =>
            Run(async () => { await _repo.RemoveChequeAsync(id); return new { ok = true }; });

        private async Task<IActionResult> Run(Func<Task<object>> work)
        {
            try
            {
                return Ok(await work());
            }
            catch (ChequePlanException ex)
            {
                return StatusCode(ex.StatusCode, new { message = ex.Message });
            }
        }
    }
}
