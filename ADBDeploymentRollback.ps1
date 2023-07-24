$clientId = "<>"
$clientSecret = "<>"
$tenantId = "<>"
$resourcegroup = "<>"
$adbwsname = "<>"

# Log in to Azure using the service principal
az login --service-principal --username $clientId --password $clientSecret --tenant $tenantId
# Set the Azure subscription context (if you have multiple subscriptions)
az account set --subscription "<>"

az config set extension.use_dynamic_install=yes_without_prompt
Write-Output "Provisioning Azure Databricks workspace..."
#Delete The ADB Workspace
$deleteDatabricks = az databricks workspace delete --name $adbwsname --resource-group $resourcegroup --yes | ConvertFrom-Json

$keyVaultName = "<>"
$secretName = $adbwsname+"-token"

# Delete the Added the secret to the Key Vault
$deletedSecret = az keyvault secret delete --name $secretName --vault-name $keyVaultName | ConvertFrom-Json
$purgeSecret = az keyvault secret purge --name $secretName --vault-name $keyVaultName | ConvertFrom-Json
Write-Output "Secret '$secretName' has been Deleted & Purged From Key Vault '$keyVaultName'."
