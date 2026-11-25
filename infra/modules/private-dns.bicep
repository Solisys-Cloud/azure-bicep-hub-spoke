// Private DNS zones hosted in the hub and linked to every peered network.

@description('Private DNS zone names, for example privatelink.vaultcore.azure.net.')
param zoneNames array

@description('Virtual network IDs to link.')
param vnetIds array

@description('Resource tags.')
param tags object

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for zone in zoneNames: {
    name: zone
    location: 'global'
    tags: tags
  }
]

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for pair in flatten(map(range(0, length(zoneNames)), z => map(range(0, length(vnetIds)), v => {
    zone: z
    vnet: v
  }))): {
    parent: zones[pair.zone]
    name: last(split(vnetIds[pair.vnet], '/'))
    location: 'global'
    tags: tags
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnetIds[pair.vnet]
      }
    }
  }
]

output zoneIds array = [for (zone, i) in zoneNames: zones[i].id]
