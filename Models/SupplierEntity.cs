// Models/SupplierDto.cs
using System;
using System.ComponentModel.DataAnnotations;

namespace ItemApi.Models
{
    public class SupplierEntity
    {
        [Key]
        public int SuppId { get; set; }
        public string SuppCode { get; set; }
        public string SuppName { get; set; }
        public int Status { get; set; }
        public string Phone { get; set; }
        public string Phone2 { get; set; }
        public string AccNo { get; set; }
        public string Bank { get; set; }
        public decimal DRate { get; set; }
        public string UserId { get; set; }
        public DateTime CDate { get; set; }
        public DateTime UDate { get; set; }
    }
}
