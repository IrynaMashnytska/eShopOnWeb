using Azure.Identity;
using Azure.Storage.Blobs;
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
    var containerName = config["OrderStorage:ContainerName"] ?? "order-requests";

    // In Azure the managed identity is used; locally there is no URI, so fall back to Azurite / the dev connection string.
    var serviceUri = config["OrderStorage:BlobServiceUri"];
    var service = string.IsNullOrEmpty(serviceUri)
        ? new BlobServiceClient(config["AzureWebJobsStorage"])
        : new BlobServiceClient(new Uri(serviceUri), new DefaultAzureCredential());

    return service.GetBlobContainerClient(containerName);
});

builder.Build().Run();
