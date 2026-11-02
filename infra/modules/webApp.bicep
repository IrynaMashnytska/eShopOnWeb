targetScope = 'resourceGroup'

param location string
param webAppName string

@description('Name of the deployment slot')
param slotName string = 'dev'

@description('ID of the App Service Plan to use')
param appServicePlanId string

@description('Absolute base URL of the Public API, including trailing slash')
param apiBaseUrl string

@description('Full URL of the OrderItemsReserver HTTP function the Web app calls after an order is created')
param orderItemsReserverUrl string

param tags object = {}

// Self-referential, so derived from the name rather than the resource to avoid a cycle
var webBaseUrl  = 'https://${webAppName}.azurewebsites.net/'
var slotBaseUrl = 'https://${webAppName}-${slotName}.azurewebsites.net/'

resource webApp 'Microsoft.Web/sites@2022-09-01' = {
  name: webAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    clientAffinityEnabled: false

    siteConfig: {
      netFrameworkVersion: 'v8.0'
      alwaysOn: true
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      http20Enabled: true

      // Set here rather than via a child 'web' config resource: that resource issues a full PUT of
      // the web config and would reset the siteConfig values above to their defaults.
      healthCheckPath: '/liveness'

      appSettings: [
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Production'
        }
        {
          name: 'UseOnlyInMemoryDatabase'
          value: 'true'           // No database is deployed: EF Core uses in-memory stores
        }
        {
          name: 'REGION'
          value: location
        }
        {
          name: 'baseUrls__apiBase'
          value: apiBaseUrl        // Without this the app falls back to localhost and /health fails
        }
        {
          name: 'baseUrls__webBase'
          value: webBaseUrl
        }
        {
          name: 'OrderItemsReserver__Url'
          value: orderItemsReserverUrl
        }
      ]
    }
  }
}

resource devSlot 'Microsoft.Web/sites/slots@2022-09-01' = {
  parent: webApp
  name: slotName
  location: location
  tags: union(tags, { slot: slotName })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      alwaysOn: true
      healthCheckPath: '/liveness'
      appSettings: [
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Development'
        }
        {
          name: 'UseOnlyInMemoryDatabase'
          value: 'true'
        }
        {
          name: 'SLOT_NAME'
          value: slotName
        }
        {
          name: 'baseUrls__apiBase'
          value: apiBaseUrl
        }
        {
          name: 'baseUrls__webBase'
          value: slotBaseUrl
        }
        {
          name: 'OrderItemsReserver__Url'
          value: orderItemsReserverUrl
        }
      ]
    }
  }
}

// Sticky settings: these stay with the slot across a swap, so the slot keeps its own environment
// name and webBase instead of carrying them into production.
resource slotConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: webApp
  name: 'slotConfigNames'
  properties: {
    appSettingNames: [
      'ASPNETCORE_ENVIRONMENT'
      'SLOT_NAME'
      'baseUrls__webBase'
    ]
  }
}

output webAppId string        = webApp.id
output webAppName string      = webApp.name
output webAppHostname string  = webApp.properties.defaultHostName
output slotHostname string    = devSlot.properties.defaultHostName
