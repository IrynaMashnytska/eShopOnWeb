// infra/main.bicep
// Single environment: one resource group (rg-eshop-dev) holding one App Service plan, the Public API,
// the Web app, Application Insights, the Azure SQL server with the catalog and identity databases, and a
// Key Vault that stores the SQL connection strings. The Web app reads them via Key Vault references.

targetScope = 'subscription'

@allowed(['dev'])
param environment string = 'dev'

param projectName string = 'eshop'

param location string = 'westeurope'

@allowed(['S1', 'S2'])
param appServiceSku string = 'S1'

// SQL has its own region because this subscription cannot provision SQL in westeurope ("ProvisioningDisabled").
// Check a region for SQL with:
//   az rest --method get --url ".../providers/Microsoft.Sql/locations/<region>/capabilities?api-version=2021-11-01"
@description('Region for the Azure SQL server and databases')
param sqlLocation string = 'germanywestcentral'

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

// Key Vault names are 3-24 characters and globally unique
var keyVaultName = take('kv-${projectName}-${environment}-${suffix}', 24)

// The region is part of the name: a resource name cannot be reused in another region, so changing the
// region after a failed or unwanted deployment gets a fresh name instead of a conflict.
var sqlServerName = 'sql-${projectName}-${environment}-${suffix}-${sqlLocation}'

var catalogDbName  = 'CatalogDb'
var identityDbName = 'IdentityDb'

// Names are derived here (not read from module outputs) because the API needs the Web URL for CORS
// and the Web app needs the API URL; passing names in avoids an api <-> web dependency cycle.
var apiBaseUrl = 'https://${apiAppName}.azurewebsites.net/api/'
var webBaseUrl = 'https://${webAppName}.azurewebsites.net/'

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
    location: sqlLocation
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

module keyVault 'modules/keyVault.bicep' = {
  name: 'deploy-keyvault'
  scope: rg
  params: {
    location: location
    keyVaultName: keyVaultName
    sqlServerFqdn: sql.outputs.sqlServerFqdn
    catalogDbName: sql.outputs.catalogDbName
    identityDbName: sql.outputs.identityDbName
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    tags: union(tags, { component: 'keyvault' })
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
    catalogConnectionSecretUri: keyVault.outputs.catalogSecretUri
    identityConnectionSecretUri: keyVault.outputs.identitySecretUri
    tags: union(tags, { component: 'web' })
  }
}

// Separate from the vault module: it needs the Web app's managed identity, which exists only after the
// Web app is deployed, and the Web app needs the secret URIs from the vault module.
module webAppKeyVaultAccess 'modules/keyVaultAccessPolicy.bicep' = {
  name: 'deploy-web-keyvault-access'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    principalId: webApp.outputs.webAppPrincipalId
  }
}

output summary object = {
  resourceGroup: rgName
  publicApi: 'https://${publicApi.outputs.apiHostname}'
  web: 'https://${webApp.outputs.webAppHostname}'
  appInsights: monitoring.outputs.appInsightsName
  sqlServer: sql.outputs.sqlServerFqdn
  sqlDatabases: [ sql.outputs.catalogDbName, sql.outputs.identityDbName ]
  keyVault: keyVault.outputs.keyVaultName
}
