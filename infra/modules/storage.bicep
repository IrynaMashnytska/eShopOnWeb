targetScope = 'resourceGroup'

// One account serves two purposes: the Functions host runtime (AzureWebJobsStorage)
// and the blob container that receives the order request JSON files.

param location string

@description('Globally unique, 3-24 chars, lowercase letters and digits only')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Container that receives one JSON file per order')
param ordersContainerName string = 'order-requests'

param tags object = {}

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false   // Order files contain customer purchase data: never anonymous
    allowSharedKeyAccess: true     // Needed by the Functions host (AzureWebJobsStorage connection string)
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storage
  name: 'default'
}

resource ordersContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: ordersContainerName
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountId string   = storage.id
output storageAccountName string = storage.name
output blobEndpoint string       = storage.properties.primaryEndpoints.blob
output ordersContainerName string = ordersContainer.name
