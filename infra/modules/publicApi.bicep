targetScope = 'resourceGroup'

param location string
param apiAppName string
param appServicePlanId string

@description('Public base URL the Web front end is served from, used as the CORS origin')
param webBaseUrl string

@description('Application Insights connection string. Empty disables telemetry: the SDK stays registered but ships nothing.')
@secure()
param appInsightsConnectionString string = ''

param tags object = {}

var appInsightsSettings = empty(appInsightsConnectionString) ? [] : [
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsightsConnectionString
  }
]

resource apiApp 'Microsoft.Web/sites@2022-09-01' = {
  name: apiAppName
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      alwaysOn: true
      cors: {
        allowedOrigins: [ '*' ]
        supportCredentials: false
      }
      appSettings: concat([
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Development'
        }
        {
          name: 'UseOnlyInMemoryDatabase'
          value: 'true'           // No database is deployed: EF Core uses in-memory stores
        }
        {
          name: 'baseUrls__webBase'
          value: webBaseUrl        // Drives the app's own CORS policy; localhost otherwise
        }
        {
          name: 'baseUrls__apiBase'
          value: 'https://${apiAppName}.azurewebsites.net/api/'
        }
      ], appInsightsSettings)
    }
  }
}

output apiAppId string    = apiApp.id
output apiAppName string  = apiApp.name
output apiHostname string = apiApp.properties.defaultHostName
