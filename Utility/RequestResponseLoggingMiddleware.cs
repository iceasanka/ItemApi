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

            Log.Information("Request Start-----------------------------------------------------");
            // Log Request
            var request = await FormatRequest(context.Request);
            Log.Information("Incoming Request: {Request}", request);

            //// Copy a pointer to the original response body stream
            //var originalBodyStream = context.Response.Body;

            //// Create a new memory stream...
            //using (var responseBody = new MemoryStream())
            //{
            //    // ...and use that for the temporary response body
            //    context.Response.Body = responseBody;

            //    // Continue down the Middleware pipeline, eventually returning to this class
            //    await _next(context);

            //    // Log Response
            //    var response = await FormatResponse(context.Response);
            //    Log.Information("Outgoing Response: {Response}", response);

            //    // Copy the contents of the new memory stream (which contains the response) to the original stream
            //    await responseBody.CopyToAsync(originalBodyStream);
            //}

            await _next(context);

            Log.Information("Request End-----------------------------------------------------");
        }

        private async Task<string> FormatRequest(HttpRequest request)
        {
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
