// One direction of a virtual network peering. Deploy twice for hub and spoke.

@description('Name of the local virtual network.')
param localVnetName string

@description('Resource ID of the remote virtual network.')
param remoteVnetId string

@description('Peering name.')
param name string

@description('Set on the hub side when a VPN or ExpressRoute gateway exists.')
param allowGatewayTransit bool = false

@description('Set on the spoke side to use the hub gateway.')
param useRemoteGateways bool = false

resource localVnet 'Microsoft.Network/virtualNetworks@2025-05-01' existing = {
  name: localVnetName
}

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2025-05-01' = {
  parent: localVnet
  name: name
  properties: {
    remoteVirtualNetwork: {
      id: remoteVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: allowGatewayTransit
    useRemoteGateways: useRemoteGateways
  }
}
