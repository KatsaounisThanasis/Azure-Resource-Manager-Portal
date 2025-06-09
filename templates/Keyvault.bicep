@description('Key Vault name')
param vaultName string

@description('Location')
param location string

@description('Tenant ID')
param tenantId string

@description('Tags')
param tags object = {}

@description('SKU Name (standard ή premium)')
param skuName string = 'standard'

@description('SKU Family')
param skuFamily string = 'A'

@description('Access Policies')
param accessPolicies array = []

@description('Enable Soft Delete')
param enableSoftDelete bool = true

@description('Enable Purge Protection')
param enablePurgeProtection bool = false

resource kv 'Microsoft.KeyVault/vaults@2022-11-01' = {
  name: vaultName
  location: location
  properties: {
    tenantId: tenantId
    sku: {
      family: skuFamily
      name: skuName
    }
    accessPolicies: accessPolicies
    enabledForDeployment: true
    enableSoftDelete: enableSoftDelete
    enablePurgeProtection: enablePurgeProtection
  }
  tags: tags
}
