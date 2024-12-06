using Microsoft.AspNetCore.Mvc;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using ItemApi.Data;
using ItemApi.Models;
using ItemApi.Repositories;
using ItemApi.Service;
using Azure.Core;
using Microsoft.Extensions.Hosting;
using static System.Runtime.InteropServices.JavaScript.JSType;
using System.Data;
using System.Xml.Linq;

namespace ItemApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class ReturnController : ControllerBase
    {
        private readonly IReturnRepository _repository;
        private readonly ReturnContext _contextReturn;
        private readonly ItemContext _contextItem;
        private readonly IItemRepository _itemRepository;
        private PrinterService printerService;

        public ReturnController(ReturnContext contextReturn, IReturnRepository repository, ItemContext contextItem, IItemRepository itemRepository)
        {
            _contextReturn = contextReturn;
            _repository = repository;

            _contextItem = contextItem;
            _itemRepository = itemRepository;
            printerService = new PrinterService();
        }

        [HttpGet]
        public async Task<ActionResult<List<ReturnItem>>> GetAllItems()
        {
            return Ok(await _repository.GetAllItemsAsync());
        }

        [HttpGet("{itemCode}")]
        public async Task<ActionResult<ReturnItem>> GetItemByCode(string itemCode)
        {
            var item = await _repository.GetItemByCodeAsync(itemCode);
            if (item == null)
                return NotFound();

            return Ok(item);
        }

        [HttpGet("GetItemsBySuppCode")]//Use
        public async Task<ActionResult<List<ReturnItem>>> GetItemsBySuppCode(string suppcode)
        {

            try
            {
                var item = await _repository.GetItemsBySuppCodeAsync(suppcode);
                if (item == null)
                    return NotFound();

                return Ok(item);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error GetItemsBySuppCode: {ex.Message}");
                return NotFound(ex.Message);
            }
        }

        [HttpPost("AddReturnItem")]//use
        public async Task<ActionResult> AddItem(ReturnItem returnItem)
        {
            await _repository.AddItemAsync(returnItem);
            return CreatedAtAction(nameof(GetItemByCode), new { itemCode = returnItem.Item_Code }, returnItem);
        }

        [HttpPut("{id}")]//use
        public async Task<ActionResult> UpdateItemById(int id, ReturnItem updatedItem)
        {
            await _repository.UpdateItemAsync(id, updatedItem);
            return NoContent();
        }

        [HttpPost("process")]//use
        public async Task<ActionResult> ProcessReturnItems([FromBody] List<ReturnItem> returnItems)
        {
            if (returnItems == null || returnItems.Count == 0)
                return BadRequest("No items provided for processing.");

            try
            {
                int _serial = await _repository.GetPRNOByLocaCodeAsync("01");

                if (_serial > 0)
                {
                    var returnModes = await _repository.GetReturnModesAsync();
                    var purchaseTypes = await _repository.GetPurchaseTypesAsync();

                    var supplier = await _repository.GetSupplierByCodeAsync(returnItems.FirstOrDefault().Supp_Code);

                    if (supplier == null)
                        return NotFound($"Supplier with code '{returnItems.FirstOrDefault().Supp_Code}' not found.");

                    if (returnItems.Any(item => item.Supp_Code != supplier.Supp_Code))
                        return BadRequest("Mismatch in supplier codes. All items must belong to the same supplier.");

                    Random random = new Random();
                    int randomNumber = random.Next(1000, 10000);

                    string _serialNo = string.Format("{0}-EASYW{1}", _serial, randomNumber);// "484-EASYW6527";

                    foreach (var item in returnItems)
                    {
                        var itemWithDetails = await _itemRepository.GetItemWithDetailsByItemCodeAsync(item.Item_Code);

                        if (itemWithDetails != null)
                        {
                            ReturnUpdateRequest request = new ReturnUpdateRequest();
                            request.UpdateStatus = 1;
                            request.SerialNo = _serialNo;
                            request.SuppCode = itemWithDetails.Supp_Code;
                            request.ItemCode = itemWithDetails.Item_Code;
                            request.Descrip = itemWithDetails.Descrip;
                            request.LocaCode = itemWithDetails.Loca_Code;
                            request.PackScale = itemWithDetails.PackScale;
                            request.Unit = itemWithDetails.PUnit;
                            request.Cost = item.Cost_Price;//100.00m;
                            request.Rate = item.ERet_Price; //150
                            request.ERate = item.ERet_Price; //150
                            request.Qty = item.Qty;//6
                            request.DiscP = "0.0000";
                            request.Discount = 0;
                            request.Amount = item.Cost_Price * Convert.ToDecimal(item.Qty);
                            request.Id = "PRN";
                            request.UserName = "EASYWAY";
                            request.PackSize = itemWithDetails.Pack_Size;
                            request.Remark = "ice";
                            request.BarcodeSrl = "";
                            request.CSCode = "";
                            request.CSName = "";
                            request.RowNo = "0";
                            request.Nbt = 0;
                            request.Tax = 0;

                            await _repository.UpdateReturnItemToTempPurchaseAsync(request);
                        }
                    }

                    //Commit the  changes 
                    var commitReturnItems = new CommitReturnItems
                    {
                        SerialNo = _serialNo,
                        RefNo = "ice123",
                        PNDate = DateTime.Parse("2024-11-25T00:00:00"),
                        SuppCode = supplier.Supp_Code, //"OTHR",
                        SuppName = supplier.Supp_Name,//"OTHER",
                        PODNo = "",
                        PType = 1,
                        PMode = 1,
                        GrossAmount = returnItems.Sum(x => x.GrossAmount),//600.00m,
                        TotDiscount = 0,
                        SubTotDiscount = 0,
                        Tax = 0,
                        Advance = 0,
                        NetAmount = returnItems.Sum(x => x.GrossAmount),//600.00m,
                        UserName = "EASYWAY",
                        LocaCode = "01",
                        Status = 1,
                        IsExp = false,
                        Nbt = 0,
                        Disc = "0.00"
                    };

                    await _repository.CommitReturnToPurchaseAsync(commitReturnItems);

                    //delete temp table 
                    var deleteTempPurchaseRequest = new DeleteTempPurchaseRequest
                    {
                        SerialNo = _serialNo,//"129-EASYW3964",
                        ID = "PRN",
                        LocaCode = "01",
                        UserName = "EASYWAY",
                        ItemCode = "",
                        Cost = 0,
                        IdNo = "0",
                        CancelAll = 1
                    };

                    await _repository.DeleteTempPurchaseAsync(deleteTempPurchaseRequest);

                }

                foreach (var item in returnItems)
                {
                    // Update the status in the database or perform other logic
                    await _repository.UpdateItemStatusAsync(item.Id, 3); // Example: Set status to 3 (processed)
                }

                
                printerService.PrintProcessedData(returnItems);

                return Ok(new { message = "Items processed successfully.", print = true });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error processing items: {ex.Message}");
                return StatusCode(500, "An error occurred while processing items.");
            }
        }

        [HttpPost("print")]//use
        public async Task<ActionResult> Print([FromBody] List<ReturnItem> returnItems)
        {
            try
            {
                printerService.PrintProcessedData(returnItems);

                return Ok("Items print successfully.");
            }
            catch (Exception ex)
            {

                // Log the error
                Console.WriteLine($"Error print items: {ex.Message}");
                return StatusCode(500, "An error occurred while print items.");
            }
        }

        [HttpDelete("{id}")]//use
        public async Task<ActionResult> DeleteItem(int id)
        {
            await _repository.DeleteItemAsync(id);
            return NoContent();
        }

        /* public async Task UpdateItemStatusAsync(int id, int newStatus)
         {
             await _repository.UpdateItemStatusAsync(id, newStatus);
            // return NoContent();
         }*/



        [HttpGet("search")]
        public async Task<ActionResult<List<ReturnItem>>> SearchItems(string description, string suppCode)
        {
            return Ok(await _repository.SearchItemsAsync(description, suppCode));
        }

        [HttpGet("groupBySuppCode")]
        public async Task<ActionResult<List<IGrouping<string, ReturnItem>>>> GroupBySuppCode()
        {
            return Ok(await _repository.GroupBySuppCodeAsync());
        }

    }
}
