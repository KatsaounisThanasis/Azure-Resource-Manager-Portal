@description('Cosmos DB account name')
param cosmosDbAccountName string

@description('Location')
param location string

@description('API kind (e.g., SQL, MongoDB, Cassandra, Gremlin, Table)')
@allowed([
  'Sql'
  'MongoDB'
  'Cassandra'
  'Gremlin'
  'Table'
])
param apiKind string = 'Sql'

@description('Cosmos DB capacity mode (Provisioned or Serverless)')
@allowed([
  'Provisioned'
  'Serverless'
])
param capacityMode string = 'Provisioned'

@description('Enable Zone Redundancy')
param enableZoneRedundancy bool = false

@description('Public network access (Enabled or Disabled)')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Default consistency level')
@allowed([
  'Eventual'
  'ConsistentPrefix'
  'Session'
  'BoundedStaleness'
  'Strong'
])
param defaultConsistencyLevel string = 'Session'

var armApiKind = (apiKind == 'Sql') ? 'GlobalDocumentDB' : apiKind
var databaseAccountOfferType = (capacityMode == 'Provisioned') ? 'Standard' : null // Serverless doesn't use databaseAccountOfferType

resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosDbAccountName
  location: location
  kind: armApiKind
  properties: {
    databaseAccountOfferType: databaseAccountOfferType
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: enableZoneRedundancy
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: defaultConsistencyLevel
      // You might need additional properties for BoundedStaleness or Strong consistency levels
      // based on the chosen defaultConsistencyLevel. Add them here if needed.
    }
    publicNetworkAccess: publicNetworkAccess
  }
}
