targetScope = 'resourceGroup'

param location string
param projectName string
param environment string
param regionShort string
param suffix string

@description('ID of the App Service Plan to use')
param appServicePlanId string

param enableDeploymentSlot bool = false

param tags object = {}

var webAppName = 'web-${projectName}-${regionShort}-${suffix}'

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

      // ── APP SETTINGS ────────────────────────
      appSettings: [
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Production'
        }
        {
          name: 'UseOnlyInMemoryDatabase'
          value: 'false'           // Use real SQL, not in-memory
        }
        {
          name: 'REGION'
          value: location          // Useful for debugging
        }
      ]
    }
  }
}

// ──────────────────────────────────────────────
// HEALTH CHECK
// Traffic Manager needs this to check if app is up
// You need to add /health endpoint in your code
// ──────────────────────────────────────────────

resource webConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: webApp
  name: 'web'
  properties: {
    healthCheckPath: '/health'
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
      ]
    }
  }
}

resource slotConfig 'Microsoft.Web/sites/config@2022-09-01' = if (enableDeploymentSlot) {
  parent: webApp
  name: 'slotConfigNames'
  properties: {
    appSettingNames: [
      'ASPNETCORE_ENVIRONMENT'  // Staging keeps 'Staging'
      'SLOT_NAME'               // Staging keeps 'staging'
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
