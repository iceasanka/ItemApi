namespace ItemApi.Models
{
    // Tools > Order Lists (U063): lists of the items ordered from another shop, printed with a blank qty column.

    // z_sp_OrderListGet row (one per line; LineId null = a list with no line)
    public class OrderListFlatRow
    {
        public int ListId { get; set; }
        public byte Kind { get; set; }
        public bool Sinhala { get; set; }
        public string ListName { get; set; } = "";
        public int ListSortNo { get; set; }
        public int? LineId { get; set; }
        public int? ItemId { get; set; }
        public string Descrip { get; set; } = "";
        // the item's own name (Descrip = the name printed: typed for the list, else this)
        public string? ItemDescrip { get; set; }
        public string? ItemSinhala { get; set; }
        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        public int? ItemStatus { get; set; }
        public string? Note { get; set; }
        public int? SortNo { get; set; }
    }

    public class OrderListDto
    {
        public int ListId { get; set; }
        // 1 order list (qty written on the print), 2 code list (names + ref codes, A4 two columns)
        public byte Kind { get; set; } = 1;
        // true = the items' Sinhala names are printed (an item with none: its English name; a name typed for the list wins)
        public bool Sinhala { get; set; }
        public string Name { get; set; } = "";
        public List<OrderListLineDto> Lines { get; set; } = new();
    }

    public class OrderListLineDto
    {
        public int LineId { get; set; }
        // null = a text line (something not in our items)
        public int? ItemId { get; set; }
        public string Descrip { get; set; } = "";
        // the item's own name (Descrip = the name printed: typed for the list, else this)
        public string? ItemDescrip { get; set; }
        // the item's Sinhala name (null = none)
        public string? ItemSinhala { get; set; }
        public string? RefCode { get; set; }
        public string? Barcode { get; set; }
        // false = the item was deactivated (still on the list)
        public bool Active { get; set; } = true;
        public string? Note { get; set; }
    }

    public class OrderListNameRequest
    {
        public string? Name { get; set; }
        // a new list: 1 order list (default), 2 code list
        public byte Kind { get; set; } = 1;
    }

    // PUT api/OrderList/{id}/Sinhala
    public class OrderListSinhalaRequest
    {
        public bool Sinhala { get; set; }
    }

    // an item (ItemId) or a text (Text)
    public class OrderListLineRequest
    {
        public int? ItemId { get; set; }
        public string? Text { get; set; }
        public string? Note { get; set; }
    }

    // POST api/OrderList/{id}/Print - on the bill printer (thermal); Spaced = an empty line under each item to write on
    public class OrderListPrintRequest
    {
        public bool Spaced { get; set; } = true;
    }

    public class OrderListIdRow
    {
        public int ListId { get; set; }
    }

    public class OrderListLineIdRow
    {
        public int LineId { get; set; }
    }
}
