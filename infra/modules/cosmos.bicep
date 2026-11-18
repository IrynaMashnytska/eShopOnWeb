targetScope = 'resourceGroup'

// Cosmos DB (NoSQL API, serverless) that holds the orders the delivery department processes.
// Written by the DeliveryOrderProcessor function, read by the delivery department's own tooling.

param location string

@description('Globally unique, 3-44 chars, lowercase letters, digits and hyphens')
@minLength(3)
@maxLength(44)
param cosmosAccountName string

param databaseName string
param containerName string

param tags object = {}

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    capabilities: [
      { name: 'EnableServerless' }   // pay per request: the sample has little traffic
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    minimalTlsVersion: 'Tls12'
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: account
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

// Partitioned by orderId: each order is written once and read by id, so a point read costs 1 RU
resource ordersContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: database
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [ '/orderId' ]
        kind: 'Hash'
        version: 2
      }
    }
  }
}

output cosmosAccountName string = account.name
output cosmosEndpoint string    = account.properties.documentEndpoint
output databaseName string      = database.name
output containerName string     = ordersContainer.name
