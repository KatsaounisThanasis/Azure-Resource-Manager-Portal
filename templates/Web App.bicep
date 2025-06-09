@description('The name of the web app')
param webAppName string

@description('The location for the web app')
param location string = resourceGroup().location

@description('The SKU of the app service plan')
param skuName string = 'F1'

@description('The kind of the app service plan')
param kind string = 'Windows'

@description('Application settings for the web app')
param appSettings array = [
  {
    name: 'WEBSITE_NODE_DEFAULT_VERSION'
    value: '~18'
  }
  {
    name: 'WEBSITE_RUN_FROM_PACKAGE'
    value: '1'
  }
]

@description('Connection strings for the web app')
param connectionStrings array = [
  {
    name: 'DefaultConnection'
    type: 'SQLAzure'
    connectionString: 'Server=myserver;Database=mydb;User Id=myuser;Password=mypassword;'
  }
]

@description('Enable HTTPS only')
param httpsOnly bool = true

@description('Minimum TLS version')
@allowed([
  '1.0'
  '1.1'
  '1.2'
])
param minTlsVersion string = '1.2'

@description('Enable VNET integration')
param enableVnetIntegration bool = false

@description('VNET name for integration')
param vnetName string = ''

@description('Subnet name for VNET integration')
param subnetName string = ''

@description('Enable diagnostic settings')
param enableDiagnostics bool = false

@description('Storage account name for diagnostics')
param storageAccountName string = ''

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2021-02-01' = {
  name: '${webAppName}-plan'
  location: location
  sku: {
    name: skuName
  }
  kind: kind
}

// Web App
resource webApp 'Microsoft.Web/sites@2021-02-01' = {
  name: webAppName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: httpsOnly
    siteConfig: {
      appSettings: appSettings
      connectionStrings: connectionStrings
      minTlsVersion: minTlsVersion
      netFrameworkVersion: 'v4.0'
      phpVersion: '7.4'
      pythonVersion: '3.9'
      nodeVersion: '~18'
    }
  }
}

// VNET Integration if enabled
resource vnetIntegration 'Microsoft.Web/sites/config@2021-02-01' = if (enableVnetIntegration) {
  parent: webApp
  name: 'web'
  properties: {
    vnetName: vnetName
    vnetRouteAllEnabled: true
  }
}

// Diagnostic Settings if enabled and storage account is provided
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics && storageAccountName != '') {
  name: '${webAppName}-diagnostics'
  scope: webApp
  properties: {
    storageAccountId: resourceId('Microsoft.Storage/storageAccounts', storageAccountName)
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
  }
}

output webAppId string = webApp.id
output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
