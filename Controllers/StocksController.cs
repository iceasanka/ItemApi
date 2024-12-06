using ItemApi.Data;
using ItemApi.Models;
using ItemApi.Repositories;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;
using Serilog;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class StocksController : ControllerBase
    {
        private readonly StockContext _context;
        private readonly IStockRepository _stockRepository;

        private readonly StockService _stockService;

        public StocksController(StockContext context, IStockRepository stockRepository, StockService stockService)
        {
            _context = context;
            _stockRepository = stockRepository;

            _stockService = stockService;
        }


        [HttpGet("GetStock")]
        public async Task<ActionResult<StockCountResult>> GetStock(string itemcode)
        {

            try
            {
                var item = await _stockRepository.GetStockByItemcodeAsync(itemcode);

                if (item == null)
                {
                    return NotFound();
                }

                return Ok(item);
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw;
            }
        }



        [HttpPost("UpdateStock")]
        public async Task<IActionResult> UpdateStock([FromBody] StockUpdateRequest request)
        {
            try
            {

                int _serial = await _stockService.GetOpbByLocaCode(request.Item.Loca_Code);

                if (_serial > 0)
                {

                    Random random = new Random();
                    int randomNumber = random.Next(1000, 10000);

                    string _serialNo = string.Format("{0}-EASYW{1}", _serial, randomNumber);// "484-EASYW6527";
                    string _serialCode = string.Empty;
                    int _type = 1;
                    string _fromLoca = string.Empty;
                    string _toLoca = string.Empty;

                    // Check if stock exists
                    bool stockExists = await _stockService.UpdateStockIfExistsAsync(
                         request.Item.Loca_Code, request.Item.Item_Code, _serialCode, request.Stock, _type, _fromLoca,
                         _toLoca, request.Id, _serialNo
                    );

                    if (stockExists)
                    {
                        return BadRequest("Can't update: stock already exists.");
                    }

                    var updateStockParams = new UpdateStockParams
                    {
                        SerialNo = _serialNo,
                        Id = request.Id,
                        ItemCode = request.Item.Item_Code,
                        SuppCode = request.Item.Supp_Code,
                        ItemDescrip = request.Item.Descrip,
                        Scale = request.Item.PackScale,
                        PackSize = request.Item.Pack_Size,
                        CostPrice = request.Item.Cost_Price,
                        RetPrice = request.Item.ERet_Price,//
                        Stock = request.Stock,
                        CostValue = request.Item.Cost_Price * request.Stock,
                        RetValue = request.Item.ERet_Price * request.Stock,
                        Remark = string.Empty,
                        Updation = 1,
                        RemarkExp = string.Empty,
                        BarcodeSrl = string.Empty,
                        CsCode = string.Empty,
                        CsName = string.Empty,
                        LocaCode = request.Item.Loca_Code
                    };


                    // Proceed with updating the stock
                    await _stockRepository.UpdateStockAsync(updateStockParams);

                    // Create the DTO for CommitStockAdjustment
                    var commitStockAdjustmentParams = new CommitStockAdjustmentParams
                    {
                        SerialNo = _serialNo,
                        RefNo = "",
                        LocaCode = request.Item.Loca_Code,
                        IDate = DateTime.Now.ToString("yyyy-MM-dd 00:00:00:000"), // Adjust as needed
                        CostValue = request.Item.Cost_Price * request.Stock,
                        RetValue = request.Item.ERet_Price * request.Stock,
                        Id = request.Id,
                        UserName = "EASYWAY", // Adjust as needed
                        Status = 1,
                        Type = "",
                        IsExp = 0
                    };

                    // Commit the stock adjustment
                    await _stockRepository.CommitStockAdjustmentAsync(commitStockAdjustmentParams);

                    return Ok();

                }
                return BadRequest("Can't update: serial error.");
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw;
            }
        }


    }
}
