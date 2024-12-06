using System.ComponentModel.DataAnnotations;

namespace ItemApi.Models
{
    public class Supplier
    {
        [Key]
        public string Supp_Code { get; set; }
        public string Supp_Name { get; set; }

    }
}
