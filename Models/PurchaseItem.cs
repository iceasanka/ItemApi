using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace ItemApi.Models
{

    public class PurchaseItem
    {
        public int Id { get; set; }
        public string BarCode { get; set; }
        public string ItemCode { get; set; }
        public string ItemRefCode { get; set; }
        public string GrnReference { get; set; }
       
        public string Descrip { get; set; }
        public decimal CostPrice { get; set; }
        public decimal ERetPrice { get; set; }
        public double Qty { get; set; }
        public decimal Discount { get; set; }
        public decimal Amount { get; set; }
        public decimal GrossAmount { get; set; }
        public DateTime Date { get; set; }
        public int Status { get; set; }

        public decimal ItemCostPrice { get; set; }
        public decimal ItemERetPrice { get; set; }
    }

}