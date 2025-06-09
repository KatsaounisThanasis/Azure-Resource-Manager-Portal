@description('The name of the AKS cluster.')
param aksClusterName string

@description('The location for the AKS cluster.')
param location string = resourceGroup().location

@description('The desired number of agent nodes in the default node pool.')
param agentCount int = 3

@description('The size of the Virtual Machines for the agent nodes.')
param agentVmSize string = 'Standard_DS2_v2'

@description('The Kubernetes version.')
param kubernetesVersion string = '1.32.4'

@description('Enable RBAC for Kubernetes authorization.')
param enableRbac bool = true

resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-10-01' = {
  name: aksClusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: aksClusterName
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: agentCount
        vmSize: agentVmSize
        mode: 'System'
        osType: 'Linux'
      }
    ]
    enableRbac: enableRbac
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    networkProfile: {
      networkPlugin: 'kubenet'
      loadBalancerSku: 'basic'
      networkPolicy: 'calico'
    }
  }
}

output aksClusterName string = aksCluster.name
output aksClusterId string = aksCluster.id 
