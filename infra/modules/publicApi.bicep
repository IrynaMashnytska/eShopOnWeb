targetScope = 'resourceGroup'

param location string
param apiAppName string
param appServicePlanId string

@description('Public base URL the Web front end is served from, used as the CORS origin')
param webBaseUrl string

@description('Application Insights connection string. Empty disables telemetry: the SDK stays registered but ships nothing.')
@secure()
param appInsightsConnectionString string = ''

param sqlServerFqdn string
param catalogDbName string
param identityDbName string
param sqlAdminLogin string

@secure()
param sqlAdminPassword string

param tags object = {}

var sqlConnectionTemplate = 'Server=tcp:${sqlServerFqdn},1433;User ID=${sqlAdminLogin};Password=${sqlAdminPassword};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

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
          value: 'false'          // Use the Azure SQL databases from the connection strings below
        }
        {
          name: 'SeedDatabase'
          value: 'false'          // The Web app owns migrations and seeding; two apps migrating at once would race
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

      connectionStrings: [
        {
          name: 'CatalogConnection'
          type: 'SQLAzure'
          connectionString: '${sqlConnectionTemplate}Initial Catalog=${catalogDbName};'
        }
        {
          name: 'IdentityConnection'
          type: 'SQLAzure'
          connectionString: '${sqlConnectionTemplate}Initial Catalog=${identityDbName};'
        }
      ]
    }
  }
}

output apiAppId string    = apiApp.id
output apiAppName string  = apiApp.name
output apiHostname string = apiApp.properties.defaultHostName
