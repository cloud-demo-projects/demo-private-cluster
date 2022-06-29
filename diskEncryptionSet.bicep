targetScope = 'resourceGroup'

@description('Specifies the name of the AKS cluster.')
param location string = resourceGroup().location

@description('Specifies the name of the AKS cluster.')
param clusterName string

@description('Specifies the name of the existing Key Vault.')
param keyVaultName string

resource keyVault 'Microsoft.KeyVault/vaults@2021-10-01' existing = {
  name: keyVaultName
}

resource key 'Microsoft.KeyVault/vaults/keys@2021-10-01' = {
  name: '${clusterName}-kv-secret'
  parent: keyVault
  properties: {
    attributes: {
      enabled: true
      exp: 1672527600
    }
    keyOps: [
      'encrypt'
      'decrypt'
      'sign'
      'verify'
      'wrapKey'
      'unwrapKey'
    ]
    kty: 'RSA'
  }
}

resource accessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2021-11-01-preview' = {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: [
      {
        objectId: diskEncryptionSet.identity.principalId
        permissions: {
          keys: [
            'get'
            'wrapKey'
            'unwrapKey'
          ]
        }
        tenantId: '3a15904d-3fd9-4256-a753-beb05cdf0c6d'
      }
    ]
  }
}

resource diskEncryptionSet 'Microsoft.Compute/diskEncryptionSets@2021-12-01' = {
  name: '${clusterName}-des'
  location: location

  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    activeKey: {
      keyUrl: key.properties.keyUriWithVersion
      sourceVault: {
        id: keyVault.id
      }
    }
  }
}

output id string = diskEncryptionSet.id
