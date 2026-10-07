targetScope = 'resourceGroup'

param location string
param projectName string
param environment string
param regionShort string
param suffix string

@description('ID of the App Service Plan to use')
param appServicePlanId string

@description('Absolute base URL of the Public API, including trailing slash')
param apiBaseUrl string

param enableDeploymentSlot bool = false

param tags object = {}

// Keeps prod names unchanged while separating dev/staging deployments in the same subscription
// (site names are globally unique, and `suffix` is subscription-wide).
var envSuffix = environment == 'prod' ? '' : '-${environment}'

var webAppName = 'web-${projectName}-${regionShort}${envSuffix}-${suffix}'

// Self-referential, so derived from the name rather than the resource to avoid a cycle
var webBaseUrl    = 'https://${webAppName}.azurewebsites.net/'
var slotBaseUrl   = 'https://${webAppName}-staging.azurewebsites.net/'

resource webApp 'Microsoft.Web/sites@2022-09-01' = {
  name: webAppName
  location: location
  tags: tags

  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    serverFarmId: appServicePlanId  // Which plan to use
    httpsOnly: true                 // Force HTTPS
    clientAffinityEnabled: false    // Better for multi-region

    siteConfig: {
      netFrameworkVersion: 'v8.0'   // .NET 8
      alwaysOn: true                // Never sleep (needs S1+)
      ftpsState: 'FtpsOnly'         // Secure FTP only
      minTlsVersion: '1.2'          // Security: no old TLS
      http20Enabled: true           // Use HTTP/2

      // Set here rather than via a child 'web' config resource: that resource issues a full PUT of
      // the web config and would reset the siteConfig values above to their defaults.
      healthCheckPath: '/liveness'

      // ── APP SETTINGS ────────────────────────
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
          value: location          // Useful for debugging
        }
        {
          name: 'baseUrls__apiBase'
          value: apiBaseUrl        // Without this the app falls back to localhost and /health fails
        }
        {
          name: 'baseUrls__webBase'
          value: webBaseUrl
        }
      ]
    }
  }
}

resource stagingSlot 'Microsoft.Web/sites/slots@2022-09-01' = if (enableDeploymentSlot) {
  parent: webApp
  name: 'staging'
  location: location
  tags: union(tags, { slot: 'staging' })
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
          value: 'Staging'
        }
        {
          name: 'UseOnlyInMemoryDatabase'
          value: 'true'
        }
        {
          name: 'SLOT_NAME'
          value: 'staging'
        }
        {
          name: 'baseUrls__apiBase'
          value: apiBaseUrl
        }
        {
          name: 'baseUrls__webBase'
          value: slotBaseUrl
        }
      ]
    }
  }
}

// Sticky settings: these stay with the slot across a swap, so the slot keeps Staging/staging and
// its own webBase instead of carrying them into production.
resource slotConfig 'Microsoft.Web/sites/config@2022-09-01' = if (enableDeploymentSlot) {
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

// ──────────────────────────────────────────────
// OUTPUTS
// ──────────────────────────────────────────────

output webAppId string       = webApp.id
output webAppName string     = webApp.name
output webAppHostname string = webApp.properties.defaultHostName

// Ternary operator: if slot enabled return hostname, else empty string
output stagingHostname string = enableDeploymentSlot
  ? stagingSlot.properties.defaultHostName
  : ''
