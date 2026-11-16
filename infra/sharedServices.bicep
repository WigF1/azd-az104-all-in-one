targetScope = 'resourceGroup'

@description('Azure region for all shared services')
param location           string = resourceGroup().location

// Base DNS zone names
@description('Base name for the public DNS zone (e.g. contoso.com)')
param publicDnsZoneBase string = 'contoso.com'

@description('Base name for the private DNS zone (e.g. contoso.local)')
param privateDnsZoneBase string = 'contoso.local'

// Generate 4-digit random suffix
var suffixDigits = substring(uniqueString(resourceGroup().id), 0, 4)

// Unique DNS zone names with 4-digit suffix
var uniquePublicDnsZoneName = replace(publicDnsZoneBase, '.com', '-${suffixDigits}.com')
var uniquePrivateDnsZoneName = replace(privateDnsZoneBase, '.local', '-${suffixDigits}.local')

@description('Name for the Recovery Services Vault')
param vaultName          string = 'contoso-rsv'

param storageAccountPrefix string = 'staz104'
var uniqueStorageName = '${storageAccountPrefix}${uniqueString(resourceGroup().id)}'
var uniqueStorageAccountName = length(uniqueStorageName) > 24 ? substring(uniqueStorageName, 0, 24) : uniqueStorageName

@description('SKU for the Storage Account')
param storageSku         string = 'Standard_LRS'

@description('Whether to deploy Key Vault for customer-managed keys')
param deployKeyVault bool = false

@description('Object ID of the deployment principal for Key Vault access')
param adminObjectId string = ''

@description('Whether to enable Customer-Managed Keys for storage encryption')
param enableCmkForStorage bool = false

@description('Enable purge protection on the Key Vault (forced on when CMK is enabled)')
param enablePurgeProtection bool = false

// Built-in role definition IDs
var keyVaultAdministratorRoleId = '00482a5a-887f-4fb3-b363-3b7fe8e74483'
var keyVaultCryptoServiceEncryptionUserRoleId = 'e147488a-f6f5-4113-8e2d-b22465e65bf6'

// 1️⃣ Public DNS Zone
resource publicDnsZone 'Microsoft.Network/dnsZones@2018-05-01' = {
  name: uniquePublicDnsZoneName
  location: 'global'
}

// 2️⃣ Private DNS Zone
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: uniquePrivateDnsZoneName
  location: 'global'
}

// 3️⃣ Recovery Services Vault
resource recoveryVault 'Microsoft.RecoveryServices/vaults@2021-08-01' = {
  name: vaultName
  location: location
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {}
}

// Import common module for shared variables
module common 'common.bicep' = {
  name: 'shared-common-params'
  params: {
    primaryLocation: location
    secondaryLocation: location
    workloadLocation: location
  }
}

// Fix: Define literal tags object since common module reference is used
var keyVaultTags = {
  project: 'AZ104 Demo'
  environment: 'demo'
  costCenter: 'Education'
  CostControl: 'ignore'
  SecurityControl: 'ignore'
}

// Key Vault for customer-managed keys - renamed to be clearer
resource keyVaultResource 'Microsoft.KeyVault/vaults@2022-07-01' = if (deployKeyVault) {
  name: 'kv-az104-${uniqueString(resourceGroup().id)}'
  location: location
  tags: keyVaultTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    enabledForDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // Purge protection can only be enabled (true) or left unset (null) - never set to false.
    // Off by default so `azd down --purge` fully removes the vault; CMK requires it.
    enablePurgeProtection: (enablePurgeProtection || enableCmkForStorage) ? true : null
    // Azure RBAC permission model; access is granted via role assignments below
    enableRbacAuthorization: true
    accessPolicies: []
  }
}

// Give the deploying user (azd sets AZURE_PRINCIPAL_ID) full data-plane access to the vault
resource adminKeyVaultAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployKeyVault && !empty(adminObjectId)) {
  name: guid(resourceGroup().id, 'kv-admin', adminObjectId)
  scope: keyVaultResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultAdministratorRoleId)
    principalId: adminObjectId
  }
}

// Create encryption key for storage
resource storageEncryptionKey 'Microsoft.KeyVault/vaults/keys@2022-07-01' = if (deployKeyVault && enableCmkForStorage) {
  parent: keyVaultResource
  name: 'storage-cmk'
  properties: {
    kty: 'RSA'
    keySize: 2048
    keyOps: [
      'encrypt'
      'decrypt'
      'sign'
      'verify'
      'wrapKey'
      'unwrapKey'
    ]
    attributes: {
      enabled: true
    }
  }
}

// Storage Account - updated to use CMK if enabled
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: uniqueStorageAccountName
  location: location
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: true // Changed to true to allow shared key access
    encryption: {
      keySource: enableCmkForStorage && deployKeyVault ? 'Microsoft.Keyvault' : 'Microsoft.Storage'
      keyvaultproperties: enableCmkForStorage && deployKeyVault ? {
        keyname: 'storage-cmk'
        keyvaulturi: keyVaultResource.properties.vaultUri
        keyversion: ''
      } : null
      services: {
        blob: { enabled: true }
        file: { enabled: true }
        table: { enabled: true }
        queue: { enabled: true }
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Assign the storage account's managed identity access to the Key Vault keys if using CMK (RBAC model)
resource storageKeyAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployKeyVault && enableCmkForStorage) {
  name: guid(resourceGroup().id, 'kv-storage-cmk', uniqueStorageAccountName)
  scope: keyVaultResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultCryptoServiceEncryptionUserRoleId)
    principalId: storageAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Export outputs
output publicDnsZoneName string = uniquePublicDnsZoneName
output privateDnsZoneName string = uniquePrivateDnsZoneName
output storageAccountName string = uniqueStorageAccountName
output keyVaultName string = deployKeyVault ? keyVaultResource.name : ''
output keyVaultUri string = deployKeyVault ? keyVaultResource.properties.vaultUri : ''
