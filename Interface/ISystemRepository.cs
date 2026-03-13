namespace ItemApi.Interface
{
    public interface ISystemRepository
    {
        Task<string> GenerateNextGrnNoAsync(string locaCode);
    }
}
