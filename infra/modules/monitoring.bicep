targetScope = 'resourceGroup'

// ──────────────────────────────────────────────
// APPLICATION INSIGHTS (+ LOG ANALYTICS)
//
// Classic Application Insights components are retired: a component must now be
// workspace-based, so the Log Analytics workspace is created here and the
// component points at it. Both telemetry and logs therefore land in one
// workspace and are queryable with KQL from either blade.
//
// Lives in the shared resource group so the Web apps in both regions can report
// into the same component later. Cross-region ingestion (component in East US,
// API in West Europe) is supported and adds only ingest latency, not a hard
// dependency on the region staying up.
// ──────────────────────────────────────────────

param location string
param projectName string
param environment string

@description('Days to retain telemetry. 30 is the free-tier allowance; beyond that is billed.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Daily ingestion cap in GB. Guards against a load test running up a bill; telemetry is dropped for the rest of the UTC day once hit.')
param dailyQuotaInGB int = 1

param tags object = {}

// Keeps prod names unchanged while separating dev/staging in the same subscription
var envSuffix = environment == 'prod' ? '' : '-${environment}'

var workspaceName = 'log-${projectName}${envSuffix}'
var appInsightsName = 'appi-${projectName}${envSuffix}'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaInGB
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    IngestionMode: 'LogAnalytics'
    RetentionInDays: retentionInDays

    // Connection string only. The instrumentation key path is deprecated and the
    // SDK is configured through APPLICATIONINSIGHTS_CONNECTION_STRING instead.
    DisableLocalAuth: false
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name

@description('Value for the APPLICATIONINSIGHTS_CONNECTION_STRING app setting')
#disable-next-line outputs-should-not-contain-secrets
output connectionString string = appInsights.properties.ConnectionString

output workspaceId string = workspace.id
output workspaceName string = workspace.name
