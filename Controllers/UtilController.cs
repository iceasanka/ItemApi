
using BarTender;
using ItemApi.Models;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using System.Text.Json;
using System.Text;
using ItemApi.Interface;


namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class UtilController : ControllerBase
    {
        private PrinterService printerService;
        private readonly IChequeCreateRepository _repository;
        private readonly AppSettings _appSettings;
        public UtilController(IOptions<AppSettings> appSettings, IChequeCreateRepository repository)
        {
            _appSettings = appSettings.Value;
            printerService = new PrinterService();
            _repository = repository;
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
                ItemWithDetails itemDetails = request.ItemDetails;

                PrintBarCode barPrint = new PrintBarCode();
                barPrint.Item_Code = itemDetails.Item_Code;
                barPrint.Barcode = itemDetails.Barcode;
                barPrint.Descrip = itemDetails.Descrip;
                barPrint.ERet_Price = itemDetails.ERet_Price.ToString("0.00");
                barPrint.expireDate = DateTime.Parse(request.expireDate).ToString("dd-MM-yyyy");
                barPrint.mrDate = DateTime.Parse(request.mrDate).ToString("dd-MM-yyyy");
                barPrint.printerName = _appSettings.PrinterZebra;
                barPrint.printTemplatePath = _appSettings.StickerExpireDatePrint;
                barPrint.lblCount = request.LabelCount; 

                await PrintLocalAgent(PrintJobType.BarCode, barPrint);
                return Ok(new { message = "BarCode Print request processed successfully." });
            }
            catch (Exception ex)
            {

                return BadRequest(new { message = "Error creating BarTender application.", error = ex.Message });
            }

        }

        public async Task<ActionResult> PrintLocalAgent<T>(PrintJobType type, T payload)
        {
            using var client = new HttpClient();

            var request = new
            {
                Type = type,
                Data = payload
            };

            var json = JsonSerializer.Serialize(request);
            var content = new StringContent(json, Encoding.UTF8, "application/json");

            var response = await client.PostAsync(
                "http://localhost:9001/print/",
                content
            );

            if (!response.IsSuccessStatusCode)
                return StatusCode(500, "Print agent failed");

            return Ok(new { message = "Print request sent." });
        }



        [HttpPost("printprice")]
        public async Task<ActionResult> PrintPrice([FromBody] PrintItem item)
        {
            try
            {
                item.printerName = _appSettings.PrinterName;
                item.printTemplatePath = _appSettings.PricePrintTemplatePath;
                item.printType = 1; // Price Print
                item.printLanguage = item.printLanguage;
                await PrintLocalAgent(PrintJobType.ItemLabel, item);
                return Ok(new { message = "Print request processed successfully." });
            }
            catch (Exception ex)
            {

                return BadRequest(new { message = "Error creating BarTender application.", error = ex.Message });
            }
        }

        [HttpPost("printDiscountPrice")]
        public async Task<ActionResult> PrintDiscountPrice([FromBody] PrintItem item)
        {
            try
            {
                item.printerName = _appSettings.PrinterName;

                if (!string.IsNullOrEmpty(item.tax3) && item.tax3 != "0")
                    item.printTemplatePath = _appSettings.DiscountPrintTemplatePath;
                else if (!string.IsNullOrEmpty(item.tax2) && item.tax2 != "0")
                    item.printTemplatePath = _appSettings.DiscountPercentagePrintTemplatePath;
                else
                    item.printTemplatePath = string.Empty;

                item.printType = 2; // Discount Print
                item.printLanguage = item.printLanguage;
                await PrintLocalAgent(PrintJobType.ItemLabel, item);
                return Ok(new { message = "Print request processed successfully." });
            }
            catch (Exception ex)
            {

                return BadRequest(new { message = "Error creating BarTender application.", error = ex.Message });
            }
        }


        [HttpPost("printitempricelandscape")]
        public async Task<ActionResult> PrintItemPriceLandscape([FromBody] PrintItem item)
        {
            try
            {
                item.printerName = _appSettings.PrinterName;
                item.printTemplatePath = _appSettings.LandScapePricePrintTemplatePath;
                item.printType = 3; // landscape Print
                item.printLanguage = item.printLanguage;
                await PrintLocalAgent(PrintJobType.ItemLabel, item);
                return Ok(new { message = "Print request processed successfully." });
            }
            catch (Exception ex)
            {

                return BadRequest(new { message = "Error creating BarTender application.", error = ex.Message });
            }
        }


        [HttpPost("printCheque")]
        public async Task<ActionResult> PrintCheque([FromBody] Cheque cheque)
        {
            try
            {
                cheque.printerName = _appSettings.PrinterHP;
                cheque.printTemplatePath = _appSettings.ChequePrintTemplatePath;
                cheque.printType = 4; // Cheque Print

                //Asanka
                await PrintLocalAgent(PrintJobType.Cheque, cheque);

                ChequeCreate chequeCreate = new ChequeCreate();
                chequeCreate.Amount  = cheque.amount;
                chequeCreate.ChequeDate = cheque.chequeDate;
                chequeCreate.PayeeId    = cheque.payeeId;
                chequeCreate.SupplierName= cheque.supplierName;
                chequeCreate.ChequeNumber = cheque.chequeNumber;
                chequeCreate.IsSync = 0;

                //Asanka : Need to remove
                //return Ok(new { message = "Print request processed successfully." });


                await _repository.AddChequeAsync(chequeCreate);


                bool isSyncSuccess = false;

                try
                {
                    await _repository.SyncPrintedChequeAsync(chequeCreate);
                    isSyncSuccess = true;
                }
                catch (Exception syncEx)
                {
                    return BadRequest(new { message = "Error Sync Printed Cheque.", error = syncEx.Message });
                }

                if (isSyncSuccess)
                {
                    chequeCreate.IsSync = 1;
                    await _repository.UpdateChequeAsync(chequeCreate);
                }
               //Asanka message

                return Ok(new { message = "Print request processed successfully." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { message = "Error creating BarTender application.", error = ex.Message });
            }
        }


        [HttpPost("printCashierSettlement")]
        public async Task<ActionResult> PrintCashierSettlement([FromBody] CashierSettlement settlement)
        {
            try
            {
                settlement.printerName = _appSettings.PrinterName;
                settlement.printTemplatePath = _appSettings.SettlementTemplatePath;

                await PrintLocalAgent(PrintJobType.Settlement, settlement);
                return Ok(new { message = "Settlement Print request processed successfully." });
            }
            catch (Exception ex)
            {

                return BadRequest(new { message = "Error creating BarTender application.", error = ex.Message });
            }
        }




    }
}
