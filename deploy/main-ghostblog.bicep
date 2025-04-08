param applicationNamePrefix string = 'ghost'
param appServicePlanSku string = 'B1'
param skuCapacity int = 1
param logAnalyticsWorkspaceSku string = 'PerGB2018'
param storageAccountSku string = 'Standard_LRS'
param location string
param mySQLServerSku string = 'Standard_B1ms'
param lastDeployed string = utcNow('d')

@secure()
param databasePassword string

param ghostContainerName string = 'andrewmatveychuk/ghost-ai:latest'
param containerRegistryUrl string = 'https://index.docker.io/v1'

@allowed([
  'Web app only'
  'Web app with Azure Front Door'
])
param deploymentConfiguration string = 'Web app only'
@description('Virtual network address prefix to use')
param vnetAddressPrefix string = '10.0.0.0/26'
@description('Address prefix for web app integration subnet')
param webAppIntegrationSubnetPrefix string = '10.0.0.0/28'
@description('Address prefix for private links subnet')
param privateEndpointsSubnetPrefix string = '10.0.0.16/28'

var vNetName = '${applicationNamePrefix}-vnet-${uniqueString(resourceGroup().id)}'
var privateEndpointsSubnetName = 'privateEndpointsSubnet'
var webAppIntegrationSubnetName = 'webAppIntegrationSubnet'
var webAppName = '${applicationNamePrefix}-web-${uniqueString(resourceGroup().id)}'
var appServicePlanName = '${applicationNamePrefix}-asp-${uniqueString(resourceGroup().id)}'
var logAnalyticsWorkspaceName = '${applicationNamePrefix}-la-${uniqueString(resourceGroup().id)}'
var applicationInsightsName = '${applicationNamePrefix}-ai-${uniqueString(resourceGroup().id)}'
var keyVaultName = '${applicationNamePrefix}-kv-${uniqueString(resourceGroup().id)}'
var storageAccountName = '${applicationNamePrefix}stor${uniqueString(resourceGroup().id)}'

var mySQLServerName = '${applicationNamePrefix}-mysql-${uniqueString(resourceGroup().id)}'
var databaseLogin = 'ghost'
var databaseName = 'ghost'

var ghostContentFileShareName = 'contentfiles'
var ghostContentFilesMountPath = '/var/lib/ghost/content_files'
var siteUrl = (deploymentConfiguration == 'Web app with Azure Front Door')
  ? 'https://${frontDoor.outputs.frontDoorEndpointHostName}'
  : 'https://${webApp.outputs.hostName}'

//Web app with Azure Front Door
var frontDoorName = '${applicationNamePrefix}-afd-${uniqueString(resourceGroup().id)}'

module vNet 'modules/virtualNetwork.bicep' = {
  name: 'vNetDeploy'
  params: {
    vNetName: vNetName
    vNetAddressPrefix: vnetAddressPrefix
    privateEndpointsSubnetName: privateEndpointsSubnetName
    privateEndpointsSubnetPrefix: privateEndpointsSubnetPrefix
    webAppIntegrationSubnetName: webAppIntegrationSubnetName
    webAppIntegrationSubnetPrefix: webAppIntegrationSubnetPrefix
    location: location
  }
}

module logAnalyticsWorkspace './modules/logAnalyticsWorkspace.bicep' = {
  name: 'logAnalyticsWorkspaceDeploy'
  params: {
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    logAnalyticsWorkspaceSku: logAnalyticsWorkspaceSku
    location: location
  }
}

module storageAccount 'modules/storageAccount.bicep' = {
  name: 'storageAccountDeploy'
  params: {
    storageAccountName: storageAccountName
    storageAccountSku: storageAccountSku
    fileShareFolderName: ghostContentFileShareName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    location: location
    vNetName: vNetName
    privateEndpointsSubnetName: privateEndpointsSubnetName
  }
  dependsOn: [
    vNet
    logAnalyticsWorkspace
  ]
}

module keyVault './deploy/modules/keyVault.bicep' = {
  name: 'keyVaultDeploy'
  params: {
    keyVaultName: keyVaultName
    keyVaultSecretName: 'databasePassword'
    keyVaultSecretValue: databasePassword
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    location: location
    vNetName: vNetName
    privateEndpointsSubnetName: privateEndpointsSubnetName
    webAppName: webAppName
  }
  dependsOn: [
    webApp
    vNet
    logAnalyticsWorkspace
  ]
}

module webApp './deploy/modules/webApp.bicep' = {
  name: 'webAppDeploy'
  params: {
    webAppName: webAppName
    appServicePlanName: appServicePlanName
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    vNetName: vNetName
    webAppIntegrationSubnetName: webAppIntegrationSubnetName
  }
  dependsOn: [
    appServicePlan
    vNet
    logAnalyticsWorkspace
  ]
}

module webAppSettings './deploy/modules/webAppSettings.bicep' = {
  name: 'webAppSettingsDeploy'
  params: {
    webAppName: webAppName
    containerRegistryUrl: containerRegistryUrl
    ghostContainerImage: ghostContainerName
    containerMountPath: ghostContentFilesMountPath
    mySQLServerName: mySQLServerName
    databaseName: databaseName
    databaseLogin: databaseLogin
    databasePasswordSecretUri: keyVault.outputs.secretUri
    siteUrl: siteUrl
    applicationInsightsName: applicationInsightsName
    fileShareName: storageAccount.outputs.fileShareFullName
    storageAccountName: storageAccountName
  }
  dependsOn: [
    webApp
    frontDoor
    mySQLServer
  ]
}

module appServicePlan './deploy/modules/appServicePlan.bicep' = {
  name: 'appServicePlanDeploy'
  params: {
    appServicePlanName: appServicePlanName
    appServicePlanSku: appServicePlanSku
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
  }
  dependsOn: [
    logAnalyticsWorkspace
  ]
}

module applicationInsights './deploy/modules/applicationInsights.bicep' = {
  name: 'applicationInsightsDeploy'
  params: {
    applicationInsightsName: applicationInsightsName
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    webAppName: webAppName
  }
  dependsOn: [
    webApp
    logAnalyticsWorkspace
  ]
}

module mySQLServer './deploy/modules/mySQLServer.bicep' = {
  name: 'mySQLServerDeploy'
  params: {
    administratorLogin: databaseLogin
    administratorPassword: databasePassword
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    mySQLServerName: mySQLServerName
    mySQLServerSku: mySQLServerSku
    vNetName: vNetName
    privateEndpointsSubnetName: privateEndpointsSubnetName
  }
  dependsOn: [
    vNet
    logAnalyticsWorkspace
  ]
}

module frontDoor './deploy/modules/frontDoor.bicep' = if (deploymentConfiguration == 'Web app with Azure Front Door') {
  name: 'FrontDoorDeploy'
  params: {
    frontDoorProfileName: frontDoorName
    applicationName: applicationNamePrefix
    webAppName: webAppName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
  }
  dependsOn: [
    webApp
    logAnalyticsWorkspace
  ]
}

output webAppHostName string = webApp.outputs.hostName
output endpointHostName string = siteUrl
