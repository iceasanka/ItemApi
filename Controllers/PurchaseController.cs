using ItemApi.Data;
using ItemApi.Interface;
using ItemApi.Models;
using ItemApi.Repositories;
using ItemApi.Service;
using Microsoft.AspNetCore.Mvc;
using Serilog;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class PurchaseController : ControllerBase
    {
        private readonly IPurchaseRepository _repository;
        private readonly IItemRepository _itemRepository;
        private PrinterService printerService;
        private readonly IGrnTempRepository _grnTempRepository;

        public PurchaseController(IPurchaseRepository repository, IItemRepository itemRepository, IGrnTempRepository grnTempRepository)
        {
            _repository = repository;
            _itemRepository = itemRepository;
            _grnTempRepository = grnTempRepository;
            printerService = new PrinterService();
        }

        [HttpGet("GetSerialNo")]
        public async Task<IActionResult> GetGrnTempById()
        {
            int _serial = await _repository.GetPNOByLocaCodeAsync("01");
            string _serialNo = string.Empty;

            if (_serial > 0)
            {

                Random random = new Random();
                int randomNumber = random.Next(1000, 10000);

                _serialNo = string.Format("{0}-EASYW{1}", _serial, randomNumber);
            }

            return Ok(new { message = "GrnTemp added successfully.", data = _serialNo });
        }

        [HttpPost("SaveGrnItems")]
        public async Task<ActionResult> ProcessPurchaseItems([FromBody] PurchasePayload purchasePayload/*[FromBody] List<PurchaseItem> purchaseItems*/)
        {
          //  return StatusCode(500, "An error occurred while processing items.");
            var summary = purchasePayload.Summary;
            var purchaseItems = purchasePayload.Items;

            if (purchaseItems == null || purchaseItems.Count == 0)
                return BadRequest("No items provided for processing.");

            try
            {

                foreach (var item in purchaseItems)
                {
                    var itemWithDetails = await _itemRepository.GetItemWithDetailsByItemCodeAsync(item.ItemCode);

                    if (itemWithDetails != null)
                    {
                        PurchaseUpdateRequest request = new PurchaseUpdateRequest();
                        request.UpdateStatus = 1;
                        request.SerialNo = summary.SeriaNo;
                        request.SuppCode = itemWithDetails.Supp_Code;
                        request.ItemCode = itemWithDetails.Item_Code;
                        request.Descrip = itemWithDetails.Descrip;
                        request.LocaCode = itemWithDetails.Loca_Code;
                        request.PackScale = itemWithDetails.PackScale;
                        request.Unit = itemWithDetails.PUnit;
                        request.Cost = item.CostPrice;
                        request.Rate = item.ERetPrice;
                        request.ERate = item.ERetPrice;
                        request.Qty = item.Qty;
                        request.DiscP = item.Discount.ToString();
                        request.Discount = item.Discount;
                        request.Amount = item.Amount;
                        request.Id = "PCH";
                        request.UserName = "EASYWAY";
                        request.PackSize = itemWithDetails.Pack_Size;
                        request.Remark = "ice";
                        request.BarcodeSrl = itemWithDetails.Item_Code;
                        request.CSCode = "";
                        request.CSName = "";
                        request.RowNo = 0;
                        request.Nbt = 0;
                        request.Tax = 0;
                        request.ManufactureDate = "";

                        await _repository.UpdatePurchaseItemToTempPurchaseAsync(request);
                    }
                }

                var commitPurchaseItems = new CommitPurchaseItems
                {
                    SerialNo = summary.SeriaNo,
                    RefNo = "icePN",
                    RefNo2 = summary.notes,
                    PNDate = DateTime.Now.ToString("yyyy-MM-dd 00:00:00:000"),
                    SuppCode = summary.SuppCode,
                    SuppName = summary.SuppName,
                    PODNo = "",
                    PType = 1,
                    PMode = 1,
                    GrossAmount = Math.Round(purchaseItems.Sum(x => x.GrossAmount), 2),
                    TotDiscount = Math.Round(purchaseItems.Sum(x => x.Discount), 2),
                    Tax = 0,
                    Advance = 0,
                    AdvPMode = 0,
                    SubTotDiscount = Math.Round(summary.SubTotDiscount, 2),
                    NetAmount = Math.Round(purchaseItems.Sum(x => x.Amount) - summary.SubTotDiscount, 2),
                    UserName = "EASYWAY",
                    LocaCode = "01",
                    Status = 1,
                    Returns = 0,
                    UpdPrice = 1,
                    RefAmount = 0,
                    IsExp = false,
                    Disc = Math.Round(summary.SubTotDiscount,2).ToString(),
                    Nbt = 0,
                    RoundingDiff = 0
                };


                await _repository.CommitPurchaseAsync(commitPurchaseItems);

                foreach (var item in purchaseItems)
                {
                    await _grnTempRepository.UpdateGrnTempStatusAsync(item.Id, 3);
                }

                // printerService.PrintProcessedData(purchaseItems);

                return Ok(new { message = "Items processed successfully.", success = true });
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");

                return StatusCode(500, "An error occurred while processing items.");
            }
        }

        /* [HttpPost("print")]
         public async Task<ActionResult> Print([FromBody] List<PurchaseItem> purchaseItems)
         {
             try
             {
                 printerService.PrintProcessedData(purchaseItems);

                 return Ok("Items printed successfully.");
             }
             catch (Exception ex)
             {
                 Log.Error($"Error: {ex}");
                 return StatusCode(500, "An error occurred while printing items.");
             }
         }*/



    }

}
