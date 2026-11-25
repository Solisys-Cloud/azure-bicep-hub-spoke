// Hub virtual network with the reserved subnets for shared platform services.

@description('Virtual network name.')
param name string

@description('Azure region.')
param location string = resourceGroup().location

@description('Hub address space, /22 or larger.')
param addressPrefix string

@description('Resource tags.')
param tags object

// Subnets are carved from the address space: four /26 blocks.
var subnets = {
  gateway: cidrSubnet(addressPrefix, 26, 0)
  firewall: cidrSubnet(addressPrefix, 26, 1)
  firewallManagement: cidrSubnet(addressPrefix, 26, 2)
  bastion: cidrSubnet(addressPrefix, 26, 3)
}

resource vnet 'Microsoft.Network/virtualNetworks@2025-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: subnets.gateway
        }
      }
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: subnets.firewall
        }
      }
      {
        name: 'AzureFirewallManagementSubnet'
        properties: {
          addressPrefix: subnets.firewallManagement
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: subnets.bastion
        }
      }
    ]
  }
}

output id string = vnet.id
output name string = vnet.name
output gatewaySubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'GatewaySubnet')
output firewallSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'AzureFirewallSubnet')
output firewallManagementSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'AzureFirewallManagementSubnet')
output bastionSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'AzureBastionSubnet')
