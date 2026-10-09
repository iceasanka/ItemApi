using System.Globalization;
using System.Security.Cryptography;

namespace ItemApi.Common
{
    // Password hashes for z_tb_User.PasswordHash: "PBKDF2$<iterations>$<salt base64>$<hash base64>" (SHA-256).
    // The tills check the same format offline — TillService/Auth/PasswordHasher.cs is a copy of Verify; keep them alike.
    public static class PasswordHasher
    {
        private const int Iterations = 100_000;
        private const int SaltBytes = 16;
        private const int HashBytes = 32;

        public static string Hash(string password)
        {
            var salt = RandomNumberGenerator.GetBytes(SaltBytes);
            var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, HashAlgorithmName.SHA256, HashBytes);
            return $"PBKDF2${Iterations}${Convert.ToBase64String(salt)}${Convert.ToBase64String(hash)}";
        }

        public static bool Verify(string password, string? stored)
        {
            var parts = (stored ?? "").Split('$');
            if (parts.Length != 4 || parts[0] != "PBKDF2" ||
                !int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var iterations) || iterations < 1)
                return false;
            try
            {
                var salt = Convert.FromBase64String(parts[2]);
                var expected = Convert.FromBase64String(parts[3]);
                var actual = Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, expected.Length);
                return CryptographicOperations.FixedTimeEquals(actual, expected);
            }
            catch (FormatException)
            {
                return false;
            }
        }
    }
}
