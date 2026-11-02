// infra/main.bicep
// Single environment, single region: one resource group (rg-eshop-prod) holding one App Service plan,
// the Public API, the Web app, Application Insights, and the OrderItemsReserver Function App
// with the Storage account that holds the order request blobs.

targetScope = 'subscription'

@allowed(['prod'])
param environment string = 'prod'

param projectName string = 'eshop'

param location string = 'westeurope'

@allowed(['S1', 'S2'])
param appServiceSku string = 'S1'

// Short unique suffix: site names are globally unique
var suffix = toLower(take(uniqueString(subscription().subscriptionId), 6))

var rgName      = 'rg-${projectName}-${environment}'
var apiAppName  = 'api-${projectName}-${environment}-${suffix}'
var webAppName  = 'web-${projectName}-${environment}-${suffix}'

var funcAppName = 'func-${projectName}-${environment}-${suffix}'
var storageName = take('st${projectName}${environment}${suffix}', 24)

// Blob container that receives the order request JSON files
var ordersContainerName = 'order-requests'

// Names are derived here (not read from module outputs) because the API needs the Web URL for CORS
// and the Web app needs the API URL; passing names in avoids an api <-> web dependency cycle.
var apiBaseUrl = 'https://${apiAppName}.azurewebsites.net/api/'
var webBaseUrl = 'https://${webAppName}.azurewebsites.net/'

// Route must match the [Function] HttpTrigger route in Azure.Functions.Worker
var orderItemsReserverUrl = 'https://${funcAppName}.azurewebsites.net/api/OrderItemsReserver'

var tags = {
  environment: environment
  project: projectName
  managedBy: 'bicep'
}

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: rgName
  location: location
  tags: tags
}

module plan 'modules/appservice-plan.bicep' = {
  name: 'deploy-plan'
  scope: rg
  params: {
    location: location
    projectName: projectName
    environment: environment
    sku: appServiceSku
    tags: tags
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-monitoring'
  scope: rg
  params: {
    location: location
    projectName: projectName
    environment: environment
    tags: tags
  }
}

module publicApi 'modules/publicApi.bicep' = {
  name: 'deploy-api'
  scope: rg
  params: {
    location: location
    apiAppName: apiAppName
    appServicePlanId: plan.outputs.planId
    webBaseUrl: webBaseUrl
    appInsightsConnectionString: monitoring.outputs.connectionString
    tags: union(tags, { component: 'api' })
  }
}

module storage 'modules/storage.bicep' = {
  name: 'deploy-storage'
  scope: rg
  params: {
    location: location
    storageAccountName: storageName
    ordersContainerName: ordersContainerName
    tags: union(tags, { component: 'storage' })
  }
}

module functionApp 'modules/functionApp.bicep' = {
  name: 'deploy-function'
  scope: rg
  params: {
    location: location
    functionAppName: funcAppName
    appServicePlanId: plan.outputs.planId
    storageAccountName: storage.outputs.storageAccountName
    ordersContainerName: storage.outputs.ordersContainerName
    appInsightsConnectionString: monitoring.outputs.connectionString
    tags: union(tags, { component: 'function' })
  }
}

module webApp 'modules/webApp.bicep' = {
  name: 'deploy-web'
  scope: rg
  params: {
    location: location
    webAppName: webAppName
    appServicePlanId: plan.outputs.planId
    apiBaseUrl: apiBaseUrl
    orderItemsReserverUrl: orderItemsReserverUrl
    tags: union(tags, { component: 'web' })
  }
}

output summary object = {
  resourceGroup: rgName
  publicApi: 'https://${publicApi.outputs.apiHostname}'
  web: 'https://${webApp.outputs.webAppHostname}'
  appInsights: monitoring.outputs.appInsightsName
  functionApp: 'https://${functionApp.outputs.functionHostname}'
  functionAppName: functionApp.outputs.functionAppName
  storageAccount: storage.outputs.storageAccountName
  ordersContainer: storage.outputs.ordersContainerName
}
