using System;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.eShopWeb.UnitTests.Builders;
using Microsoft.eShopWeb.Web.Services;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Microsoft.eShopWeb.UnitTests.Web.Services;

public class DeliveryOrderProcessorClientTests
{
    private const string Url = "https://delivery.test/api/DeliveryOrderProcessor";

    private class StubHandler : HttpMessageHandler
    {
        private readonly HttpStatusCode _status;
        public string? Body { get; private set; }
        public Uri? RequestUri { get; private set; }
        public int Calls { get; private set; }

        public StubHandler(HttpStatusCode status) => _status = status;

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            RequestUri = request.RequestUri;
            Body = request.Content == null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
            return new HttpResponseMessage(_status);
        }
    }

    private static DeliveryOrderProcessorClient CreateClient(StubHandler handler, string? url = Url)
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new[] { new System.Collections.Generic.KeyValuePair<string, string?>(DeliveryOrderProcessorClient.ConfigKey, url) })
            .Build();
        return new DeliveryOrderProcessorClient(new HttpClient(handler), config, NullLogger<DeliveryOrderProcessorClient>.Instance);
    }

    [Fact]
    public async Task SendsShippingAddressItemsAndFinalPrice()
    {
        var handler = new StubHandler(HttpStatusCode.Created);
        var order = new OrderBuilder().WithDefaultValues();

        await CreateClient(handler).SendAsync(order);

        Assert.Equal(Url, handler.RequestUri!.ToString());
        using var json = JsonDocument.Parse(handler.Body!);
        var root = json.RootElement;
        Assert.Equal(order.Id, root.GetProperty("orderId").GetInt32());
        Assert.Equal(order.ShipToAddress.City, root.GetProperty("shippingAddress").GetProperty("city").GetString());
        Assert.Equal(order.ShipToAddress.ZipCode, root.GetProperty("shippingAddress").GetProperty("zipCode").GetString());
        Assert.Equal(order.Total(), root.GetProperty("finalPrice").GetDecimal());
        var item = root.GetProperty("items")[0];
        Assert.Equal(234, item.GetProperty("itemId").GetInt32());
        Assert.Equal("Test Product Name", item.GetProperty("name").GetString());
        Assert.Equal(1.23m, item.GetProperty("unitPrice").GetDecimal());
        Assert.Equal(3, item.GetProperty("quantity").GetInt32());
    }

    [Fact]
    public async Task DoesNotThrowWhenFunctionFails()
    {
        var handler = new StubHandler(HttpStatusCode.InternalServerError);

        await CreateClient(handler).SendAsync(new OrderBuilder().WithDefaultValues());

        Assert.Equal(1, handler.Calls);
    }

    [Fact]
    public async Task SkipsCallWhenUrlNotConfigured()
    {
        var handler = new StubHandler(HttpStatusCode.Created);

        await CreateClient(handler, url: null).SendAsync(new OrderBuilder().WithDefaultValues());

        Assert.Equal(0, handler.Calls);
    }
}
