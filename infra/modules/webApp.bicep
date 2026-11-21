targetScope = 'resourceGroup'

param location string
param webAppName string

@description('ID of the App Service Plan to use')
param appServicePlanId string

@description('Absolute base URL of the Public API, including trailing slash')
param apiBaseUrl string

@description('Key Vault secret URI of the catalog database connection string')
param catalogConnectionSecretUri string

@description('Key Vault secret URI of the identity database connection string')
param identityConnectionSecretUri string

param tags object = {}

// Self-referential, so derived from the name rather than the resource to avoid a cycle
var webBaseUrl = 'https://${webAppName}.azurewebsites.net/'

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
          value: 'false'          // Use the Azure SQL databases from the connection strings below
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
        // Key Vault references: App Service resolves them with the app's managed identity and hands the
        // secret value to the app, so no code change is needed. ConnectionStrings__X is read by the app
        // as ConnectionStrings:X. The access policy that allows the read is in keyVaultAccessPolicy.bicep.
        {
          name: 'ConnectionStrings__CatalogConnection'
          value: '@Microsoft.KeyVault(SecretUri=${catalogConnectionSecretUri})'
        }
        {
          name: 'ConnectionStrings__IdentityConnection'
          value: '@Microsoft.KeyVault(SecretUri=${identityConnectionSecretUri})'
        }
      ]
    }
  }
}

output webAppId string        = webApp.id
output webAppName string      = webApp.name
output webAppHostname string  = webApp.properties.defaultHostName
output webAppPrincipalId string = webApp.identity.principalId
