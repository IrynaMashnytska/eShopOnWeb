using System.Text.Json;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using OrderItemsReserver.Models;

namespace OrderItemsReserver;

public class OrderItemsReserverFunction
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web) { WriteIndented = true };

    private readonly BlobContainerClient _container;
    private readonly ILogger<OrderItemsReserverFunction> _logger;

    public OrderItemsReserverFunction(BlobContainerClient container, ILogger<OrderItemsReserverFunction> logger)
    {
        _container = container;
        _logger = logger;
    }

    [Function("OrderItemsReserver")]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post")] HttpRequest req,
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
            return new BadRequestObjectResult("Request body is not valid JSON.");
        }

        if (order is null || order.OrderId <= 0 || order.Items.Count == 0
            || order.Items.Any(i => i.ItemId <= 0 || i.Quantity <= 0))
        {
            return new BadRequestObjectResult("Order must have a positive orderId and at least one item with positive itemId and quantity.");
        }

        var blobName = $"order-{order.OrderId}.json";
        var content = BinaryData.FromBytes(JsonSerializer.SerializeToUtf8Bytes(order, JsonOptions));

        await _container.CreateIfNotExistsAsync(cancellationToken: cancellationToken);
        await _container.GetBlobClient(blobName).UploadAsync(
            content,
            new BlobUploadOptions { HttpHeaders = new BlobHttpHeaders { ContentType = "application/json" } },
            cancellationToken);

        _logger.LogInformation("Uploaded order request {BlobName} with {ItemCount} item(s)", blobName, order.Items.Count);
        return new OkObjectResult(new { blob = blobName });
    }
}
