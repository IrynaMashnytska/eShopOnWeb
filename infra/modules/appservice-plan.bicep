targetScope = 'resourceGroup'


param location string
param projectName string
param environment string

@description('Short region code: eus, weu')
param regionShort string

@description('App Service SKU - S1 minimum for deployment slots')
@allowed(['S1', 'S2', 'S3'])
param sku string = 'S1'

param tags object = {}

var skuTierMap = {
  S1: 'Standard'
  S2: 'Standard'
  S3: 'Standard'
}


var planName = 'plan-${projectName}-${regionShort}-${environment}'


resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: planName
  location: location
  tags: tags
  sku: {
    name: sku                    
    tier: skuTierMap[sku]        
    capacity: 1               
  }
  properties: {
    reserved: false              // false = Windows OS
                                 // true  = Linux OS
  }
}

output planId string   = appServicePlan.id
output planName string = appServicePlan.name