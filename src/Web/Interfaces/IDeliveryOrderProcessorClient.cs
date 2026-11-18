using Microsoft.eShopWeb.ApplicationCore.Entities.OrderAggregate;

namespace Microsoft.eShopWeb.Web.Interfaces;

public interface IDeliveryOrderProcessorClient
{
    Task SendAsync(Order order, CancellationToken cancellationToken = default);
}
