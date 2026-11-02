using Microsoft.eShopWeb.ApplicationCore.Entities.OrderAggregate;
using Microsoft.eShopWeb.Web.Interfaces;

namespace Microsoft.eShopWeb.Web.Services;

public class OrderItemsReserverClient : IOrderItemsReserverClient
{
    public const string ConfigKey = "OrderItemsReserver:Url";

    private readonly HttpClient _httpClient;
    private readonly string? _url;
    private readonly ILogger<OrderItemsReserverClient> _logger;

    public OrderItemsReserverClient(HttpClient httpClient, IConfiguration configuration, ILogger<OrderItemsReserverClient> logger)
    {
        _httpClient = httpClient;
        _url = configuration[ConfigKey];
        _logger = logger;
    }

    // Best effort: the order is already saved, so a failed reservation request must not fail the checkout.
    public async Task ReserveAsync(Order order, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(_url))
        {
            _logger.LogWarning("{ConfigKey} is not configured; skipping reservation request for order {OrderId}", ConfigKey, order.Id);
            return;
        }

        var request = new
        {
            orderId = order.Id,
            items = order.OrderItems.Select(i => new { itemId = i.ItemOrdered.CatalogItemId, quantity = i.Units })
        };

        try
        {
            var response = await _httpClient.PostAsJsonAsync(_url, request, cancellationToken);
            response.EnsureSuccessStatusCode();
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            _logger.LogError(ex, "Failed to send reservation request for order {OrderId}", order.Id);
        }
    }
}
