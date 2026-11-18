using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;

namespace OrderItemsReserver.Models;

// The function returns data; the Functions host performs the blob write and only then sends the HTTP response,
// so a failed write surfaces to the caller as a 5xx. A null Blob means nothing is written.
public class OrderItemsReserverOutput
{
    // Uses the AzureWebJobsStorage connection (Azurite locally). The container comes from the OrderContainerName app setting.
    [BlobOutput("%OrderContainerName%/order-{OrderId}.json")]
    public string? Blob { get; set; }

    [HttpResult]
    public required HttpResponseData Response { get; set; }
}
