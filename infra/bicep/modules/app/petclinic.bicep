targetScope = 'resourceGroup'

param managedEnvironmentsName string

param acrRegistry string
param acrIdentityId string

param umiAppsClientId string
param umiAppsIdentityId string

param appImage string

param targetPort int = 8080

param openAiEndpoint string

param tags object = {}

var env = [
    {
      name: 'AZURE_OPENAI_ENDPOINT'
      value: openAiEndpoint
    }
    {
      name: 'AZURE_CLIENT_ID'
      value: umiAppsClientId
    }
    {
      name: 'AZURE_OPENAI_KEYLESS'
      value: 'true'
    }
  ]

module app '../containerapps/containerapp.bicep' = {
  name: 'app-petclinic-ai'
  params: {
    containerAppsEnvironmentName: managedEnvironmentsName
    name: 'petclinic-ai'
    acrName: acrRegistry
    acrIdentityId: acrIdentityId
    image: appImage
    umiAppsIdentityId: umiAppsIdentityId
    external: true
    targetPort: targetPort
    isJava: true
    tags: tags
    env: env
  }
}

output appFqdn string = app.outputs.appFqdn

