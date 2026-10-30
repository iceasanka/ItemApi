namespace ItemApi.Interface
{
    public interface ISystemRepository
    {
        Task<string> GenerateNextGrnNoAsync(string locaCode);

        Task<string> UpdateNextGrnNoAsync(string locaCode);

        // the number a new GRN is saved with (PNO moved on; numbers already used skipped)
        Task<string> TakeNextGrnNoAsync(string locaCode);

        Task<string> GenerateNextPrnNoAsync(string locaCode);

        Task<string> UpdateNextPrnNoAsync(string locaCode);
    }
}
