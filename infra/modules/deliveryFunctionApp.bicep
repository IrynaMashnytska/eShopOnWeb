targetScope = 'resourceGroup'

// DeliveryOrderProcessor: HTTP-triggered Azure Function (.NET 8 isolated) that saves the
// delivery details of a created order (shipping address, items, final price) to Cosmos DB.

param location string
param functionAppName string

@description('ID of the App Service Plan to host the function on')
param appServicePlanId string

@description('Storage account used by the Functions host runtime')
param storageAccountName string

param cosmosAccountName string
param cosmosDatabaseName string
param cosmosContainerName string

@description('Application Insights connection string. Empty disables telemetry.')
@secure()
param appInsightsConnectionString string = ''

param tags object = {}

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: cosmosAccountName
}

var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

var appInsightsSettings = empty(appInsightsConnectionString) ? [] : [
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsightsConnectionString
  }
]

resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      appSettings: concat([
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        // Key-based access: the deployment principal has no Microsoft.Authorization/roleAssignments/write,
        // so a managed-identity role assignment is not an option (same constraint as the OrderItemsReserver function).
        {
          name: 'CosmosDb__ConnectionString'
          value: cosmos.listConnectionStrings().connectionStrings[0].connectionString
        }
        {
          name: 'CosmosDb__DatabaseName'
          value: cosmosDatabaseName
        }
        {
          name: 'CosmosDb__ContainerName'
          value: cosmosContainerName
        }
      ], appInsightsSettings)
    }
  }
}

output functionAppId string    = functionApp.id
output functionAppName string  = functionApp.name
output functionHostname string = functionApp.properties.defaultHostName
