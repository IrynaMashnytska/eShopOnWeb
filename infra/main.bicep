// infra/main.bicep
// ──────────────────────────────────────────────
// MAIN FILE - This is the ORCHESTRATOR
// It calls all modules in the right order
// ──────────────────────────────────────────────

targetScope = 'subscription'     


@secure()

@allowed(['dev', 'staging', 'prod'])
param environment string = 'prod'

param projectName string = 'eshop'

param locationEastUS string = 'eastus'
param locationWestEU string = 'westeurope'

@allowed(['S1', 'S2'])
param appServiceSku string = 'S1'


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
    enableDeploymentSlot: true                         // ← Enable for East US
    tags: {
      environment: environment
      region: locationEastUS
      component: 'web'
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
    tags: {
      environment: environment
      region: locationWestEU
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
    enableDeploymentSlot: false                        // ← No slot here
    tags: {
      environment: environment
      region: locationWestEU
      component: 'web'
    }
  }
}

module publicApi 'modules/publicApi.bicep' = {
  name: 'deploy-api-westeu'
  scope: rgWestEUResource
  params: {
    location: locationWestEU
    projectName: projectName
    suffix: '${suffix}eu'
    appServicePlanId: planWestEU.outputs.planId
    appServicePlanName: planWestEU.outputs.planName
    minInstances: 1
    maxInstances: 5
    cpuScaleOut: 70
    cpuScaleIn: 30
    tags: {
      environment: environment
      region: locationWestEU
      component: 'api'
    }
  }
}


module trafficManager 'modules/trafficManager.bicep' = {
  name: 'deploy-traffic-manager'
  scope: rgSharedResource             // In shared RG
  params: {
    projectName: projectName
    environment: environment
    suffix: suffix
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
    url: 'http://${trafficManager.outputs.tmFqdn}'
  }
}
