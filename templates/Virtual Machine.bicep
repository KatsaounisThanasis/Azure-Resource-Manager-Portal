@description('The name of the virtual machine')
param vmName string

@description('The location for the virtual machine')
param location string = resourceGroup().location

@description('The size of the virtual machine')
param vmSize string = 'Standard_D2s_v3'

@description('The admin username for the virtual machine')
param adminUsername string

@description('The admin password for the virtual machine')
@secure()
param adminPassword string

@description('The operating system type for the virtual machine')
@allowed([
  'Windows'
  'Linux'
])
param osType string = 'Windows'

@description('Image Publisher for the VM')
param imagePublisher string = (osType == 'Windows') ? 'MicrosoftWindowsServer' : 'Canonical'

@description('Image Offer for the VM')
param imageOffer string = (osType == 'Windows') ? 'WindowsServer' : 'UbuntuServer'

@description('Image SKU for the VM')
param imageSku string = (osType == 'Windows') ? '2019-Datacenter' : '18.04-LTS'

@description('Image Version for the VM')
param imageVersion string = 'latest'

@description('Tags for all resources')
param tags object = {}

@description('Public IP allocation method')
@allowed([
  'Dynamic'
  'Static'
])
param publicIpAllocationMethod string = 'Dynamic'

@description('NSG rules (array of rules, optional)')
param nsgRules array = [
  {
    name: 'AllowRDP'
    properties: {
      priority: 1000
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '3389'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      description: 'Allow RDP'
    }
  }
]

resource publicIp 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: '${vmName}-pip'
  location: location
  tags: tags
  properties: {
    publicIPAllocationMethod: publicIpAllocationMethod
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: '${vmName}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: nsgRules
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: '${vmName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: '${vmName}-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: vmName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSku
        version: imageVersion
      }
    }
  }
}

output vmId string = virtualMachine.id
output vmName string = virtualMachine.name
output nsgId string = nsg.id
