using System.ComponentModel.DataAnnotations;

namespace ItemApi.Models
{
    public class ReturnMode
    {
        [Key]
        public string TypeId { get; set; }
        public string TypeName { get; set; }
    }
}
