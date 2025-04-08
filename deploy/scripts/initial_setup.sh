#!/bin/bash
set -e

# This script creates the necessary registry infrastructure and configures GitHub OpenID Connect for this repo
usage="Usage: ./initial_setup.sh <tenantId> <subscriptionId> <resourceGroupName>"
tenantId=${1:?"Missing tenantId. ${usage}"}
subId=${2:?"Missing subscriptionId. ${usage}"}
rgName=${3:?"Missing resourceGroupName. ${usage}"}

repoOwner="jimlarscode"
repoName="rg-Salfjallet"
rgLocation="swedencentral"

az account set -n "$subId"
az group create \
  --location "$rgLocation" \
  --name "$rgName" >/dev/null

appCreate=$(az ad app create --display-name $rgName)
appId=$(echo $appCreate | jq -r '.appId')

if [[ -z $(az ad sp show --id $appId 2>/dev/null) ]]; then
  az ad sp create --id $appId >/dev/null
fi

spId=$(az ad sp show --id $appId --query id --output tsv)
az role assignment create \
  --role JimLarsInfrastructureAsCode \
  --subscription $subId \
  --assignee-object-id $spId \
  --assignee-principal-type ServicePrincipal \
  --scope subscriptions/$subId/resourceGroups/$rgName >/dev/null

credName="cimain"
credSubject="repo:$repoOwner/$repoName:ref:refs/heads/master"
if [[ -z $(az ad app federated-credential show --id $appId --federated-credential-id $credName 2>/dev/null) ]]; then
  az ad app federated-credential create \
    --id $appId \
    --parameters '{"name":"'$credName'","issuer":"https://token.actions.githubusercontent.com","subject":"'$credSubject'","description":"GitHub OIDC Connection","audiences":["api://AzureADTokenExchange"]}' >/dev/null
fi

credName="cipullrequest"
credSubject="repo:$repoOwner/$repoName:pull_request"
if [[ -z $(az ad app federated-credential show --id $appId --federated-credential-id $credName 2>/dev/null) ]]; then
  az ad app federated-credential create \
    --id $appId \
    --parameters '{"name":"'$credName'","issuer":"https://token.actions.githubusercontent.com","subject":"'$credSubject'","description":"GitHub OIDC Connection","audiences":["api://AzureADTokenExchange"]}' >/dev/null
fi

# Set secrets for GitHub Actions
gh -R $repoOwner/$repoName secret set AZURE_CLIENT_ID --body $appId --app actions
gh -R $repoOwner/$repoName secret set AZURE_SUBSCRIPTION_ID --body $subId --app actions
gh -R $repoOwner/$repoName secret set AZURE_TENANT_ID --body $tenantId --app actions

# Set secrets for GitHub Actions invoked by Dependabot
gh -R $repoOwner/$repoName secret set AZURE_CLIENT_ID --body $appId --app dependabot
gh -R $repoOwner/$repoName secret set AZURE_SUBSCRIPTION_ID --body $subId --app dependabot
gh -R $repoOwner/$repoName secret set AZURE_TENANT_ID --body $tenantId --app dependabot