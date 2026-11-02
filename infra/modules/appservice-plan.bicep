targetScope = 'resourceGroup'

param location string
param projectName string
param environment string

@description('App Service SKU')
@allowed(['S1', 'S2', 'S3'])
param sku string = 'S1'

param tags object = {}

var skuTierMap = {
  S1: 'Standard'
  S2: 'Standard'
  S3: 'Standard'
}

resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: 'plan-${projectName}-${environment}'
  location: location
  tags: tags
  sku: {
    name: sku
    tier: skuTierMap[sku]
    capacity: 1
  }
  properties: {
    reserved: false              // Windows
  }
}

output planId string   = appServicePlan.id
output planName string = appServicePlan.name
