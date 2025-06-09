@description('Name of the Function App')
param functionAppName string

@description('Location for the Function App and related resources.')
param location string

@description('Name for the App Service Plan')
param planName string

@description('Name of an existing Storage account to be used by the Function App.')
param storageAccountName string

@description('Runtime stack (e.g., node, dotnet, python)')
param runtime string = 'node'

@description('Operating System for the Function App and Plan.')
@allowed([
  'Linux'
  'Windows'
])
param os string = 'Linux'

@description('Type of Hosting Plan.')
@allowed([
  'Consumption'
  'ElasticPremium'
  'Dedicated'
])
param hostingPlanType string = 'Consumption'

@description('SKU Name for the App Service Plan. Examples: Y1 (Consumption), EP1 (ElasticPremium), S1 (Dedicated)')
param planSkuName string = (hostingPlanType == 'Consumption') ? 'Y1' : (hostingPlanType == 'ElasticPremium') ? 'EP1' : 'S1'

@description('SKU Tier for the App Service Plan. Examples: Dynamic (Consumption), ElasticPremium (ElasticPremium), Standard (Dedicated)')
param planSkuTier string = (hostingPlanType == 'Consumption') ? 'Dynamic' : (hostingPlanType == 'ElasticPremium') ? 'ElasticPremium' : 'Standard'

@description('Tags for the Function App and related resources.')
param tags object = {}

@description('Enable Application Insights for monitoring.')
param enableApplicationInsights bool = true

@description('Name for the Application Insights resource (required if enabled).')
param applicationInsightsName string = '${functionAppName}-ai'

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: planName
  location: location
  sku: {
    name: planSkuName
    tier: planSkuTier
  }
  kind: os
  tags: tags
  properties: {
    // Additional plan properties based on tier might be needed here for advanced scenarios
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'IbizaAIExtension'
  }
  tags: tags
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: (os == 'Linux') ? 'functionapp,linux' : 'functionapp'
  properties: {
    reserved: (os == 'Linux') ? true : false
    serverFarmId: plan.id
    siteConfig: {
      linuxFxVersion: (os == 'Linux') ? '${runtime == 'python' ? 'PYTHON|3.12' : runtime == 'node' ? 'NODE|18' : runtime == 'dotnet' ? 'DOTNET|6.0' : ''}' : null
      windowsFxVersion: (os == 'Windows') ? '${runtime == 'dotnet' ? 'dotnet|6.0' : runtime == 'node' ? 'node|16' : runtime == 'python' ? 'python|3.9' : ''}' : null
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: '@Microsoft.Storage accounts/${storageAccountName}.connectionString'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: runtime
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: enableApplicationInsights ? '~2' : ''
        }
      ]
    }
    functionAppConfig: {
      runtime: {
        name: runtime
        version: (runtime == 'python') ? '3.12' : (runtime == 'node') ? '18' : (runtime == 'dotnet') ? '6.0' : ''
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '@Microsoft.Storage accounts/${storageAccountName}.connectionString'
          authentication: {
            type: 'SystemAssignedIdentity' // Assuming SystemAssignedIdentity based on typical Flex Consumption examples
          }
        }
      }
    }
  }
  dependsOn: [ plan, applicationInsights ]
}

output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output planId string = plan.id
output applicationInsightsId string = enableApplicationInsights ? applicationInsights.id : ''
