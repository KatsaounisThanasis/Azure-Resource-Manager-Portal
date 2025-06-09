@description('The name of the storage account')
param storageAccountName string

@description('The location for the storage account')
param location string = resourceGroup().location

@description('The type of the storage account (SKU)')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Standard_GZRS'
  'Standard_RAGZRS'
  'Premium_LRS'
  'Premium_ZRS'
])
param storageAccountType string = 'Standard_LRS'

@description('Tags for the storage account')
param tags object = {}

@description('Allow blob public access')
param allowBlobPublicAccess bool = false

@description('Minimum TLS version required')
@allowed([
  'TLS1_0'
  'TLS1_1'
  'TLS1_2'
])
param minimumTlsVersion string = 'TLS1_2'

@description('Enable hierarchical namespace for Data Lake Storage Gen2')
param isHnsEnabled bool = false

@description('Enable SFTP support')
param isSftpEnabled bool = false

@description('Enable NFS v3 protocol support')
param isNfsV3Enabled bool = false

@description('Enable soft delete for blobs')
param enableBlobSoftDelete bool = false

@description('Blob soft delete retention period in days (1-365)')
@minValue(1)
@maxValue(365)
param blobSoftDeleteRetentionInDays int = 7

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: allowBlobPublicAccess
    minimumTlsVersion: minimumTlsVersion
    isHnsEnabled: isHnsEnabled
    isSftpEnabled: isSftpEnabled
    isNfsV3Enabled: isNfsV3Enabled
  }
}

resource storageAccount_blobServices 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    containerDeleteRetentionPolicy: {
      enabled: enableBlobSoftDelete
      days: enableBlobSoftDelete ? blobSoftDeleteRetentionInDays : null
    }
    deleteRetentionPolicy: {
       enabled: enableBlobSoftDelete
       days: enableBlobSoftDelete ? blobSoftDeleteRetentionInDays : null
    }
  }
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
