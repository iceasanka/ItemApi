namespace ItemApi.Models
{
    public class TableData
    {
        public List<Dictionary<string, object>> Rows { get; set; } = new();
        public decimal Total { get; set; }
    }
}
