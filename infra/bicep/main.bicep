targetScope = 'subscription'

@minLength(2)
@maxLength(32)
@description('Name of the azd environment.')
param environmentName string

@minLength(2)
@description('Primary location for all resources.')
param location string

@description('Name of the resource group. Default: rg-{environmentName}')
param resourceGroupName string = ''

@description('Name of the Azure Container Registry. Default: cr{uniqueString}')
param acrName string = ''

@description('Name of the Azure OpenAI Service. Default: openai-{uniqueString}')
param openAiName string = ''

@description('Name of the new containerapp environment. Default: aca-env-{environmentName}')
param managedEnvironmentsName string = ''

@description('Name of the virtual network. Default vnet-{environmentName}')
param vnetName string = ''

@description('Boolean indicating the aca environment only has an internal load balancer. ')
param vnetEndpointInternal bool = false

param utcValue string = utcNow()

var vnetPrefix = '10.1.0.0/16'
var infraSubnetPrefix = '10.1.0.0/24'
var infraSubnetName = '${abbrs.networkVirtualNetworksSubnets}infra'

var abbrs = loadJsonContent('./abbreviations.json')
var tags = {
  'azd-env-name': environmentName
  'java-acc-samples-spring-petclinic-ai': 'true'
  'utc-time': utcValue
}

@description('Organize resources in a resource group')
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

@description('Prepare Azure Container Registry for the images with UMI for AcrPull & AcrPush')
module acr 'modules/acr/acr.bicep' = {
  name: 'acr-${environmentName}'
  scope: rg
  params: {
    name: !empty(acrName) ? acrName : '${abbrs.containerRegistryRegistries}${uniqueString(rg.id)}'
    tags: tags
  }
}

var placeholderImage = 'mcr.microsoft.com/azurespringapps/default-banner:distroless-2024022107-66ea1a62-87936983'

var acrLoginServer = acr.outputs.loginServer

@description('Create user assigned managed identity for petclinic apps')
// apps will use this managed identity to connect MySQL, openAI etc
module umiApps 'modules/shared/userAssignedIdentity.bicep' = {
  name: 'umi-apps'
  scope: rg
  params: {
    name: 'umi-apps-${environmentName}'
  }
}

@description('Create Vnet for Azure Container Apps')
module vnet './modules/network/vnet.bicep' = {
  name: 'vnet-${environmentName}'
  scope: rg
  params: {
    name: !empty(vnetName) ? vnetName : '${abbrs.networkVirtualNetworks}${environmentName}'
    location: location
    vnetAddressPrefixes: [vnetPrefix]
    subnets: [
      {
        name: infraSubnetName
        properties: {
          addressPrefix: infraSubnetPrefix
          delegations: [
            {
              name: 'ContainerAppsEnvInfra'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
    ]
    tags: tags
  }
}

@description('Prepare Open AI instance')
module openai 'modules/ai/openai.bicep' = {
  name: 'openai-${environmentName}'
  scope: rg
  params: {
    accountName: !empty(openAiName) ? openAiName : 'openai-${environmentName}'
    appPrincipalId: umiApps.outputs.principalId
    tags: tags
  }
}

@description('Create Azure Container Apps environment')
module managedEnvironment 'modules/containerapps/aca-environment.bicep' = {
  name: 'managedEnvironment-${environmentName}'
  scope: rg
  params: {
    name: !empty(managedEnvironmentsName) ? managedEnvironmentsName : 'aca-env-${environmentName}'
    location: location
    isVnet: true
    vnetEndpointInternal: vnetEndpointInternal
    vnetSubnetId: first(filter(vnet.outputs.vnetSubnets, x => x.name == infraSubnetName)).id
    userAssignedIdentities: {
      '${acr.outputs.umiAcrPullId}': {}
      '${umiApps.outputs.id}': {}
    }
    tags: tags
  }
}

@description('Create apps for the petclinic ai solution')
module application 'modules/app/petclinic.bicep' = {
  name: 'petclinic-${environmentName}'
  scope: rg
  params: {
    managedEnvironmentsName: managedEnvironment.outputs.containerAppsEnvironmentName
    umiAppsClientId: umiApps.outputs.clientId
    umiAppsIdentityId: umiApps.outputs.id
    acrRegistry: acrLoginServer
    acrIdentityId: acr.outputs.umiAcrPullId
    appImage: placeholderImage
    targetPort: 8080
    openAiEndpoint: openai.outputs.endpoint
    tags: tags
  }
}

output environmentPortal string = environment().portal
output subscriptionId string = subscription().subscriptionId

output resourceGroupName string = rg.name
output resourceGroupId string = rg.id

output acrLoginServer string = acrLoginServer

output appFqdn string = application.outputs.appFqdn

output azdProvisionTimestamp string = 'azd-${environmentName}-${utcValue}'
