// infra/main.bicep
// ──────────────────────────────────────────────
// MAIN FILE - This is the ORCHESTRATOR
// It calls all modules in the right order
// ──────────────────────────────────────────────

targetScope = 'subscription'     


@allowed(['dev', 'staging', 'prod'])
param environment string = 'prod'

param projectName string = 'eshop'

param locationEastUS string = 'eastus'
param locationWestEU string = 'westeurope'

@allowed(['S1', 'S2'])
param appServiceSku string = 'S1'


// ── PUBLIC API AUTOSCALE ──────────────────────
// Single source of truth: apiMinInstances is both the autoscale floor and the capacity the West EU
// plan is deployed with, so `1-infra.yml` can no longer push a value the autoscale rule disagrees
// with. Note the plan is still set to the floor on every redeploy, so avoid running the infra
// workflow in the middle of a load test - autoscale will climb back, but not instantly.

@description('Autoscale floor for the Public API plan')
@minValue(1)
param apiMinInstances int = 1

@description('Autoscale ceiling for the Public API plan')
@maxValue(10)
param apiMaxInstances int = 5

@description('CPU % that triggers scale out')
param apiCpuScaleOut int = 70

@description('CPU % that triggers scale in')
param apiCpuScaleIn int = 30


// ──────────────────────────────────────────────
// VARIABLES
// ──────────────────────────────────────────────

// Create a short unique suffix based on subscription ID
// uniqueString() always returns same value for same input
// take() gets first 6 characters: 'a1b2c3'
var suffix = toLower(take(uniqueString(subscription().subscriptionId), 6))

// Resource Group names
var rgEastUS = 'rg-${projectName}-eus-${environment}'
var rgWestEU = 'rg-${projectName}-weu-${environment}'
var rgShared = 'rg-${projectName}-shared-${environment}'

// Traffic Manager DNS label, computed here rather than read from the trafficManager module's output:
// the API needs the public Web URL for its CORS origin, and the module depends on the Web apps.
// Deriving the label breaks what would otherwise be api -> tm -> web -> api.
var envSuffix   = environment == 'prod' ? '' : '-${environment}'
var tmDnsLabel  = '${projectName}${envSuffix}-${suffix}'
var tmPublicUrl = 'https://${tmDnsLabel}.trafficmanager.net/'


// ──────────────────────────────────────────────
// STEP 1: CREATE RESOURCE GROUPS
// Must happen first! Everything else goes inside these
// ──────────────────────────────────────────────

resource rgEastUSResource 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: rgEastUS
  location: locationEastUS
  tags: {
    environment: environment
    project: projectName
    managedBy: 'bicep'
  }
}

resource rgWestEUResource 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: rgWestEU
  location: locationWestEU
  tags: {
    environment: environment
    project: projectName
    managedBy: 'bicep'
  }
}

resource rgSharedResource 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: rgShared
  location: locationEastUS       // Shared resources in East US
  tags: {
    environment: environment
    project: projectName
    managedBy: 'bicep'
  }
}


module planEastUS 'modules/appservice-plan.bicep' = {
  name: 'deploy-plan-eastus'
  scope: rgEastUSResource
  params: {
    location: locationEastUS
    projectName: projectName
    environment: environment
    regionShort: 'eus'
    sku: appServiceSku
    tags: {
      environment: environment
      region: locationEastUS
    }
  }
}

// ──────────────────────────────────────────────
// STEP 6: WEST EUROPE - APP SERVICE PLAN
// ──────────────────────────────────────────────

module planWestEU 'modules/appservice-plan.bicep' = {
  name: 'deploy-plan-westeu'
  scope: rgWestEUResource
  params: {
    location: locationWestEU
    projectName: projectName
    environment: environment
    regionShort: 'weu'
    sku: appServiceSku
    capacity: apiMinInstances          // Matches the autoscale floor below
    tags: {
      environment: environment
      region: locationWestEU
    }
  }
}


// Deployed before the Web apps: they need its hostname for baseUrls__apiBase.
module publicApi 'modules/publicApi.bicep' = {
  name: 'deploy-api-westeu'
  scope: rgWestEUResource
  params: {
    location: locationWestEU
    projectName: projectName
    environment: environment
    suffix: '${suffix}eu'
    appServicePlanId: planWestEU.outputs.planId
    appServicePlanName: planWestEU.outputs.planName
    webBaseUrl: tmPublicUrl
    minInstances: apiMinInstances
    maxInstances: apiMaxInstances
    cpuScaleOut: apiCpuScaleOut
    cpuScaleIn: apiCpuScaleIn
    tags: {
      environment: environment
      region: locationWestEU
      component: 'api'
    }
  }
}

var apiBaseUrl = 'https://${publicApi.outputs.apiHostname}/api/'

module webAppEastUS 'modules/webApp.bicep' = {
  name: 'deploy-webapp-eastus'
  scope: rgEastUSResource
  params: {
    location: locationEastUS
    projectName: projectName
    environment: environment
    regionShort: 'eus'
    suffix: suffix
    appServicePlanId: planEastUS.outputs.planId
    apiBaseUrl: apiBaseUrl
    enableDeploymentSlot: true                         // ← Enable for East US
    tags: {
      environment: environment
      region: locationEastUS
      component: 'web'
    }
  }
}

module webAppWestEU 'modules/webApp.bicep' = {
  name: 'deploy-webapp-westeu'
  scope: rgWestEUResource
  params: {
    location: locationWestEU
    projectName: projectName
    environment: environment
    regionShort: 'weu'
    suffix: '${suffix}eu'
    appServicePlanId: planWestEU.outputs.planId
    apiBaseUrl: apiBaseUrl
    enableDeploymentSlot: false                        // ← No slot here
    tags: {
      environment: environment
      region: locationWestEU
      component: 'web'
    }
  }
}


module trafficManager 'modules/trafficManager.bicep' = {
  name: 'deploy-traffic-manager'
  scope: rgSharedResource             // In shared RG
  params: {
    projectName: projectName
    environment: environment
    dnsLabel: tmDnsLabel
    webAppEastUSId: webAppEastUS.outputs.webAppId       // ← From webApp module
    webAppWestEUID: webAppWestEU.outputs.webAppId        // ← From webApp module
    webAppEastUSHostname: webAppEastUS.outputs.webAppHostname
    webAppWestEUHostname: webAppWestEU.outputs.webAppHostname
    routingMethod: 'Performance'
    tags: {
      environment: environment
      component: 'traffic-manager'
    }
  }
}


output summary object = {
  webEastUS: {
    production: 'https://${webAppEastUS.outputs.webAppHostname}'
    staging: 'https://${webAppEastUS.outputs.stagingHostname}'
  }
  webWestEU: {
    production: 'https://${webAppWestEU.outputs.webAppHostname}'
  }
  publicApi: {
    url: 'https://${publicApi.outputs.apiHostname}'
    autoscale: publicApi.outputs.autoscaleName
  }
  trafficManager: {
    // HTTPS, not HTTP: the auth cookie is CookieSecurePolicy.Always, so sign-in silently fails over
    // plain HTTP. The browser will warn about the certificate - the App Service default cert covers
    // *.azurewebsites.net, not *.trafficmanager.net - which is expected here.
    url: 'https://${trafficManager.outputs.tmFqdn}'
  }
}
