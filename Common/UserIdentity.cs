using System.Security.Claims;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ItemApi.Common
{
    // The back office pages send "userId" from localStorage, which holds the LOGIN NAME ("ice"), not the number.
    // These requests' UserId therefore takes a number, a number in a string, or a name (→ null) instead of failing
    // with 400; the real user comes from the sign-in token (CurrentUserId).
    public class LenientUserIdConverter : JsonConverter<int?>
    {
        public override int? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            switch (reader.TokenType)
            {
                case JsonTokenType.Number:
                    return reader.TryGetInt32(out var n) ? n : null;
                case JsonTokenType.String:
                    return int.TryParse(reader.GetString(), out var s) ? s : null;
                case JsonTokenType.Null:
                    return null;
                default:
                    reader.Skip();
                    return null;
            }
        }

        public override void Write(Utf8JsonWriter writer, int? value, JsonSerializerOptions options)
        {
            if (value.HasValue) writer.WriteNumberValue(value.Value);
            else writer.WriteNullValue();
        }
    }

    public static class UserIdentity
    {
        // the signed-in user (token claim NameIdentifier = z_tb_User.UserId), else what the page sent
        public static int? CurrentUserId(this ClaimsPrincipal user, int? sent = null) =>
            int.TryParse(user?.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var id) ? id : sent;

        // a userId from the query string / form: a number, else (a login name) null
        public static int? ParseUserId(string? sent) => int.TryParse(sent, out var id) ? id : null;
    }
}
