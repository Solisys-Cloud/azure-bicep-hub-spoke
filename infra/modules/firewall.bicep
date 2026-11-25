// Azure Firewall with a policy that controls spoke egress.

@description('Name prefix for the firewall resources.')
param name string

@description('Azure region.')
param location string = resourceGroup().location

@description('Firewall tier.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param tier string = 'Basic'

@description('Resource ID of AzureFirewallSubnet.')
param subnetId string

@description('Resource ID of AzureFirewallManagementSubnet. Required for the Basic tier.')
param managementSubnetId string

@description('Address spaces allowed to reach the internet through the firewall.')
param sourceAddressPrefixes array

@description('Availability zones. Leave empty in regions without zones.')
param zones array = [
  '1'
  '2'
  '3'
]

@description('Optional Log Analytics workspace for firewall logs.')
param logAnalyticsWorkspaceId string = ''

@description('Resource tags.')
param tags object

var isBasic = tier == 'Basic'

resource dataPip 'Microsoft.Network/publicIPAddresses@2025-05-01' = {
  name: 'pip-${name}'
  location: location
  tags: tags
  zones: zones
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource managementPip 'Microsoft.Network/publicIPAddresses@2025-05-01' = if (isBasic) {
  name: 'pip-${name}-mgmt'
  location: location
  tags: tags
  zones: zones
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource policy 'Microsoft.Network/firewallPolicies@2025-05-01' = {
  name: 'afwp-${name}'
  location: location
  tags: tags
  properties: {
    sku: {
      tier: tier
    }
    threatIntelMode: 'Alert'
  }
}

resource egressRules 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2025-05-01' = {
  parent: policy
  name: 'spoke-egress'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'allow-platform-network'
        priority: 100
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'dns'
            ipProtocols: [
              'UDP'
              'TCP'
            ]
            sourceAddresses: sourceAddressPrefixes
            destinationAddresses: [
              '*'
            ]
            destinationPorts: [
              '53'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'ntp'
            ipProtocols: [
              'UDP'
            ]
            sourceAddresses: sourceAddressPrefixes
            destinationAddresses: [
              '*'
            ]
            destinationPorts: [
              '123'
            ]
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'allow-web-egress'
        priority: 200
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'windows-update-and-azure'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            sourceAddresses: sourceAddressPrefixes
            fqdnTags: [
              'WindowsUpdate'
              'AzureBackup'
            ]
          }
        ]
      }
    ]
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2025-05-01' = {
  name: 'afw-${name}'
  location: location
  tags: tags
  zones: zones
  dependsOn: [
    egressRules
  ]
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: tier
    }
    firewallPolicy: {
      id: policy.id
    }
    ipConfigurations: [
      {
        name: 'data'
        properties: {
          subnet: {
            id: subnetId
          }
          publicIPAddress: {
            id: dataPip.id
          }
        }
      }
    ]
    managementIpConfiguration: isBasic
      ? {
          name: 'management'
          properties: {
            subnet: {
              id: managementSubnetId
            }
            publicIPAddress: {
              id: managementPip.id
            }
          }
        }
      : null
  }
}

#disable-next-line use-recent-api-versions
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'to-law'
  scope: firewall
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

output privateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
output id string = firewall.id
