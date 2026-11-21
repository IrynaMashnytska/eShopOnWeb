targetScope = 'resourceGroup'

// Key Vault that holds the SQL connection strings as secrets. The Web app reads them through
// App Service Key Vault references, so the password never appears in the app's settings.
// Access policies (not RBAC) are used: the deployment principal has no
// Microsoft.Authorization/roleAssignments/write. The policy itself is in keyVaultAccessPolicy.bicep
// because it needs the Web app's managed identity, and the Web app needs the secret URIs from here.

param location string
param keyVaultName string

param sqlServerFqdn string
param catalogDbName string
param identityDbName string
param sqlAdminLogin string

@secure()
param sqlAdminPassword string

param tags object = {}

var sqlConnectionTemplate = 'Server=tcp:${sqlServerFqdn},1433;User ID=${sqlAdminLogin};Password=${sqlAdminPassword};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: false
    accessPolicies: []
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

resource catalogSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'CatalogConnection'
  properties: {
    value: '${sqlConnectionTemplate}Initial Catalog=${catalogDbName};'
  }
}

resource identitySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'IdentityConnection'
  properties: {
    value: '${sqlConnectionTemplate}Initial Catalog=${identityDbName};'
  }
}

output keyVaultName string = keyVault.name
// Version-less URIs: the app always resolves the latest version of the secret
output catalogSecretUri string = catalogSecret.properties.secretUri
output identitySecretUri string = identitySecret.properties.secretUri
