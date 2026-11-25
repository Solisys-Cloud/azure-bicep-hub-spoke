using 'main.bicep'

// Lab defaults: network, private DNS and Key Vault only, at near-zero cost.
// Set the deploy flags to true to add the billable hub services.

param prefix = 'hs'
param location = 'westeurope'
param environment = 'dev'

param hubAddressPrefix = '10.0.0.0/22'
param spokeAddressPrefix = '10.1.0.0/22'

param deployFirewall = false
param firewallTier = 'Basic'
param deployBastion = false
param deployVpnGateway = false
