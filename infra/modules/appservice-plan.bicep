targetScope = 'resourceGroup'


param location string
param projectName string
param environment string

@description('Short region code: eus, weu')
param regionShort string

@description('App Service SKU - S1 minimum for deployment slots')
@allowed(['S1', 'S2', 'S3'])
param sku string = 'S1'

@description('Instance count to deploy the plan with. For a plan under an autoscale rule, pass the autoscale minimum so a redeploy cannot contradict the rule.')
@minValue(1)
param capacity int = 1

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
    capacity: capacity           // Autoscale owns this at runtime; see the note in main.bicep
  }
  properties: {
    reserved: false              // false = Windows OS
                                 // true  = Linux OS
  }
}

output planId string   = appServicePlan.id
output planName string = appServicePlan.name