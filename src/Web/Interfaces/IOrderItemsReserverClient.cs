using Microsoft.eShopWeb.ApplicationCore.Entities.OrderAggregate;

namespace Microsoft.eShopWeb.Web.Interfaces;

public interface IOrderItemsReserverClient
{
    Task ReserveAsync(Order order, CancellationToken cancellationToken = default);
}
