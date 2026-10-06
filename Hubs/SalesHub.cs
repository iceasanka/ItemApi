using Microsoft.AspNetCore.SignalR;

namespace ItemApi.Hubs
{
    // Live sales for the back office home page. The page connects to /hubs/sales and listens for
    // "salesChanged" (SalesChangedEvent) — sent by SyncController after a till uploads new bills — then reloads
    // GET api/Dashboard/Today. Nothing is called on the hub by the page.
    public class SalesHub : Hub
    {
        public const string Path = "/hubs/sales";
        public const string SalesChanged = "salesChanged";
    }
}
