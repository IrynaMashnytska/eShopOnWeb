using System.Net;
using System.Text.Json;
using DeliveryOrderProcessor.Models;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace DeliveryOrderProcessor;

public class DeliveryOrderProcessorFunction
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private readonly Container _container;
    private readonly ILogger<DeliveryOrderProcessorFunction> _logger;

    public DeliveryOrderProcessorFunction(Container container, ILogger<DeliveryOrderProcessorFunction> logger)
    {
        _container = container;
        _logger = logger;
    }

    [Function("DeliveryOrderProcessor")]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post")] HttpRequest req,
        CancellationToken cancellationToken)
    {
        DeliveryOrderRequest? order;
        try
        {
            order = await JsonSerializer.DeserializeAsync<DeliveryOrderRequest>(req.Body, JsonOptions, cancellationToken);
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "Rejected delivery order: malformed JSON");
            return new BadRequestObjectResult("Request body is not valid JSON.");
        }

        var error = Validate(order);
        if (error is not null)
        {
            _logger.LogWarning("Rejected delivery order: {Error}", error);
            return new BadRequestObjectResult(error);
        }

        var document = DeliveryOrderDocument.From(order!, DateTimeOffset.UtcNow);

        try
        {
            await _container.CreateItemAsync(document, new PartitionKey(document.OrderId), cancellationToken: cancellationToken);
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.Conflict)
        {
            // The caller retried an order that is already stored. Keep the stored document: the
            // delivery department may have moved it past "New" already.
            _logger.LogInformation("Delivery order {OrderId} already exists; nothing to do", document.OrderId);
            return new OkObjectResult(new { id = document.Id, created = false });
        }

        _logger.LogInformation("Saved delivery order {OrderId} with {ItemCount} item(s), total {FinalPrice}",
            document.OrderId, document.Items.Count, document.FinalPrice);
        return new ObjectResult(new { id = document.Id, created = true }) { StatusCode = StatusCodes.Status201Created };
    }

    public static string? Validate(DeliveryOrderRequest? order)
    {
        if (order is null || order.OrderId <= 0)
        {
            return "Order must have a positive orderId.";
        }

        var address = order.ShippingAddress;
        if (address is null
            || string.IsNullOrWhiteSpace(address.Street)
            || string.IsNullOrWhiteSpace(address.City)
            || string.IsNullOrWhiteSpace(address.Country)
            || string.IsNullOrWhiteSpace(address.ZipCode))
        {
            return "Order must have a shipping address with street, city, country and zipCode.";
        }

        if (order.Items.Count == 0 || order.Items.Any(i => i.ItemId <= 0 || i.Quantity <= 0 || i.UnitPrice < 0))
        {
            return "Order must have at least one item with positive itemId and quantity and a non-negative unitPrice.";
        }

        if (order.FinalPrice < 0)
        {
            return "Order finalPrice must not be negative.";
        }

        return null;
    }
}
