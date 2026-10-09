namespace ItemApi.Utility
{
    using Microsoft.AspNetCore.Http;
    using Serilog;
    using System.IO;
    using System.Text;
    using System.Threading.Tasks;

    public class RequestResponseLoggingMiddleware
    {
        private readonly RequestDelegate _next;

        public RequestResponseLoggingMiddleware(RequestDelegate next)
        {
            _next = next;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            if (!context.Items.ContainsKey("RequestLogged"))
            {
                context.Items["RequestLogged"] = true;
                var request = await FormatRequest(context.Request);
                Log.Information("Incoming Request: {Request}", request);

                await _next(context);
            }
        }

        private async Task<string> FormatRequest(HttpRequest request)
        {
            // passwords (sign-in, users) and tokens (SignalR sends ?access_token=) never go to the log
            if (request.Path.StartsWithSegments("/api/Auth", StringComparison.OrdinalIgnoreCase) ||
                request.Path.StartsWithSegments("/api/Users", StringComparison.OrdinalIgnoreCase))
                return $"{request.Scheme} {request.Host}{request.Path} {request.QueryString} [body not logged]";
            if (request.Path.StartsWithSegments("/hubs", StringComparison.OrdinalIgnoreCase))
                return $"{request.Scheme} {request.Host}{request.Path} [query not logged]";

            request.EnableBuffering();
            var body = request.Body;

            // Leave the body open so the next middleware can read it
            var buffer = new byte[Convert.ToInt32(request.ContentLength)];
            await request.Body.ReadAsync(buffer, 0, buffer.Length);
            var bodyAsText = Encoding.UTF8.GetString(buffer);
            request.Body.Position = 0;

            return $"{request.Scheme} {request.Host}{request.Path} {request.QueryString} {bodyAsText}";
        }

        private async Task<string> FormatResponse(HttpResponse response)
        {
            response.Body.Seek(0, SeekOrigin.Begin);
            var text = await new StreamReader(response.Body).ReadToEndAsync();
            response.Body.Seek(0, SeekOrigin.Begin);

            return $"{response.StatusCode}: {text}";
        }
    }

}
