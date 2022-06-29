targetScope = 'resourceGroup'

//
//  General parameters
//  ***************************
//
@description('Specifies the name of the AKS cluster.')
param location string = resourceGroup().location

@description('An AAD group object ids to give administrative access.')
param adminGroupObjectID string = ''

// 
//  AKS cluster parameters
//  **********************
//  These parameters are general parameters for the AKS cluster resource as a whole.
// 

@description('Specifies the name of the AKS cluster.')
param clusterName string

@description('Specifies the version of the AKS cluster.')
param aksVersion string

//
//  Pre-requisite Resource ID parameters
//  ************************************
//  These parameters must specify the Resource IDs of the pre-requisite resources which must already 
//  exist deployment. These resources include:
//  - a User-Assigned Managed Identity
//  - a Log Analytics Workspace
//  - a Disk Encryption Set
//

@description('Resource ID of an existing User-Assigned Managed Identity.')
param userAssignedManagedIdentityId string

@description('Resource ID of an existing Log Analytics Workspace.')
param logAnalyticsWorkspaceId string

//
//  General Cluster parameters
//  ***************************
//

@description('Specifies the name of DNS Prefix.')
param dnsPrefix string

//
//  System Node Pool parameters
//  ***************************
//  These parameters are here to show you which parameters you _can_ change.
//  The other parameters specified in the AKS cluster resource cannot be changed,
//  otherwise your cluster will not deploy due to incompliancy with Azure Policy.
//
//  You do not need to keep these parameters; you are free to remove them, hard-
//  code values, whatever you like. They are just here to highlight the
//  the configurable values.
//
//  You can always add another Node Pool too!
//

@description('Specifies the Node Pool\'s name.')
param nodePoolName string = 'system'

@description('Specifies the number of Nodes.')
param nodePoolCount int = 3

@description('Specifies the VM Size of Nodes.')
param nodePoolVmSize string = ''

@description('Specifies the maximum number of Pods per Node (\'maxPod\').')
param nodePoolMaxPod int = 30

@description('Specifies the Resource ID of the Subnet you wish to deploy AKS Nodes into.')
param nodePoolVnetSubnetID string

@description('Specifies the Resource ID of the Pod Subnet you wish to deploy AKS pods into.')
param nodePoolVnetPodSubnetID string


//
//  External disk encryption set deployment
//  ******************
//
resource diskEncryptionSet 'Microsoft.Compute/diskEncryptionSets@2021-12-01' existing = {
  name: '${clusterName}-des'
}

//
//  Role Assingement for the admin group.
//  ******************
//  The default RBAC roles that MS delivers out of the box
//  https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
//  The ID and names are the same. You can pick one and assing that to the group.
//
var role = {
  // roleName:    Azure Kubernetes Service Cluster Admin Role
  // description: List cluster admin credential action.
  azureKubernetesServiceClusterAdminRole: '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8'
  // roleName:    Azure Kubernetes Service Cluster User Role
  // description: List cluster user credential action.
  azureKubernetesServiceClusterUserRole: '4abbcc35-e782-43d8-92c5-2d3f1bd2253f'
  // roleName:    Azure Kubernetes Service Contributor Role
  // description: Grants access to read and write Azure Kubernetes Service clusters
  azureKubernetesServiceContributorRole: 'ed7f3fbd-7b88-4dd4-9017-9adb7ce333f8'
  // roleName:    Azure Kubernetes Service RBAC Admin
  // description: Lets you manage all resources under cluster/namespace, except update or delete resource quotas and namespaces.
  azureKubernetesServiceRBACAdmin: '3498e952-d568-435e-9b2c-8d77e338d7f7'
  // roleName:    Azure Kubernetes Service RBAC Cluster Admin
  // description: Lets you manage all resources in the cluster.
  azureKubernetesServiceRBACClusterAdmin: 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b'
  // roleName:    Azure Kubernetes Service RBAC Reader
  // description: Allows read-only access to see most objects in a namespace. It does not allow viewing roles or role bindings. This role does not allow viewing Secrets, since reading the contents of Secrets enables access to ServiceAccount credentials in the namespace, which would allow API access as any ServiceAccount in the namespace (a form of privilege escalation). Applying this role at cluster scope will give access across all namespaces.
  azureKubernetesServiceRBACReader: '7f6c6a51-bcf8-42ba-9220-52d62157d7db'
  // roleName:    Azure Kubernetes Service RBAC Writer
  // description: Allows read/write access to most objects in a namespace.This role does not allow viewing or modifying roles or role bindings. However, this role allows accessing Secrets and running Pods as any ServiceAccount in the namespace, so it can be used to gain the API access levels of any ServiceAccount in the namespace. Applying this role at cluster scope will give access across all namespaces.
  azureKubernetesServiceRBACWriter: 'a7ffa36f-339b-4b5c-8bdf-e2c188b2c0eb'
}

var roleID = role['azureKubernetesServiceRBACAdmin']
var roleDefinitionResourceId = '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/${roleID}'

resource RoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(managedCluster.id, adminGroupObjectID, roleDefinitionResourceId)
  scope: managedCluster
  properties: {
    roleDefinitionId: roleDefinitionResourceId
    principalId: adminGroupObjectID
  }
}

//
//  AKS cluster resources
//  ******************
//  This the basic set of a plain AKS cluster 
//  All the mandatory varabales are set as hardcoded values.
//  if you chnage the values than the policys will deny the deployment.
//  you can add more varables and configuration. 
//  Information can be found here: 
//   https://docs.microsoft.com/en-us/azure/templates/microsoft.containerservice/managedclusters?tabs=bicep
//
resource managedCluster 'Microsoft.ContainerService/managedClusters@2022-03-01' = {
  name: clusterName
  location: location

  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedManagedIdentityId}': {}
    }
  }

  sku: {
    name: 'Basic'
    tier: 'Free'
  }

  properties: {

    aadProfile: {
      managed: true
      enableAzureRBAC: true
      tenantID: subscription().tenantId
    }

    addonProfiles: {
      azurePolicy: {
        enabled: true
      }
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
    }

    agentPoolProfiles: [
      {
        name: nodePoolName
        count: nodePoolCount
        vmSize: nodePoolVmSize
        maxPods: nodePoolMaxPod
        vnetSubnetID: nodePoolVnetSubnetID
        podSubnetID: nodePoolVnetPodSubnetID
        mode: 'System'
        enableEncryptionAtHost: true
        osType: 'Linux'
      }
    ]

    apiServerAccessProfile: {
      enablePrivateCluster: true
      enablePrivateClusterPublicFQDN: true
      privateDNSZone: 'None'
    }

    disableLocalAccounts: true
    dnsPrefix: dnsPrefix
    enableRBAC: true
    kubernetesVersion: aksVersion

    diskEncryptionSetID: diskEncryptionSet.id

    networkProfile: {
      outboundType: 'userDefinedRouting'
      networkPlugin: 'azure'
      networkPolicy: 'calico'
      serviceCidr: '10.236.0.0/16'
      dnsServiceIP: '10.236.0.10'
      dockerBridgeCidr: '10.237.0.1/16'
    }
  }
}
