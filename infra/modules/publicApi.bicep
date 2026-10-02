targetScope = 'resourceGroup'

param location string
param projectName string
param suffix string
param appServicePlanId string
param appServicePlanName string

// ── AUTOSCALE PARAMETERS ──────────────────────
// These control when scaling happens
// Good defaults, can be overridden

@description('Minimum number of instances')
@minValue(1)
param minInstances int = 1

@description('Maximum number of instances')
@maxValue(10)
param maxInstances int = 5

@description('CPU % to trigger scale OUT')
param cpuScaleOut int = 70

@description('CPU % to trigger scale IN')
param cpuScaleIn int = 30

param tags object = {}

// ──────────────────────────────────────────────
// VARIABLES
// ──────────────────────────────────────────────

var apiAppName = 'api-${projectName}-${suffix}'

resource apiApp 'Microsoft.Web/sites@2022-09-01' = {
  name: apiAppName
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      alwaysOn: true

      // ── CORS ────────────────────────────────
      // API needs to allow calls from Web Apps
      cors: {
        allowedOrigins: [ '*' ]      // Lock down in production!
        supportCredentials: false
      }

      appSettings: [
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Production'
        }
        {
          name: 'UseOnlyInMemoryDatabase'
          value: 'true'
        }
      ]
    }
  }
}

// ──────────────────────────────────────────────
// AUTO-SCALE SETTINGS
//
// HOW AUTOSCALE WORKS:
//
// Normal load:   [Instance 1]
//                CPU: 20% ← below 70%, no action
//
// High load:     [Instance 1] CPU: 80% > 70%
//                ↓ After 5 minutes
//                [Instance 1][Instance 2] added!
//
// Load drops:    CPU: 25% < 30%
//                ↓ After 10 minutes
//                [Instance 1] removed!
//
// IMPORTANT: Autoscale scales the PLAN (all apps in it)
// ──────────────────────────────────────────────

resource autoscale 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: 'autoscale-${apiAppName}'
  location: location
  tags: tags
  properties: {
    enabled: true
    name: 'autoscale-${apiAppName}'
    targetResourceUri: appServicePlanId    // Scale the PLAN
    targetResourceLocation: location

    profiles: [
      {
        name: 'Default'
        capacity: {
          minimum: string(minInstances)    // int → string required!
          maximum: string(maxInstances)
          default: string(minInstances)
        }

        rules: [
          // ── RULE 1: Scale OUT when CPU high ──
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appServicePlanId
              timeGrain: 'PT1M'          // Check every 1 minute
              statistic: 'Average'       // Average across instances
              timeWindow: 'PT5M'         // Over 5 minute window
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: cpuScaleOut     // Default: 70%
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '2'                 // Add 2 instances at once
              cooldown: 'PT5M'           // Wait 5min before scaling again
            }
          }

          // ── RULE 2: Scale IN when CPU low ────
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appServicePlanId
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'        // Longer window - be sure before removing
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: cpuScaleIn      // Default: 30%
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'                 // Remove 1 at a time (cautious)
              cooldown: 'PT10M'          // Wait 10min between scale-in
            }
          }

          // ── RULE 3: Scale OUT on HTTP Queue ──
          // When requests pile up waiting
          {
            metricTrigger: {
              metricName: 'HttpQueueLength'
              metricResourceUri: appServicePlanId
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 10              // > 10 requests queued
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
        ]
      }
    ]
  }
}

output apiAppId string      = apiApp.id
output apiAppName string    = apiApp.name
output apiHostname string   = apiApp.properties.defaultHostName
output autoscaleName string = autoscale.name
