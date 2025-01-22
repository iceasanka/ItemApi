using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Models
{

    public class ReturnItem
    {
        [Key]
        public int Id { get; set; }
        public string Item_Code { get; set; }
        public string Ref_Code { get; set; }
        public string Barcode { get; set; }
        public string Descrip { get; set; }
        public string Supp_Code { get; set; }

        [NotMapped]
        public string? Supp_Name { get; set; }
        public int? Status { get; set; }
        public string StatusText {
            get
            {
                return Status switch
                {
                    1 => "Added",
                    2 => "Returned",
                    3 => "PRN-Done",
                    _ => "Unknown" // Default case for null or other values
                };
            }
        }
        public DateOnly? Date { get; set; }
        public decimal Cost_Price { get; set; }
        public decimal ERet_Price { get; set; }

        public double Qty { get; set; }

        public decimal GrossAmount { get {
                return Cost_Price * Convert.ToDecimal(Qty);
            } }
    }

}