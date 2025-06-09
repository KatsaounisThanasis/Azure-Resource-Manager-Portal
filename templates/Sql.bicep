@description('The name of the SQL server.')
param serverName string

@description('The administrator login username for the SQL server.')
param adminUsername string

@description('The administrator login password for the SQL server.')
@secure()
param adminPassword string

@description('The name of the SQL database.')
param databaseName string

@description('The location for the SQL server and database.')
param location string

@description('The edition of the SQL database.')
param edition string = 'Basic'

@description('The maximum size of the database in GB.')
param maxSizeGB int = 2

resource sqlServer 'Microsoft.Sql/servers@2021-11-01' = {
  name: serverName
  location: location
  properties: {
    administratorLogin: adminUsername
    administratorLoginPassword: adminPassword
  }
}

resource sqlDb 'Microsoft.Sql/servers/databases@2021-11-01' = {
  parent: sqlServer
  name: databaseName
  location: location
  sku: {
    name: edition
  }
  properties: {
    maxSizeBytes: maxSizeGB * 1024 * 1024 * 1024 // Convert GB to bytes
  }
}
