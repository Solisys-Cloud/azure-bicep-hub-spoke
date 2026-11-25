// Route-based VPN gateway for site-to-site connectivity to on-premises.
// Provisioning takes 30 to 45 minutes.

@description('Name suffix.')
param name string

@description('Azure region.')
param location string = resourceGroup().location

@description('Gateway SKU. AZ SKUs are zone-redundant.')
@allowed([
  'VpnGw1AZ'
  'VpnGw2AZ'
  'VpnGw3AZ'
])
param sku string = 'VpnGw1AZ'

@description('Resource ID of GatewaySubnet.')
param subnetId string

@description('Resource tags.')
param tags object

resource pip 'Microsoft.Network/publicIPAddresses@2025-05-01' = {
  name: 'pip-${name}'
  location: location
  tags: tags
  zones: [
    '1'
    '2'
    '3'
  ]
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource gateway 'Microsoft.Network/virtualNetworkGateways@2025-05-01' = {
  name: 'vgw-${name}'
  location: location
  tags: tags
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    vpnGatewayGeneration: 'Generation1'
    sku: {
      name: sku
      tier: sku
    }
    enableBgp: false
    activeActive: false
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
  }
}

output id string = gateway.id
