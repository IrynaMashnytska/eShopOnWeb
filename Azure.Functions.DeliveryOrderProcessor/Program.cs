using System.Text.Json;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var connectionString = config["CosmosDb:ConnectionString"];
    if (string.IsNullOrWhiteSpace(connectionString))
    {
        throw new InvalidOperationException("CosmosDb:ConnectionString is not configured.");
    }

    return new CosmosClient(connectionString, new CosmosClientOptions
    {
        ApplicationName = "DeliveryOrderProcessor",
        // camelCase property names, so Id is stored as the "id" Cosmos DB requires
        UseSystemTextJsonSerializerWithOptions = new JsonSerializerOptions(JsonSerializerDefaults.Web),
    });
});

builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    return sp.GetRequiredService<CosmosClient>().GetContainer(
        config["CosmosDb:DatabaseName"] ?? "delivery",
        config["CosmosDb:ContainerName"] ?? "orders");
});

builder.Build().Run();
