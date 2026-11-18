// infra/main.bicep
// Single environment, single region: one resource group (rg-eshop-dev) holding one App Service plan,
// the Public API, the Web app, Application Insights, the Azure SQL server with the catalog and identity
// databases, the OrderItemsReserver Function App with the Storage account that holds the order request blobs,
// and the DeliveryOrderProcessor Function App with the Cosmos DB account that holds the delivery orders.

targetScope = 'subscription'

@allowed(['dev'])
param environment string = 'dev'

param projectName string = 'eshop'

param location string = 'westeurope'

@allowed(['S1', 'S2'])
param appServiceSku string = 'S1'

@description('Azure SQL administrator login')
param sqlAdminLogin string = 'eshopadmin'

@description('Azure SQL administrator password (8-128 chars, 3 of: upper, lower, digit, symbol). Avoid ; and quotes: it is embedded in connection strings.')
@secure()
param sqlAdminPassword string

// Short unique suffix: site names are globally unique
var suffix = toLower(take(uniqueString(subscription().subscriptionId), 6))

var rgName      = 'rg-${projectName}-${environment}'
var apiAppName  = 'api-${projectName}-${environment}-${suffix}'
var webAppName  = 'web-${projectName}-${environment}-${suffix}'

var funcAppName = 'func-${projectName}-${environment}-${suffix}'
var storageName = take('st${projectName}${environment}${suffix}', 24)

// Prefix 'func-delivery' (not 'func-eshop') so the deploy workflows can tell the two function apps apart by name
var deliveryFuncAppName = 'func-delivery-${projectName}-${environment}-${suffix}'
var sqlServerName       = 'sql-${projectName}-${environment}-${suffix}'
var cosmosAccountName   = 'cosmos-${projectName}-${environment}-${suffix}'

var catalogDbName  = 'CatalogDb'
var identityDbName = 'IdentityDb'

var cosmosDatabaseName  = 'delivery'
var cosmosContainerName = 'orders'

// Blob container that receives the order request JSON files
var ordersContainerName = 'order-requests'

// Names are derived here (not read from module outputs) because the API needs the Web URL for CORS
// and the Web app needs the API URL; passing names in avoids an api <-> web dependency cycle.
var apiBaseUrl = 'https://${apiAppName}.azurewebsites.net/api/'
var webBaseUrl = 'https://${webAppName}.azurewebsites.net/'

// Route must match the [Function] HttpTrigger route in Azure.Functions.Worker
var orderItemsReserverUrl = 'https://${funcAppName}.azurewebsites.net/api/OrderItemsReserver'

// Route must match the [Function] HttpTrigger route in Azure.Functions.DeliveryOrderProcessor
var deliveryOrderProcessorUrl = 'https://${deliveryFuncAppName}.azurewebsites.net/api/DeliveryOrderProcessor'

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

module sql 'modules/sql.bicep' = {
  name: 'deploy-sql'
  scope: rg
  params: {
    location: location
    sqlServerName: sqlServerName
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    catalogDbName: catalogDbName
    identityDbName: identityDbName
    tags: union(tags, { component: 'sql' })
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
    sqlServerFqdn: sql.outputs.sqlServerFqdn
    catalogDbName: sql.outputs.catalogDbName
    identityDbName: sql.outputs.identityDbName
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
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

module cosmos 'modules/cosmos.bicep' = {
  name: 'deploy-cosmos'
  scope: rg
  params: {
    location: location
    cosmosAccountName: cosmosAccountName
    databaseName: cosmosDatabaseName
    containerName: cosmosContainerName
    tags: union(tags, { component: 'cosmos' })
  }
}

module deliveryFunctionApp 'modules/deliveryFunctionApp.bicep' = {
  name: 'deploy-delivery-function'
  scope: rg
  params: {
    location: location
    functionAppName: deliveryFuncAppName
    appServicePlanId: plan.outputs.planId
    storageAccountName: storage.outputs.storageAccountName
    cosmosAccountName: cosmos.outputs.cosmosAccountName
    cosmosDatabaseName: cosmos.outputs.databaseName
    cosmosContainerName: cosmos.outputs.containerName
    appInsightsConnectionString: monitoring.outputs.connectionString
    tags: union(tags, { component: 'delivery-function' })
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
    deliveryOrderProcessorUrl: deliveryOrderProcessorUrl
    sqlServerFqdn: sql.outputs.sqlServerFqdn
    catalogDbName: sql.outputs.catalogDbName
    identityDbName: sql.outputs.identityDbName
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
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
  deliveryFunctionApp: 'https://${deliveryFunctionApp.outputs.functionHostname}'
  deliveryFunctionAppName: deliveryFunctionApp.outputs.functionAppName
  sqlServer: sql.outputs.sqlServerFqdn
  sqlDatabases: [ sql.outputs.catalogDbName, sql.outputs.identityDbName ]
  cosmosAccount: cosmos.outputs.cosmosAccountName
  cosmosDatabase: cosmos.outputs.databaseName
  cosmosContainer: cosmos.outputs.containerName
}
