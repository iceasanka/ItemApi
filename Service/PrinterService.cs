using ItemApi.Models;
using System.Drawing.Printing;
using System.Runtime.InteropServices;
using System;
using System.Drawing;

namespace ItemApi.Service
{
    public class PrinterService
    {
        private const string PrinterName = "PegasusPR8003"; // Replace with the printer name as configured on the system

        public void PrintProcessedData(List<ReturnItem> processedItems)
        {
            // Prepare the text to print
            var printText = FormatProcessedData(processedItems);

            // Set up the printer
            PrintDocument printDocument = new PrintDocument();
            printDocument.PrinterSettings.PrinterName = PrinterName;

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
                Console.WriteLine($"Error printing: {ex.Message}");
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
                body += $"{item.Item_Code,-12} {item.Cost_Price,-10} {item.Qty,-5} {netValue,-10}\n";
            }

            // Footer section
            string footer = "----------------------------\n";
            footer += $"Sub Total: {subTotal}\n";
            footer += $"Date: {DateTime.Now:yyyy-MM-dd}\n";
            footer += $"Time: {DateTime.Now:HH:mm:ss}\n";
            footer += "----------------------------\n";
            footer += "Thank you for using our service!";

            // Combine all sections
            return header + body + footer;



        }
    }
}
