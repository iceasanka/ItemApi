using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace ItemApi.Controllers
{
    // Mobile app downloads for the back office "Mobile App" page. Files are copied by hand into the server folder
    // MobileApp (next to ItemApi.dll, or MobileApp:Folder in appsettings):
    //   MobileApp\*.apk or MobileApp\Android\*.apk  - the newest one is "Latest"
    //   MobileApp\iOS\*.ipa      - kept for the iPhone app (an iPhone can't install an .ipa from a browser), and/or
    //   MobileApp\iOS\link.txt   - one line: the App Store / TestFlight link shown to iPhone users
    // Open (no sign-in): a phone opens the download link / QR code from its own browser, which has no token.
    [Route("api/[controller]")]
    [ApiController]
    [AllowAnonymous]
    public class MobileAppController : ControllerBase
    {
        private static readonly Dictionary<string, (string Folder, string Pattern, string Type)> Platforms =
            new(StringComparer.OrdinalIgnoreCase)
            {
                ["android"] = ("Android", "*.apk", "application/vnd.android.package-archive"),
                ["ios"] = ("iOS", "*.ipa", "application/octet-stream"),
            };

        private readonly string _root;

        public MobileAppController(IWebHostEnvironment env, IConfiguration config)
        {
            var folder = config["MobileApp:Folder"];
            _root = string.IsNullOrWhiteSpace(folder) ? Path.Combine(env.ContentRootPath, "MobileApp") : folder;
        }

        private string FolderOf(string platform)
        {
            var dir = Path.Combine(_root, Platforms[platform].Folder);
            Directory.CreateDirectory(dir);
            return dir;
        }

        // Android: also an .apk copied straight into MobileApp
        private FileInfo[] Files(string platform)
        {
            var files = new DirectoryInfo(FolderOf(platform)).GetFiles(Platforms[platform].Pattern).AsEnumerable();
            if (platform.Equals("android", StringComparison.OrdinalIgnoreCase))
                files = files.Concat(new DirectoryInfo(_root).GetFiles(Platforms[platform].Pattern));
            return files.OrderByDescending(f => f.LastWriteTimeUtc).ToArray();
        }

        private static object Row(FileInfo f) => new { fileName = f.Name, sizeBytes = f.Length, modified = f.LastWriteTime };

        // GET: api/MobileApp → { android: [{ fileName, sizeBytes, modified }], ios: [...], iosLink }, newest first
        [HttpGet]
        public IActionResult List()
        {
            try
            {
                var linkFile = Path.Combine(FolderOf("ios"), "link.txt");
                var iosLink = System.IO.File.Exists(linkFile)
                    ? System.IO.File.ReadAllLines(linkFile).Select(l => l.Trim()).FirstOrDefault(l => l.StartsWith("http", StringComparison.OrdinalIgnoreCase))
                    : null;
                return Ok(new
                {
                    android = Files("android").Select(Row),
                    ios = Files("ios").Select(Row),
                    iosLink,
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Could not read the MobileApp folder: " + ex.Message });
            }
        }

        // GET: api/MobileApp/android/Latest → the newest .apk, always saved as IRM.apk (the link / QR code for phones)
        [HttpGet("{platform}/Latest")]
        public IActionResult Latest(string platform)
        {
            if (!Platforms.ContainsKey(platform)) return NotFound(new { message = "Unknown platform." });
            var f = Files(platform).FirstOrDefault();
            if (f == null) return NotFound(new { message = "No app file on the server yet." });
            var name = platform.Equals("android", StringComparison.OrdinalIgnoreCase) ? "IRM.apk" : f.Name;
            return PhysicalFile(f.FullName, Platforms[platform].Type, name);
        }

        // GET: api/MobileApp/android/Download/{fileName} → that file
        [HttpGet("{platform}/Download/{fileName}")]
        public IActionResult Download(string platform, string fileName)
        {
            if (!Platforms.ContainsKey(platform)) return NotFound(new { message = "Unknown platform." });
            // a plain file name in the folder only - no paths
            if (string.IsNullOrWhiteSpace(fileName) || Path.GetFileName(fileName) != fileName)
                return BadRequest(new { message = "Not an app file." });
            var f = Files(platform).FirstOrDefault(x => x.Name.Equals(fileName, StringComparison.OrdinalIgnoreCase));
            if (f == null) return NotFound(new { message = "File not found." });
            return PhysicalFile(f.FullName, Platforms[platform].Type, f.Name);
        }
    }
}
