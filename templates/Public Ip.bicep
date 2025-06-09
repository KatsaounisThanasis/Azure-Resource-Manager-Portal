@description('Public IP name')
param publicIpName string

@description('Location')
param location string

@description('SKU of the public IP. Basic or Standard')
@allowed([
  'Basic'
  'Standard'
])
param sku string = 'Basic'

@description('Tier of the public IP. Regional or Global')
@allowed([
  'Regional'
  'Global'
])
param tier string = 'Regional'

@description('IP Version')
@allowed([
  'IPv4'
  'IPv6'
])
param ipVersion string = 'IPv4'

@description('IP Assignment method')
@allowed([
  'Dynamic'
  'Static'
])
param ipAllocationMethod string = 'Dynamic'

@description('Idle timeout in minutes')
@minValue(4)
@maxValue(30)
param idleTimeoutInMinutes int = 4

@description('DNS name label (optional)')
param dnsNameLabel string = ''

@description('Tags for the resource')
param tags object = {}

resource publicIP 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: publicIpName
  location: location
  sku: {
    name: sku
    tier: tier
  }
  properties: {
    publicIPAllocationMethod: ipAllocationMethod
    publicIPAddressVersion: ipVersion
    idleTimeoutInMinutes: idleTimeoutInMinutes
    dnsSettings: !empty(dnsNameLabel) ? {
      domainNameLabel: dnsNameLabel
    } : null
  }
  tags: tags
}
