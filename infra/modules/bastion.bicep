// Azure Bastion for administrative access without public IPs on virtual machines.

@description('Name suffix.')
param name string

@description('Azure region.')
param location string = resourceGroup().location

@description('Bastion SKU.')
@allowed([
  'Basic'
  'Standard'
])
param sku string = 'Basic'

@description('Resource ID of AzureBastionSubnet.')
param subnetId string

@description('Resource tags.')
param tags object

resource pip 'Microsoft.Network/publicIPAddresses@2025-05-01' = {
  name: 'pip-${name}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2025-05-01' = {
  name: 'bas-${name}'
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    ipConfigurations: [
      {
        name: 'default'
        properties: {
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

output id string = bastion.id
