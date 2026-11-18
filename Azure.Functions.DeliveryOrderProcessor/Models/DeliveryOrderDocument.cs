namespace DeliveryOrderProcessor.Models;

// The Cosmos DB document the delivery department reads. Id is the order id as a string; the container
// is partitioned by orderId. Status starts at "New" and is owned by the delivery department afterwards.
public class DeliveryOrderDocument
{
    public const string NewStatus = "New";

    public string Id { get; set; } = "";
    public int OrderId { get; set; }
    public DateTimeOffset OrderDate { get; set; }
    public ShippingAddress ShippingAddress { get; set; } = new();
    public List<DeliveryOrderItem> Items { get; set; } = new();
    public decimal FinalPrice { get; set; }
    public string Status { get; set; } = NewStatus;
    public DateTimeOffset ReceivedAt { get; set; }

    public static DeliveryOrderDocument From(DeliveryOrderRequest request, DateTimeOffset receivedAt) => new()
    {
        Id = request.OrderId.ToString(),
        OrderId = request.OrderId,
        OrderDate = request.OrderDate,
        ShippingAddress = request.ShippingAddress!,
        Items = request.Items,
        FinalPrice = request.FinalPrice,
        ReceivedAt = receivedAt,
    };
}
