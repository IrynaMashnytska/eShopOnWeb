// infra/main.bicepparam
using './main.bicep'

param environment   = 'dev'
param projectName   = 'eshop'
param location      = 'westeurope'
param appServiceSku = 'S1'
param sqlLocation   = 'germanywestcentral'

// Never commit the password: the workflow supplies it from the SQL_ADMIN_PASSWORD secret
param sqlAdminPassword = readEnvironmentVariable('SQL_ADMIN_PASSWORD')
