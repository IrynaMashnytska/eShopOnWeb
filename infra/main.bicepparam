// infra/main.bicepparam
using './main.bicep'

param environment        = 'prod'
param projectName        = 'eshop'
param locationEastUS     = 'eastus'
param locationWestEU     = 'westeurope'
param appServiceSku      = 'S1'

// Public API autoscale; apiMinInstances is also the West EU plan's deployed capacity
param apiMinInstances    = 1
param apiMaxInstances    = 5
param apiCpuScaleOut     = 70
param apiCpuScaleIn      = 30
