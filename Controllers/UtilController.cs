
using BarTender;
using ItemApi.Data;
using ItemApi.Models;
using ItemApi.Repositories;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using Serilog;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Text;
using System.Xml.Linq;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class UtilController : ControllerBase
    {
        private PrinterService printerService;
        private readonly AppSettings _appSettings;
        public UtilController(IOptions<AppSettings> appSettings)
        {
            _appSettings = appSettings.Value;
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

        [HttpPost("printbarcode")]
        public async Task<ActionResult> HandleSubmit([FromBody] PrintBarcodeRequest request)
        {
            try
            {
                Application btApp = new Application();

                try
                {
                  

                    ItemWithDetails itemDetails = request.ItemDetails;
                    var labelCount = request.LabelCount;
                    DateTime expireDate = DateTime.Parse(request.expireDate);
                    DateTime mrDate = DateTime.Parse(request.mrDate);

                    string templatePath = _appSettings.TemplatePath;
                    string printerName = "ZDesigner ZP888 203DPI";
                    string dataTextFilePath = _appSettings.DataTextFilePath;

                    string columnNames = "Item_Code,Barcode,Descrip,ERet_Price,expireDate,mrDate";
                    string data = $"{itemDetails.Item_Code},{itemDetails.Barcode},{itemDetails.Descrip},{itemDetails.ERet_Price},{expireDate.ToString("dd-MM-yyyy")},{mrDate.ToString("dd-MM-yyyy")}";


                    if (System.IO.File.Exists(dataTextFilePath))
                        System.IO.File.WriteAllText(dataTextFilePath, string.Empty);

                    System.IO.File.WriteAllText(dataTextFilePath, $"{columnNames}\n{data}");


                    btApp.Visible = false;
                    Format btFormat = btApp.Formats.Open(templatePath, false, printerName);
                    //btFormat.SetNamedSubStringValue("Items_Data", dataTextFilePath);
                    btFormat.PrintSetup.IdenticalCopiesOfLabel = labelCount;

                    btFormat.PrintOut(true, true);

                    btFormat.Close(BtSaveOptions.btDoNotSaveChanges);
                    btApp.Quit(BtSaveOptions.btDoNotSaveChanges);

                    return Ok(new { message = "Print request processed successfully." });

                }
                catch (Exception ex)
                {
                    return BadRequest(new { message = "Error processing print request.", error = ex.Message });
                }
                finally
                {
                    btApp.Quit(BtSaveOptions.btDoNotSaveChanges);
                }

            }
            catch (Exception ex)
            {
                return BadRequest(new { message = "Error creating BarTender application.", error = ex.Message });
            }

        }


        //



        public class PrintBarcodeRequest
        {
            public ItemWithDetails ItemDetails { get; set; }
            public int LabelCount { get; set; }

            public string expireDate { get; set; }
            public string mrDate { get; set; }
        }



    }
}
