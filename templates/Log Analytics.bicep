@description('Name of the Log Analytics workspace')
param workspaceName string

@description('Location')
param location string

@description('SKU (e.g., PerGB2018)')
param sku string = 'PerGB2018'

@description('Number of days to retain data')
param retentionInDays int = 30

@description('Access control mode')
@allowed([
  'WorkspaceBased'
  'ResourceBased'
])
param accessControlMode string = 'WorkspaceBased'

@description('Public network access for data ingestion')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccessForIngestion string = 'Enabled'

@description('Public network access for data query')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccessForQuery string = 'Enabled'

resource workspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: (accessControlMode == 'ResourceBased')
    }
    publicNetworkAccessForIngestion: publicNetworkAccessForIngestion
    publicNetworkAccessForQuery: publicNetworkAccessForQuery
  }
}
