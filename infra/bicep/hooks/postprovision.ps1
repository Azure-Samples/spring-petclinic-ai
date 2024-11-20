azd env set AZURE_RESOURCE_GROUP $env:resourceGroupName

azd env set AZURE_CONTAINER_REGISTRY_ENDPOINT $env:acrLoginServer

azd env set AZD_PROVISION_TIMESTAMP $env:azdProvisionTimestamp

Write-Host ""
Write-Host "INFO: " -ForegroundColor Green -NoNewline;
Write-Host "Deploy finish succeed!"

Write-Host "INFO: " -ForegroundColor Green -NoNewline;
Write-Host "App url: https://$env:appFqdn"

$domain = (az account show -o tsv --query tenantDefaultDomain)
Write-Host "INFO: " -ForegroundColor Green -NoNewline;
Write-Host "Resource Group: $env:environmentPortal/#@$domain$env:resourceGroupId
