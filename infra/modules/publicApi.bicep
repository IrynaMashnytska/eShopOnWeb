targetScope = 'resourceGroup'

param location string
param projectName string
param environment string
param suffix string
param appServicePlanId string
param appServicePlanName string

@description('Public base URL the Web front end is served from, used as the CORS origin')
param webBaseUrl string

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

// Keeps prod names unchanged while separating dev/staging deployments in the same subscription
var envSuffix = environment == 'prod' ? '' : '-${environment}'

var apiAppName = 'api-${projectName}${envSuffix}-${suffix}'

resource apiApp 'Microsoft.Web/sites@2022-09-01' = {
  name: apiAppName
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true

    // Without this, App Service pins each client to the instance it first hit
    // via the ARRAffinity cookie. Scaling out then adds instances that get no
    // traffic from existing clients, so autoscale buys nothing for the users
    // already suffering. The Web app (modules/webApp.bicep) already sets this.
    clientAffinityEnabled: false
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
          value: 'true'           // No database is deployed: EF Core uses in-memory stores
        }
        {
          name: 'baseUrls__webBase'
          value: webBaseUrl        // Drives the app's own CORS policy; localhost otherwise
        }
        {
          name: 'baseUrls__apiBase'
          value: 'https://${apiAppName}.azurewebsites.net/api/'
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
//                ↓ After ~2 minutes (+ metric ingestion lag)
//                [Instance 1][Instance 2][Instance 3]  <- +2 at a time
//
// Load drops:    CPU: 25% < 30%
//                ↓ After ~5 minutes
//                [Instance 1][Instance 2]              <- -1 at a time
//
// IMPORTANT: Autoscale scales the PLAN (all apps in it). CpuPercentage is
// averaged across the plan's INSTANCES, and every app in the plan shares each
// instance's CPU - so a busy API raises the metric even when the Web app idles.
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
              timeWindow: 'PT2M'         // Short: this API saturates in seconds
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: cpuScaleOut     // Default: 70%
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '2'                 // Add 2 instances at once
              cooldown: 'PT3M'           // Enough for the new instances to absorb load
            }
          }

          // ── RULE 2: Scale IN when CPU low ────
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appServicePlanId
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'         // 2.5x the scale-out window - be sure before removing
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: cpuScaleIn      // Default: 30%
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'                 // Remove 1 at a time (cautious)
              cooldown: 'PT5M'           // Slower than scale-out, to avoid thrash
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
              timeWindow: 'PT2M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 10              // > 10 requests queued
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT3M'
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
