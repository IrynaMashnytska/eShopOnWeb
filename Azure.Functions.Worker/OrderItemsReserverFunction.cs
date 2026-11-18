using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using OrderItemsReserver.Models;

namespace OrderItemsReserver;

public class OrderItemsReserverFunction
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web) { WriteIndented = true };

    private readonly ILogger<OrderItemsReserverFunction> _logger;

    public OrderItemsReserverFunction(ILogger<OrderItemsReserverFunction> logger)
    {
        _logger = logger;
    }

    [Function("OrderItemsReserver")]
    public async Task<OrderItemsReserverOutput> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post")] HttpRequestData req,
        CancellationToken cancellationToken)
    {
        OrderRequest? order;
        try
        {
            order = await JsonSerializer.DeserializeAsync<OrderRequest>(req.Body, JsonOptions, cancellationToken);
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "Rejected order request: malformed JSON");
            return await RejectAsync(req, "Request body is not valid JSON.", cancellationToken);
        }

        if (order is null || order.OrderId <= 0 || order.Items.Count == 0
            || order.Items.Any(i => i.ItemId <= 0 || i.Quantity <= 0))
        {
            return await RejectAsync(req, "Order must have a positive orderId and at least one item with positive itemId and quantity.", cancellationToken);
        }

        _logger.LogInformation("Accepted order request {OrderId} with {ItemCount} item(s)", order.OrderId, order.Items.Count);

        var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
        await response.WriteAsJsonAsync(new { blob = $"order-{order.OrderId}.json" }, cancellationToken);

        return new OrderItemsReserverOutput
        {
            Blob = JsonSerializer.Serialize(order, JsonOptions),
            Response = response,
        };
    }

    private static async Task<OrderItemsReserverOutput> RejectAsync(HttpRequestData req, string message, CancellationToken cancellationToken)
    {
        var response = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
        await response.WriteStringAsync(message, cancellationToken);
        return new OrderItemsReserverOutput { Response = response };
    }
}
