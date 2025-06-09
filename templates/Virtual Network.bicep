@description('VNet name')
param vnetName string

@description('VNet Address prefix (e.g. 10.0.0.0/16)')
param vnetAddressPrefix string

@description('Subnet name')
param subnetName string

@description('Address prefix for the first subnet (e.g. 10.0.0.0/24)')
param subnetAddressPrefix string

@description('Location')
param location string

@description('Tags')
param tags object = {}

@description('Additional Subnets')
param additionalSubnets array = []

@description('Enable DDoS protection')
param enableDdosProtection bool = false

@description('DDoS protection plan ID (required if DDoS protection is enabled)')
param ddosProtectionPlanId string = ''

@description('Enable VM protection')
param enableVmProtection bool = false

@description('Enable DNS servers')
param enableDnsServers bool = false

@description('Custom DNS servers')
param dnsServers array = []

@description('Enable service endpoints')
param enableServiceEndpoints bool = false

@description('Service endpoints to enable')
@allowed([
  'Microsoft.AzureActiveDirectory'
  'Microsoft.AzureCosmosDB'
  'Microsoft.ContainerRegistry'
  'Microsoft.EventHub'
  'Microsoft.KeyVault'
  'Microsoft.ServiceBus'
  'Microsoft.Sql'
  'Microsoft.Storage'
  'Microsoft.Web'
])
param serviceEndpoints array = []

@description('Enable private endpoints')
param enablePrivateEndpoints bool = false

@description('Enable network policies')
param enableNetworkPolicies bool = false

var allSubnets = array(concat([
  {
    name: subnetName
    properties: {
      addressPrefix: subnetAddressPrefix
      serviceEndpoints: enableServiceEndpoints ? serviceEndpoints : []
      privateEndpointNetworkPolicies: enablePrivateEndpoints ? 'Enabled' : 'Disabled'
      networkSecurityGroup: enableNetworkPolicies ? {
        id: resourceId('Microsoft.Network/networkSecurityGroups', '${vnetName}-nsg')
      } : null
    }
  }
], additionalSubnets))

resource vnet 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: allSubnets
    enableDdosProtection: enableDdosProtection
    ddosProtectionPlan: enableDdosProtection ? {
      id: ddosProtectionPlanId
    } : null
    enableVmProtection: enableVmProtection
    dhcpOptions: enableDnsServers ? {
      dnsServers: dnsServers
    } : null
  }
}

// Create a default NSG for the subnet if network policies are enabled
resource nsg 'Microsoft.Network/networkSecurityGroups@2022-05-01' = if (enableNetworkPolicies) {
  name: '${vnetName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowVnetInBound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          description: 'Allow inbound traffic from VNet'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInBound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          description: 'Allow inbound traffic from Azure Load Balancer'
        }
      }
      {
        name: 'DenyAllInBound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          description: 'Deny all inbound traffic'
        }
      }
    ]
  }
  tags: tags
}
