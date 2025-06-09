@description('Name of the VM Scale Set')
param vmssName string

@description('Location')
param location string = resourceGroup().location

@description('Number of instances')
param instanceCount int = 2

@description('Admin username')
param adminUsername string

@description('Admin password')
@secure()
param adminPassword string

@description('VM size')
param vmSize string = 'Standard_B1s'

@description('Operating System Type')
@allowed([
  'Windows'
  'Linux'
])
param osType string = 'Linux'

@description('OS Version')
param osVersion string = '18.04-LTS'

@description('OS Publisher')
param osPublisher string = 'Canonical'

@description('OS Offer')
param osOffer string = 'UbuntuServer'

@description('Enable managed identity')
param enableManagedIdentity bool = false

@description('Enable boot diagnostics')
param enableBootDiagnostics bool = true

@description('Storage account name for boot diagnostics')
param bootDiagnosticsStorageAccount string = ''

@description('Enable auto scaling')
param enableAutoScaling bool = false

@description('Minimum instance count for auto scaling')
param minInstanceCount int = 1

@description('Maximum instance count for auto scaling')
param maxInstanceCount int = 10

@description('Scale out CPU threshold percentage')
param scaleOutCPUThreshold int = 80

@description('Scale in CPU threshold percentage')
param scaleInCPUThreshold int = 20

@description('Scale out cooldown minutes')
param scaleOutCooldownMinutes int = 5

@description('Scale in cooldown minutes')
param scaleInCooldownMinutes int = 15

@description('VNET name')
param vnetName string = '${vmssName}-vnet'

@description('VNET address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet name')
param subnetName string = '${vmssName}-subnet'

@description('Subnet address prefix')
param subnetAddressPrefix string = '10.0.0.0/24'

@description('Enable accelerated networking')
param enableAcceleratedNetworking bool = false

@description('Enable IP forwarding')
param enableIPForwarding bool = false

@description('Enable network security group')
param enableNSG bool = false

@description('NSG rules')
param nsgRules array = []

@description('Custom data script')
param customData string = ''

@description('Tags')
param tags object = {}

// VNET Resource
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: enableNSG ? {
            id: nsg.id
          } : null
        }
      }
    ]
  }
}

// Network Security Group
resource nsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = if (enableNSG) {
  name: '${vmssName}-nsg'
  location: location
  properties: {
    securityRules: nsgRules
  }
}

// VMSS Resource
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2022-11-01' = {
  name: vmssName
  location: location
  tags: tags
  identity: enableManagedIdentity ? {
    type: 'SystemAssigned'
  } : null
  sku: {
    name: vmSize
    capacity: instanceCount
    tier: 'Standard'
  }
  properties: {
    upgradePolicy: {
      mode: 'Manual'
    }
    virtualMachineProfile: {
      storageProfile: {
        imageReference: {
          publisher: osPublisher
          offer: osOffer
          sku: osVersion
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'Standard_LRS'
          }
        }
      }
      osProfile: {
        computerNamePrefix: vmssName
        adminUsername: adminUsername
        adminPassword: adminPassword
        customData: customData != '' ? base64(customData) : null
        windowsConfiguration: osType == 'Windows' ? {
          enableAutomaticUpdates: true
          provisionVMAgent: true
        } : null
        linuxConfiguration: osType == 'Linux' ? {
          disablePasswordAuthentication: false
          provisionVMAgent: true
        } : null
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: '${vmssName}-nic'
            properties: {
              primary: true
              enableAcceleratedNetworking: enableAcceleratedNetworking
              enableIPForwarding: enableIPForwarding
              ipConfigurations: [
                {
                  name: '${vmssName}-ipconfig'
                  properties: {
                    subnet: {
                      id: vnet.properties.subnets[0].id
                    }
                    loadBalancerBackendAddressPools: []
                    applicationGatewayBackendAddressPools: []
                  }
                }
              ]
            }
          }
        ]
      }
      diagnosticsProfile: enableBootDiagnostics ? {
        bootDiagnostics: {
          enabled: true
          storageUri: bootDiagnosticsStorageAccount != '' ? reference(resourceId('Microsoft.Storage/storageAccounts', bootDiagnosticsStorageAccount)).primaryEndpoints.blob : null
        }
      } : null
    }
  }
  dependsOn: [
    vnet
    nsg
  ]
}

// Auto Scaling Settings
resource autoscaleSettings 'Microsoft.Insights/autoscalesettings@2022-10-01' = if (enableAutoScaling) {
  name: '${vmssName}-autoscale'
  location: location
  properties: {
    profiles: [
      {
        name: 'defaultProfile'
        capacity: {
          minimum: minInstanceCount
          maximum: maxInstanceCount
          default: instanceCount
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: scaleOutCPUThreshold
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT${scaleOutCooldownMinutes}M'
            }
          }
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: scaleInCPUThreshold
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT${scaleInCooldownMinutes}M'
            }
          }
        ]
      }
    ]
    targetResourceUri: vmss.id
  }
}

output vmssId string = vmss.id
output vmssName string = vmss.name
output vmssPrincipalId string = enableManagedIdentity ? vmss.identity.principalId : null
output vnetId string = vnet.id
output subnetId string = vnet.properties.subnets[0].id
