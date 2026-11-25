// Hub and spoke network topology with Bicep - subscription-scope entry point.
targetScope = 'subscription'

metadata name = 'Azure Hub and Spoke with Bicep'
metadata description = 'Hub and spoke topology with optional Azure Firewall, Bastion and VPN gateway, and a private Key Vault in the spoke.'
metadata author = 'Olivier Lumeau'

@description('Short prefix used in resource names, 2 to 6 lowercase characters.')
@minLength(2)
@maxLength(6)
param prefix string

@description('Azure region.')
param location string = 'westeurope'

@description('Environment name.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Resource tags.')
param tags object = {
  Owner: 'platform-team'
  CostCenter: 'IT-CLOUD-001'
  Environment: environment
}

@description('Hub address space.')
param hubAddressPrefix string = '10.0.0.0/22'

@description('Spoke address space.')
param spokeAddressPrefix string = '10.1.0.0/22'

@description('Deploy Azure Firewall and force spoke egress through it.')
param deployFirewall bool = false

@description('Azure Firewall tier.')
@allowed([
  'Basic'
  'Standard'
])
param firewallTier string = 'Basic'

@description('Deploy Azure Bastion.')
param deployBastion bool = false

@description('Deploy a VPN gateway for on-premises connectivity. Takes 30 to 45 minutes.')
param deployVpnGateway bool = false

@description('Optional Log Analytics workspace for firewall logs, for example from azure-bicep-landing-zone.')
param logAnalyticsWorkspaceId string = ''

var names = {
  hubRg: 'rg-${prefix}-hub-${environment}'
  spokeRg: 'rg-${prefix}-spoke-${environment}'
  hubVnet: 'vnet-${prefix}-hub-${environment}'
  spokeVnet: 'vnet-${prefix}-spoke-${environment}'
}

resource hubRg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: names.hubRg
  location: location
  tags: tags
}

resource spokeRg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: names.spokeRg
  location: location
  tags: tags
}

module hub 'modules/hub-network.bicep' = {
  name: 'hub-network'
  scope: hubRg
  params: {
    name: names.hubVnet
    location: location
    addressPrefix: hubAddressPrefix
    tags: tags
  }
}

module firewall 'modules/firewall.bicep' = if (deployFirewall) {
  name: 'hub-firewall'
  scope: hubRg
  params: {
    name: '${prefix}-hub-${environment}'
    location: location
    tier: firewallTier
    subnetId: hub.outputs.firewallSubnetId
    managementSubnetId: hub.outputs.firewallManagementSubnetId
    sourceAddressPrefixes: [
      spokeAddressPrefix
    ]
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    tags: tags
  }
}

module bastion 'modules/bastion.bicep' = if (deployBastion) {
  name: 'hub-bastion'
  scope: hubRg
  params: {
    name: '${prefix}-hub-${environment}'
    location: location
    subnetId: hub.outputs.bastionSubnetId
    tags: tags
  }
}

module vpnGateway 'modules/vpn-gateway.bicep' = if (deployVpnGateway) {
  name: 'hub-vpn-gateway'
  scope: hubRg
  params: {
    name: '${prefix}-hub-${environment}'
    location: location
    subnetId: hub.outputs.gatewaySubnetId
    tags: tags
  }
}

module spoke 'modules/spoke-network.bicep' = {
  name: 'spoke-network'
  scope: spokeRg
  params: {
    name: names.spokeVnet
    location: location
    addressPrefix: spokeAddressPrefix
    firewallPrivateIp: deployFirewall ? firewall!.outputs.privateIp : ''
    tags: tags
  }
}

module hubToSpoke 'modules/peering.bicep' = {
  name: 'peering-hub-to-spoke'
  scope: hubRg
  dependsOn: [
    vpnGateway
  ]
  params: {
    name: 'peer-hub-to-spoke'
    localVnetName: hub.outputs.name
    remoteVnetId: spoke.outputs.id
    allowGatewayTransit: deployVpnGateway
  }
}

module spokeToHub 'modules/peering.bicep' = {
  name: 'peering-spoke-to-hub'
  scope: spokeRg
  dependsOn: [
    hubToSpoke
  ]
  params: {
    name: 'peer-spoke-to-hub'
    localVnetName: spoke.outputs.name
    remoteVnetId: hub.outputs.id
    useRemoteGateways: deployVpnGateway
  }
}

module privateDns 'modules/private-dns.bicep' = {
  name: 'private-dns'
  scope: hubRg
  params: {
    zoneNames: [
      'privatelink.vaultcore.azure.net'
    ]
    vnetIds: [
      hub.outputs.id
      spoke.outputs.id
    ]
    tags: tags
  }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'spoke-key-vault'
  scope: spokeRg
  params: {
    name: 'kv-${prefix}-${uniqueString(spokeRg.id)}'
    location: location
    privateEndpointSubnetId: spoke.outputs.privateLinkSubnetId
    privateDnsZoneId: privateDns.outputs.zoneIds[0]
    tags: tags
  }
}

output hubVnetId string = hub.outputs.id
output spokeVnetId string = spoke.outputs.id
output firewallPrivateIp string = deployFirewall ? firewall!.outputs.privateIp : 'not deployed'
output keyVaultUri string = keyVault.outputs.uri
