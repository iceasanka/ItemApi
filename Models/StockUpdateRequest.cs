// ItemApi/Models/StockUpdateRequest.cs
using System;

namespace ItemApi.Models
{
    public class StockUpdateRequest
    {

    public string Id { get; set; }
    public decimal Stock { get; set; }
    public ItemWithDetails Item { get; set; }
    }
}
