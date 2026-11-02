targetScope = 'resourceGroup'

// OrderItemsReserver: HTTP-triggered Azure Function (.NET 8 isolated) that writes
// an order request JSON file to Blob Storage.

param location string
param functionAppName string

@description('ID of the App Service Plan to host the function on')
param appServicePlanId string

@description('Storage account used by the Functions host and as the order request destination')
param storageAccountName string

param ordersContainerName string

@description('Application Insights connection string. Empty disables telemetry.')
@secure()
param appInsightsConnectionString string = ''

param tags object = {}

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
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
      alwaysOn: true               // Dedicated plan: the host is not idled, so the first order is not slowed by a cold start
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
        // Blobs are written with the AzureWebJobsStorage connection string. A managed-identity role assignment
        // is avoided because the deployment principal has no Microsoft.Authorization/roleAssignments/write.
        {
          name: 'OrderStorage__ContainerName'
          value: ordersContainerName
        }
      ], appInsightsSettings)
    }
  }
}

output functionAppId string       = functionApp.id
output functionAppName string     = functionApp.name
output functionHostname string    = functionApp.properties.defaultHostName
