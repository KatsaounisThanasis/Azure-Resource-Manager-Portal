@description('Name of the Load Balancer')
param lbName string

@description('Location')
param location string

@description('Public IP address ID to associate')
param publicIpId string

@description('Load Balancer SKU (Basic or Standard)')
@allowed([
  'Basic'
  'Standard'
])
param skuName string = 'Basic'

@description('Health Probe Protocol')
@allowed([
  'Tcp'
  'Http'
  'Https'
])
param probeProtocol string = 'Tcp'

@description('Health Probe Port')
param probePort int = 80

resource lb 'Microsoft.Network/loadBalancers@2022-05-01' = {
  name: lbName
  location: location
  sku: {
    name: skuName
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'LoadBalancerFrontEnd'
        properties: {
          publicIPAddress: {
            id: publicIpId
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'BackendPool'
      }
    ]
    probes: [
      {
        name: 'HealthProbe'
        properties: {
          protocol: probeProtocol
          port: probePort
          requestPath: (probeProtocol == 'Http' || probeProtocol == 'Https') ? '/' : null
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'HttpRule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'LoadBalancerFrontEnd')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'BackendPool')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'HealthProbe')
          }
        }
      }
    ]
  }
}
