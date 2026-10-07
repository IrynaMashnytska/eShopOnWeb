targetScope = 'resourceGroup'

// ──────────────────────────────────────────────
// PARAMETERS
// ──────────────────────────────────────────────

param projectName string
param environment string

@description('DNS label for the profile, e.g. eshop-abc123 -> eshop-abc123.trafficmanager.net. Passed in so callers can derive the public URL without depending on this module.')
param dnsLabel string

@description('Resource ID of East US Web App')
param webAppEastUSId string

@description('Resource ID of West EU Web App')
param webAppWestEUID string

@description('Hostname of East US Web App')
param webAppEastUSHostname string

@description('Hostname of West EU Web App')
param webAppWestEUHostname string

// ──────────────────────────────────────────────
// HOW ROUTING METHODS WORK:
//
// Performance → User goes to CLOSEST region
//   User in US  → East US App
//   User in EU  → West Europe App
//   ← BEST for our case!
//
// Priority    → Always use primary, failover if down
//   East US = Priority 1 (always used)
//   West EU = Priority 2 (only if East US fails)
//
// Weighted    → Split traffic by percentage
//   East US = 80%
//   West EU = 20%
// ──────────────────────────────────────────────

@allowed(['Performance', 'Priority', 'Weighted'])
param routingMethod string = 'Performance'

param tags object = {}


var tmProfileName = 'tm-${projectName}-${environment}'
var tmDnsName     = dnsLabel
// Result URL: eshop-abc123.trafficmanager.net


resource tmProfile 'Microsoft.Network/trafficManagerProfiles@2022-04-01' = {
  name: tmProfileName
  location: 'global'             // MUST be 'global' for Traffic Manager
  tags: tags
  properties: {
    profileStatus: 'Enabled'
    trafficRoutingMethod: routingMethod

    dnsConfig: {
      relativeName: tmDnsName    // → eshop-abc123.trafficmanager.net
      ttl: 30                    // DNS cache: 30 seconds
    }

    // ── HEALTH MONITORING ─────────────────────
    // Traffic Manager checks this path
    // If it fails → remove from rotation
    monitorConfig: {
      protocol: 'HTTPS'
      port: 443
      path: '/liveness'          // App-only check: an API outage must not degrade both Web regions
      intervalInSeconds: 30      // Check every 30s
      timeoutInSeconds: 10       // Wait 10s for response
      toleratedNumberOfFailures: 3  // 3 failures = endpoint down
    }
  }
}

resource endpointEastUS 'Microsoft.Network/trafficManagerProfiles/azureEndpoints@2022-04-01' = {
  parent: tmProfile
  name: 'endpoint-eastus'
  properties: {
    targetResourceId: webAppEastUSId   // Link to actual App Service
    endpointStatus: 'Enabled'
    priority: 1                        // Primary (for Priority routing)
    weight: 50                         // 50% (for Weighted routing)
    endpointLocation: 'eastus'         // For Performance routing
  }
}


resource endpointWestEU 'Microsoft.Network/trafficManagerProfiles/azureEndpoints@2022-04-01' = {
  parent: tmProfile
  name: 'endpoint-westeu'
  properties: {
    targetResourceId: webAppWestEUID
    endpointStatus: 'Enabled'
    priority: 2                        // Secondary
    weight: 50                         // 50%
    endpointLocation: 'westeurope'
  }
}

output tmProfileId string = tmProfile.id
output tmDnsName string   = tmDnsName
output tmFqdn string      = tmProfile.properties.dnsConfig.fqdn
