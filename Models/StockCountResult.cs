using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Models
{
    
[Table("tb_Stock")]
    public class StockCountResult
    {
        public decimal Stock { get; set; }
    }
}