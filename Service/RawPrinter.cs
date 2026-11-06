using System.ComponentModel;
using System.IO.Ports;
using System.Net.Sockets;
using System.Runtime.InteropServices;

namespace ItemApi.Service
{
    // Sends ready-made printer bytes (ESC/POS, ZPL) to the printer, bypassing the driver's page layout:
    // a Windows printer (spooler, RAW), a COM port (Epson TM Virtual Port Driver / serial cable) or a network "ip:port".
    // Same as TillService/Printing/RawPrinter.cs.
    public static class RawPrinter
    {
        // Windows printer on this server (USB / shared). Success = the spooler accepted the job.
        public static void SendToWindowsPrinter(string printerName, byte[] data, string docName)
        {
            if (!OpenPrinter(printerName, out var hPrinter, IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error(), $"Printer '{printerName}' not found");

            var unmanaged = IntPtr.Zero;
            try
            {
                var doc = new DOCINFOW { pDocName = docName, pDataType = "RAW" };
                if (!StartDocPrinter(hPrinter, 1, doc))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), $"Printer '{printerName}' refused the job");
                try
                {
                    StartPagePrinter(hPrinter);
                    unmanaged = Marshal.AllocCoTaskMem(data.Length);
                    Marshal.Copy(data, 0, unmanaged, data.Length);
                    if (!WritePrinter(hPrinter, unmanaged, data.Length, out var written) || written != data.Length)
                        throw new Win32Exception(Marshal.GetLastWin32Error(), $"Could not write to printer '{printerName}'");
                    EndPagePrinter(hPrinter);
                }
                finally
                {
                    EndDocPrinter(hPrinter);
                }
            }
            finally
            {
                if (unmanaged != IntPtr.Zero)
                    Marshal.FreeCoTaskMem(unmanaged);
                ClosePrinter(hPrinter);
            }
        }

        // Network printer, "host:port" (port 9100 when left out)
        public static async Task SendToNetworkAsync(string address, byte[] data, TimeSpan timeout)
        {
            var parts = address.Trim().Split(':');
            var port = parts.Length > 1 && int.TryParse(parts[1], out var p) ? p : 9100;

            using var cts = new CancellationTokenSource(timeout);
            using var client = new TcpClient();
            try
            {
                await client.ConnectAsync(parts[0], port, cts.Token);
                await using var stream = client.GetStream();
                await stream.WriteAsync(data, cts.Token);
                await stream.FlushAsync(cts.Token);
            }
            catch (OperationCanceledException)
            {
                throw new IOException($"Printer {address} did not answer");
            }
        }

        // COM ports on this server (Settings > Printers drop-down): COM1, COM2, ... in number order
        public static List<string> ListComPorts() =>
            SerialPort.GetPortNames().Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(p => p.Length > 3 && int.TryParse(p.AsSpan(3), out var n) ? n : 999).ToList();

        // COM port, e.g. "COM3". The baud rate only matters on a real serial cable (the Epson virtual port ignores it).
        public static Task SendToSerialAsync(string portName, int baudRate, byte[] data, TimeSpan timeout) =>
            Task.Run(() =>
            {
                portName = portName.Trim();
                using var port = new SerialPort(portName, baudRate > 0 ? baudRate : 38400, Parity.None, 8, StopBits.One)
                {
                    Handshake = Handshake.None,
                    WriteTimeout = (int)timeout.TotalMilliseconds,
                    DtrEnable = true
                };
                try
                {
                    port.Open();
                }
                catch (Exception ex)
                {
                    throw new IOException($"{portName} could not be opened: {ex.Message}");
                }
                try
                {
                    port.Write(data, 0, data.Length);
                    port.BaseStream.Flush();
                }
                catch (TimeoutException)
                {
                    throw new IOException($"The printer on {portName} did not take the print (write timed out) - is it on?");
                }
            });

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private class DOCINFOW
        {
            [MarshalAs(UnmanagedType.LPWStr)] public string? pDocName;
            [MarshalAs(UnmanagedType.LPWStr)] public string? pOutputFile;
            [MarshalAs(UnmanagedType.LPWStr)] public string? pDataType;
        }

        [DllImport("winspool.drv", EntryPoint = "OpenPrinterW", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, IntPtr pDefault);

        [DllImport("winspool.drv", SetLastError = true)]
        private static extern bool ClosePrinter(IntPtr hPrinter);

        [DllImport("winspool.drv", EntryPoint = "StartDocPrinterW", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool StartDocPrinter(IntPtr hPrinter, int level, [In] DOCINFOW di);

        [DllImport("winspool.drv", SetLastError = true)]
        private static extern bool EndDocPrinter(IntPtr hPrinter);

        [DllImport("winspool.drv", SetLastError = true)]
        private static extern bool StartPagePrinter(IntPtr hPrinter);

        [DllImport("winspool.drv", SetLastError = true)]
        private static extern bool EndPagePrinter(IntPtr hPrinter);

        [DllImport("winspool.drv", SetLastError = true)]
        private static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);
    }
}
