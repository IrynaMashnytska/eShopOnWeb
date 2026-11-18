using Microsoft.eShopWeb.ApplicationCore.Entities.OrderAggregate;
using Microsoft.eShopWeb.Web.Interfaces;

namespace Microsoft.eShopWeb.Web.Services;

public class DeliveryOrderProcessorClient : IDeliveryOrderProcessorClient
{
    public const string ConfigKey = "DeliveryOrderProcessor:Url";

    private readonly HttpClient _httpClient;
    private readonly string? _url;
    private readonly ILogger<DeliveryOrderProcessorClient> _logger;

    public DeliveryOrderProcessorClient(HttpClient httpClient, IConfiguration configuration, ILogger<DeliveryOrderProcessorClient> logger)
    {
        _httpClient = httpClient;
        _url = configuration[ConfigKey];
        _logger = logger;
    }

    // Best effort: the order is already saved, so a failed hand-off to delivery must not fail the checkout.
    public async Task SendAsync(Order order, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(_url))
        {
            _logger.LogWarning("{ConfigKey} is not configured; skipping delivery hand-off for order {OrderId}", ConfigKey, order.Id);
            return;
        }

        var request = new
        {
            orderId = order.Id,
            orderDate = order.OrderDate,
            shippingAddress = new
            {
                street = order.ShipToAddress.Street,
                city = order.ShipToAddress.City,
                state = order.ShipToAddress.State,
                country = order.ShipToAddress.Country,
                zipCode = order.ShipToAddress.ZipCode,
            },
            items = order.OrderItems.Select(i => new
            {
                itemId = i.ItemOrdered.CatalogItemId,
                name = i.ItemOrdered.ProductName,
                unitPrice = i.UnitPrice,
                quantity = i.Units,
            }),
            finalPrice = order.Total(),
        };

        try
        {
            var response = await _httpClient.PostAsJsonAsync(_url, request, cancellationToken);
            response.EnsureSuccessStatusCode();
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            _logger.LogError(ex, "Failed to send delivery details for order {OrderId}", order.Id);
        }
    }
}
