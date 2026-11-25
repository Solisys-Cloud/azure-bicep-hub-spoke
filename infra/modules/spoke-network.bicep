// Workload spoke: tiered subnets, one NSG per subnet, forced egress through the hub firewall.

@description('Virtual network name.')
param name string

@description('Azure region.')
param location string = resourceGroup().location

@description('Spoke address space, /22 or larger.')
param addressPrefix string

@description('Private IP of the hub firewall. Empty means no forced tunnelling.')
param firewallPrivateIp string = ''

@description('Resource tags.')
param tags object

var useFirewall = !empty(firewallPrivateIp)

// Four /24 tiers carved from the address space.
var tiers = [
  {
    name: 'snet-appgw'
    prefix: cidrSubnet(addressPrefix, 24, 0)
    routeToFirewall: false
    privateEndpoints: false
  }
  {
    name: 'snet-frontend'
    prefix: cidrSubnet(addressPrefix, 24, 1)
    routeToFirewall: true
    privateEndpoints: false
  }
  {
    name: 'snet-backend'
    prefix: cidrSubnet(addressPrefix, 24, 2)
    routeToFirewall: true
    privateEndpoints: false
  }
  {
    name: 'snet-privatelink'
    prefix: cidrSubnet(addressPrefix, 24, 3)
    routeToFirewall: false
    privateEndpoints: true
  }
]

// Inbound rules per tier. Everything else falls through to the deny-all rule.
var tierRules = {
  'snet-appgw': [
    {
      name: 'allow-https-internet'
      priority: 100
      source: 'Internet'
      destination: '*'
      ports: [
        '443'
      ]
    }
    {
      name: 'allow-gateway-manager'
      priority: 110
      source: 'GatewayManager'
      destination: '*'
      ports: [
        '65200-65535'
      ]
    }
    {
      name: 'allow-azure-load-balancer'
      priority: 120
      source: 'AzureLoadBalancer'
      destination: '*'
      ports: [
        '*'
      ]
    }
  ]
  'snet-frontend': [
    {
      name: 'allow-https-from-appgw'
      priority: 100
      source: cidrSubnet(addressPrefix, 24, 0)
      destination: '*'
      ports: [
        '443'
      ]
    }
    {
      name: 'allow-azure-load-balancer'
      priority: 120
      source: 'AzureLoadBalancer'
      destination: '*'
      ports: [
        '*'
      ]
    }
  ]
  'snet-backend': [
    {
      name: 'allow-app-from-frontend'
      priority: 100
      source: cidrSubnet(addressPrefix, 24, 1)
      destination: '*'
      ports: [
        '443'
        '1433'
      ]
    }
    {
      name: 'allow-azure-load-balancer'
      priority: 120
      source: 'AzureLoadBalancer'
      destination: '*'
      ports: [
        '*'
      ]
    }
  ]
  'snet-privatelink': [
    {
      name: 'allow-https-from-spoke'
      priority: 100
      source: addressPrefix
      destination: '*'
      ports: [
        '443'
      ]
    }
  ]
}

resource nsgs 'Microsoft.Network/networkSecurityGroups@2025-05-01' = [
  for tier in tiers: {
    name: 'nsg-${name}-${replace(tier.name, 'snet-', '')}'
    location: location
    tags: tags
    properties: {
      securityRules: concat(
        map(tierRules[tier.name], rule => {
          name: rule.name
          properties: {
            priority: rule.priority
            direction: 'Inbound'
            access: 'Allow'
            protocol: 'Tcp'
            sourceAddressPrefix: rule.source
            sourcePortRange: '*'
            destinationAddressPrefix: rule.destination
            destinationPortRanges: rule.ports
          }
        }),
        [
          {
            name: 'deny-all-inbound'
            properties: {
              priority: 4096
              direction: 'Inbound'
              access: 'Deny'
              protocol: '*'
              sourceAddressPrefix: '*'
              sourcePortRange: '*'
              destinationAddressPrefix: '*'
              destinationPortRange: '*'
            }
          }
        ]
      )
    }
  }
]

resource routeTable 'Microsoft.Network/routeTables@2025-05-01' = if (useFirewall) {
  name: 'rt-${name}'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: true
    routes: [
      {
        name: 'default-to-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIp
        }
      }
    ]
  }
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
      for (tier, i) in tiers: {
        name: tier.name
        properties: {
          addressPrefix: tier.prefix
          networkSecurityGroup: {
            id: nsgs[i].id
          }
          routeTable: useFirewall && tier.routeToFirewall ? { id: routeTable.id } : null
          privateEndpointNetworkPolicies: tier.privateEndpoints ? 'Enabled' : 'Disabled'
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

output id string = vnet.id
output name string = vnet.name
output privateLinkSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-privatelink')
