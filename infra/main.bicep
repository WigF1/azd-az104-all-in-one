targetScope = 'resourceGroup'

@description('Location for hub vnet resources')
param hubLocation string

@description('Location for spoke1 vnet resources')
param spoke1Location string

@description('Location for spoke2 vnet resources')
param spoke2Location string

@description('Location for workload vnet resources')
param workloadLocation string

@description('Administrator username for virtual machines')
param adminUsername string

@description('Administrator password for virtual machines')
@secure()
param adminPassword string

// Add parameter to control Bastion deployment
@description('Whether to deploy Bastion Developer hosts (free) in spoke1, spoke2 and workload VNets')
param deployBastion bool = true

// Add parameter to control VPN deployment
@description('Whether to deploy VPN Gateway')
param deployVpnGateway bool = true

// Add parameters for Key Vault and CMK
@description('Whether to deploy Key Vault for customer-managed keys demos')
param deployKeyVault bool = true 

@description('Object ID of the admin for Key Vault access')
param adminObjectId string = ''

@description('Whether to enable Customer-Managed Keys for storage encryption')
param enableCmkForStorage bool = false

@description('Whether to deploy Monitoring (DCR, Connection Monitor, Alerts)')
param deployMonitoring bool = true

@description('Email address for alert notifications (set with: azd env set AZURE_ALERT_EMAIL you@example.com)')
param alertEmailAddress string = ''

@description('Whether to deploy the custom RBAC role and policy initiative definitions (needs Owner or User Access Administrator on the subscription)')
param deployGovernance bool = true

@description('Enable Key Vault purge protection. Off by default so azd down --purge can fully remove the vault; turn it on live (it is irreversible) or enable CMK, which forces it on.')
param enableKeyVaultPurgeProtection bool = false

param publicDnsZoneBase  string = 'contoso.com'
param privateDnsZoneBase string = 'contoso.local'
param vaultName          string = 'contoso-rsv'
param storageAccountPrefix string = 'staz104'

// VM Size Configuration
@description('Default VM size for all tiers unless overridden')
param defaultVmSize string = 'Standard_B2s_v2'

@description('Override VM size for web tier (leave empty to use default)')
param webTierVmSize string = ''

@description('Override VM size for app tier (leave empty to use default)')
param appTierVmSize string = ''

@description('Override VM size for workload tier (leave empty to use default)')
param workloadTierVmSize string = ''

@description('Override VM size for VMSS (leave empty to use default)')
param vmssVmSize string = ''

// Resolve VM sizes: use tier-specific override if provided, otherwise use default
var resolvedWebTierVmSize = !empty(webTierVmSize) ? webTierVmSize : defaultVmSize
var resolvedAppTierVmSize = !empty(appTierVmSize) ? appTierVmSize : defaultVmSize
var resolvedWorkloadTierVmSize = !empty(workloadTierVmSize) ? workloadTierVmSize : defaultVmSize
var resolvedVmssVmSize = !empty(vmssVmSize) ? vmssVmSize : defaultVmSize

var hubVnetName = 'hub-vnet'
var spoke1VnetName = 'spoke1-vnet'
var spoke2VnetName = 'spoke2-vnet'
var workloadVnetName = 'workload-vnet'


module network 'network.bicep' = {
  name: 'vnets'
  params: {
    hublocation: hubLocation
    spoke1location: spoke1Location
    spoke2location: spoke2Location
    workloadlocation: workloadLocation
    hubVnetName: hubVnetName
    spoke1VnetName: spoke1VnetName
    spoke2VnetName: spoke2VnetName
    workloadVnetName: workloadVnetName
  }
}

// Bastion Developer SKU (free) does not support VNet peering, so instead of a single
// hub bastion we deploy one Developer bastion into each VNet that hosts VMs.
// The hub VNet has no VMs, so it gets none (AzureBastionSubnet is left in place).
var bastionTargets = [
  { vnetName: spoke1VnetName,   location: spoke1Location }
  { vnetName: spoke2VnetName,   location: spoke2Location }
  { vnetName: workloadVnetName, location: workloadLocation }
]

module bastion 'bastion.bicep' = [for target in bastionTargets: if (deployBastion) {
  name: 'bastion-${target.vnetName}'
  params: {
    location:    target.location
    vnetName:    target.vnetName
    bastionName: '${target.vnetName}-bastion'
  }
  dependsOn: [
    network
  ]
}]

