namespace ItemApi.Interface
{
    public interface ISystemRepository
    {
        Task<string> GenerateNextGrnNoAsync(string locaCode);

        Task<string> UpdateNextGrnNoAsync(string locaCode);

        Task<string> GenerateNextPrnNoAsync(string locaCode);

        Task<string> UpdateNextPrnNoAsync(string locaCode);
    }
}
