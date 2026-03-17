namespace ItemApi.Interface
{
    public interface ISystemRepository
    {
        Task<string> GenerateNextGrnNoAsync(string locaCode);

        Task<string> UpdateNextGrnNoAsync(string locaCode);
    }
}
