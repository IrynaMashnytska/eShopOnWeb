namespace OrderItemsReserver.Models;

public class OrderRequest
{
    public int OrderId { get; set; }
    public List<OrderItemDetail> Items { get; set; } = new();
}
