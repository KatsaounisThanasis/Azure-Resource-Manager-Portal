@description('Network Security Group name')
param nsgName string

@description('Location')
param location string

@description('Tags for the resource')
param tags object = {}

@description('Security rules for the NSG')
param securityRules array = [
  {
    name: 'Allow-HTTP'
    properties: {
      priority: 100
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '80'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      description: 'Allow HTTP traffic'
    }
  }
  {
    name: 'Allow-HTTPS'
    properties: {
      priority: 110
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '443'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      description: 'Allow HTTPS traffic'
    }
  }
  {
    name: 'Allow-SSH'
    properties: {
      priority: 120
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '22'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      description: 'Allow SSH traffic'
    }
  }
  {
    name: 'Allow-RDP'
    properties: {
      priority: 130
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '3389'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      description: 'Allow RDP traffic'
    }
  }
  {
    name: 'Deny-All-Inbound'
    properties: {
      priority: 4096
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

@description('Default security rules for the NSG')
param defaultSecurityRules array = [
  {
    name: 'AllowVnetInBound'
    properties: {
      priority: 65000
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
      priority: 65001
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
      priority: 65500
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
  {
    name: 'AllowVnetOutBound'
    properties: {
      priority: 65000
      direction: 'Outbound'
      access: 'Allow'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: 'VirtualNetwork'
      destinationAddressPrefix: 'VirtualNetwork'
      description: 'Allow outbound traffic to VNet'
    }
  }
  {
    name: 'AllowInternetOutBound'
    properties: {
      priority: 65001
      direction: 'Outbound'
      access: 'Allow'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: 'Internet'
      description: 'Allow outbound traffic to Internet'
    }
  }
  {
    name: 'DenyAllOutBound'
    properties: {
      priority: 65500
      direction: 'Outbound'
      access: 'Deny'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      description: 'Deny all outbound traffic'
    }
  }
]

resource nsg 'Microsoft.Network/networkSecurityGroups@2022-09-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: securityRules
    defaultSecurityRules: defaultSecurityRules
  }
  tags: tags
}
