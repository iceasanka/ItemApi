using ItemApi.Data;
using ItemApi.Models;
using ItemApi.Repositories;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;
using Serilog;
using System.Drawing.Drawing2D;
using System.Linq;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class UtilController : ControllerBase
    {
        private PrinterService printerService;

        public UtilController()
        {
           
            printerService = new PrinterService();
        }


        [HttpPost("print")]
        public async Task<ActionResult> Print([FromBody] PrintRequest data)
        {
            try
            {
                // Extract data for the Cash Table
                List<Dictionary<string, object>> cashData = data.CashTable.Rows;
                decimal cashTotal = data.CashTable.Total;

                // Extract data for the Credit Table
                List<Dictionary<string, object>> creditData = data.CreditTable.Rows;
                decimal creditTotal = data.CreditTable.Total;

                // Extract data for the Debit Table
                List<Dictionary<string, object>> debitData = data.DebitTable.Rows;
                decimal debitTotal = data.DebitTable.Total;

                // Calculate the total cash balance
                decimal totalCashBalance = data.TotalCashBalance;

                // Call the PrinterService to print the combined data
                PrinterService printerService = new PrinterService();
                printerService.PrintCombinedData(cashData, cashTotal, creditData, creditTotal, debitData, debitTotal);

                return Ok(new { message = "Print request processed successfully." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { message = "Error processing print request.", error = ex.Message });
            }
        }




    }
}
