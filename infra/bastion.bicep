targetScope = 'resourceGroup'

// Azure Bastion Developer SKU
// - Free, shared infrastructure: no AzureBastionSubnet and no public IP required
// - Connects only to VMs in the SAME virtual network (no VNet peering support),
//   so one Developer bastion is deployed per VNet that hosts VMs (see main.bicep)
// - One VM connection at a time; portal connections only (no native client,
//   IP-connect or shareable links)
// - Only available in selected regions:
//   https://learn.microsoft.com/azure/bastion/bastion-sku-comparison

@description('Azure region for Bastion (must match the VNet region)')
param location    string

@description('Name of the existing VNet the Developer bastion serves')
param vnetName    string

@description('Name for the Bastion host')
param bastionName string = '${vnetName}-bastion'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
}

resource bastionHost 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: bastionName
  location: location
  sku: { name: 'Developer' }
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
  }
}

output bastionName string = bastionHost.name
