@description('The name of the diagnostic setting')
param diagName string

@description('Resource ID of the target resource')
param targetResourceId string

@description('Log Analytics workspace ID')
param workspaceId string

@description('Enable or disable retention policy')
param enableRetention bool = false

@description('Number of days to retain logs')
@minValue(0)
@maxValue(365)
param retentionInDays int = 0

// var resourceName = last(split(targetResourceId, '/')) // No longer needed

// resource targetResource 'Microsoft.Storage/storageAccounts@2022-09-01' existing = {
//   name: resourceName
// } // No longer needed

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagName
  // scope is inherited from the deployment scope when targetResourceId is used
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'Transaction' // This category is specific to Storage Accounts. Need to make this dynamic or add more categories.
        enabled: true
        retentionPolicy: {
          enabled: enableRetention
          days: retentionInDays
        }
      }
    ]
  }
}
