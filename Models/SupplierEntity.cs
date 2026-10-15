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
        // NULL-able columns: rows made outside the Supplier page (e.g. U008 payees) can have NULL here
        public string? Phone { get; set; }
        public string? Phone2 { get; set; }
        public string? AccNo { get; set; }
        public string? Bank { get; set; }
        public decimal DRate { get; set; }
        // the name printed on cheques (null = SuppName) — z_tb_Payee is merged in here (U007)
        public string? PayeeName { get; set; }
        // cheque period: a bill is due its date + CreditDays
        public int? CreditDays { get; set; }
        public string? UserId { get; set; }
        public DateTime CDate { get; set; }
        public DateTime UDate { get; set; }
    }
}
