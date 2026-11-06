using ItemApi.Models;
using System.Drawing.Printing;
using System.Runtime.InteropServices;
using System;
using System.Drawing;
using Serilog;
using System.Text.Json;
using static ItemApi.Controllers.UtilController;
using System.Text;

namespace ItemApi.Service
{
    public class PrinterService
    {
        // return item slip on the bill printer (Settings > Printers - PrinterConfig): a Windows printer prints it through
        // its driver as before; a COM port / network printer gets the same lines as ESC/POS
        public async Task PrintProcessedDataAsync(List<ReturnItem> processedItems, Printers printers)
        {
            var target = printers.NeedBill();
            if (target.Conn == PrinterTarget.Windows)
            {
                await Task.Run(() => PrintProcessedData(processedItems, target.Name));
                return;
            }
            var slip = new ReceiptSlip(printers.BillChars);
            foreach (var line in FormatProcessedData(processedItems).Split('\n'))
                slip.Line(line.TrimEnd('\r'));
            await target.SendRawAsync(slip.ToEscPos(), "Return items");
        }

        public void PrintProcessedData(List<ReturnItem> processedItems, string printerName)
        {
            // Prepare the text to print
            var printText = FormatProcessedData(processedItems);

            // Set up the printer
            PrintDocument printDocument = new PrintDocument();
            printDocument.PrinterSettings.PrinterName = printerName;

            printDocument.PrintPage += (sender, e) =>
            {
                e.Graphics.DrawString(printText, new Font("Courier New", 10, FontStyle.Bold), Brushes.Black, new PointF(0, 0));
            };

            // Print the document
            try
            {
                printDocument.Print();
            }
            catch (Exception ex)
            {
                Log.Error($"Error: {ex}");
                throw;
            }
        }

       

        private string FormatProcessedData(List<ReturnItem> processedItems)
        {
            // Header section
            string header = "IRESHA FOOD CITY-Return Items\n";
            // Header section
            header += "----------------------------\n";

            // Column Headers
            header += "ItemCode   C.Price   Qty   Netv\n";
            header += "----------------------------\n";

            // Body section
            string body = "";
            decimal subTotal = 0;
            int itemCount = 1; // Counter for item numbering

            foreach (var item in processedItems)
            {
                // Calculate net value
                decimal netValue = item.Cost_Price  * (decimal)item.Qty;
                subTotal += netValue;

                // Append item details
                body += $"{itemCount++} - {item.Descrip}\n"; // Description with numbering
                body += $"{item.Item_Code,-12} {item.Cost_Price,-5} {item.Qty,-5} {netValue,-15}\n";
            }

            // Footer section
            string footer = "----------------------------\n";
            footer += $"Sub Total: {subTotal}\n";
            footer += $"Date: {DateTime.Now:yyyy-MM-dd}\n";
            footer += $"Time: {DateTime.Now:HH:mm:ss}\n";
            footer += "----------------------------\n";
            footer += "Thank you!";

            // Combine all sections
            return header + body + footer;



        }
        
    }

}
