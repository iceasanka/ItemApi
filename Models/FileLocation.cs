namespace ItemApi.Models
{
    public class FileLocation
    {
        public int Id { get; set; }
        public string Supp_Name { get; set; }
        public int Row_No { get; set; }
        public int Clm_No { get; set; }
        public string? Note { get; set; }
    }
}
