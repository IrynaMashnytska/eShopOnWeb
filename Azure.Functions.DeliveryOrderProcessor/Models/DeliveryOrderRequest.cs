namespace DeliveryOrderProcessor.Models;

public class DeliveryOrderRequest
{
    public int OrderId { get; set; }
    public DateTimeOffset OrderDate { get; set; }
    public ShippingAddress? ShippingAddress { get; set; }
    public List<DeliveryOrderItem> Items { get; set; } = new();
    public decimal FinalPrice { get; set; }
}

public class ShippingAddress
{
    public string Street { get; set; } = "";
    public string City { get; set; } = "";
    public string State { get; set; } = "";
    public string Country { get; set; } = "";
    public string ZipCode { get; set; } = "";
}

public class DeliveryOrderItem
{
    public int ItemId { get; set; }
    public string Name { get; set; } = "";
    public decimal UnitPrice { get; set; }
    public int Quantity { get; set; }
}