module vpnGateway 'vpnGateway.bicep' = if (deployVpnGateway) {
  name: 'vpn'
  params: {
    location: hubLocation
    vnetName: hubVnetName
    gatewayPip: 'hub-vpn-pip'
    vpnGatewayName: 'hub-vpn-gateway'
  }
  dependsOn: [
    network  
  ]
} 

 module enableGatewayTransit 'enableGatewayTransit.bicep' = if (deployVpnGateway) {
  name: 'enableGatewayTransit'
  params: {
    hubVnetName:    hubVnetName
    spoke1VnetName: spoke1VnetName
    spoke2VnetName: spoke2VnetName
  }
  dependsOn: [
    vpnGateway 
  ]
}

module webTier 'webTier.bicep' = {
  name: 'webTier'
  params: {
    location:       spoke1Location
    vnetName:       spoke1VnetName
    lbName:         'web-lb'
    vmNames:        [
      'web1-vm'
      'web2-vm'
    ]
    subnetName:     'default'
    adminUsername:  adminUsername
    adminPassword:  adminPassword
    vmSize:         resolvedWebTierVmSize
  }
  dependsOn: [
    network 
  ]
}

module appTier 'appTier.bicep' = {
  name: 'appTier'
  params: {
    location: spoke2Location 
    vnetName: spoke2VnetName
    appGwName: 'app-gateway'
    vmNames: [
      'vm1'
    ]
    vmSubnetName: 'default'
    appGwSubnetName: 'AppGwSubnet' // Make sure this subnet exists in the spoke2-vnet
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: resolvedAppTierVmSize
  }
  dependsOn: [
    network 
  ]
}

module workloadTier 'workloadTier.bicep' = {
  name: 'workloadTier'
  params: {
    location: workloadLocation 
    vnetName: workloadVnetName
    lbName: 'workload-lb'
    vmName: 'workload1-vm'
    subnetName: 'default'
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: resolvedWorkloadTierVmSize
  }
  dependsOn: [
    network 
  ]
}

module consumerPe 'consumerPE.bicep' = {
  name: 'consumerPE'
  params: {
    location:           spoke2Location
    vnetName:           spoke2VnetName
    consumerSubnetName: 'default'
    peName:             'workload-pe'
    plsName:            'workload-pls'
  }
  dependsOn: [
    workloadTier
  ]
}

module shared 'sharedServices.bicep' = {
  name: 'sharedServices'
  params: {
    location: hubLocation
    publicDnsZoneBase: publicDnsZoneBase
    privateDnsZoneBase: privateDnsZoneBase
    vaultName: vaultName
    storageAccountPrefix: storageAccountPrefix
    deployKeyVault: deployKeyVault
    adminObjectId: adminObjectId
    enableCmkForStorage: enableCmkForStorage
    enablePurgeProtection: enableKeyVaultPurgeProtection
  }
  dependsOn: [
    workloadTier
  ]
}

module dnsLinks 'dnsLinks.bicep' = {
  name: 'dnsLinks'
  params: {
    privateDnsZoneName:   shared.outputs.privateDnsZoneName
    hubVnetName:          hubVnetName
    spoke1VnetName:       spoke1VnetName
    spoke2VnetName:       spoke2VnetName
  }
  dependsOn: [
    network 
  ]
}

module vmss 'vmss.bicep' = {
  name: 'vmss'
  params: {
    location:       spoke2Location
    vnetName:       spoke2VnetName
    subnetName:     'default'
    vmSku:          resolvedVmssVmSize
    instanceCount:  2
    adminUsername:  adminUsername
    adminPassword: adminPassword
  }
  dependsOn: [
    network
  ]
}

// Deploy governance components conditionally
module governance 'governance.bicep' = {
  name: 'governance-${hubLocation}'
  scope: subscription()
  params: {
    deployGovernance: deployGovernance
    resourceGroupName: resourceGroup().name
    allowedLocations: [
      hubLocation
      spoke1Location
      spoke2Location
      workloadLocation
    ]
    allowedVmSizes: [
      'Standard_B2s' 
      'Standard_B2s_v2'
      'Standard_B4ms'
    ]
  }
}

// Deploy monitoring (DCR, Connection Monitor, Alerts)
module monitoring 'monitoring.bicep' = if (deployMonitoring) {
  name: 'monitoring'
  params: {
    location:            hubLocation
    deployMonitoring:    deployMonitoring
    webVmLocation:       spoke1Location
    appVmLocation:       spoke2Location
    workloadVmLocation:  workloadLocation
    webVmNames:          [ 'web1-vm', 'web2-vm' ]
    appVmNames:          [ 'vm1' ]
    workloadVmName:      'workload1-vm'
    webLbName:           'web-lb'
    workloadLbName:      'workload-lb'
    appGwName:           'app-gateway'
    vaultName:           vaultName
    alertEmailAddress:   !empty(alertEmailAddress) ? alertEmailAddress : 'trainer@contoso.com'
  }
  dependsOn: [
    webTier
    appTier
    workloadTier
    shared
  ]
}
