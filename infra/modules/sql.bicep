targetScope = 'resourceGroup'

// Azure SQL logical server with the two databases eShopOnWeb uses (catalog + identity).
// Tables are not created here: the apps apply their EF Core migrations at startup.

param location string
param sqlServerName string

@description('SQL administrator login. Reserved names such as admin, sa and root are rejected by Azure.')
param sqlAdminLogin string

@secure()
param sqlAdminPassword string

param catalogDbName string
param identityDbName string

param tags object = {}

resource sqlServer 'Microsoft.Sql/servers@2021-11-01' = {
  name: sqlServerName
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// 0.0.0.0 - 0.0.0.0 is the special range that lets Azure-hosted services (the App Services) connect
resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2021-11-01' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Basic (5 DTU, 2 GB) is enough for the sample data. Unlike serverless it never auto-pauses,
// so the migrations that run at app startup do not hit a paused database.
resource catalogDb 'Microsoft.Sql/servers/databases@2021-11-01' = {
  parent: sqlServer
  name: catalogDbName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    maxSizeBytes: 2147483648
  }
}

resource identityDb 'Microsoft.Sql/servers/databases@2021-11-01' = {
  parent: sqlServer
  name: identityDbName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    maxSizeBytes: 2147483648
  }
}

output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output catalogDbName string = catalogDb.name
output identityDbName string = identityDb.name
