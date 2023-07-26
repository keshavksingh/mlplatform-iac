$clientId = "<>"
$clientSecret = "<>"
$tenantId = "<>"
$resourcegroup = "<>"
$adbwsname = "<>"
$subscription= "<>"
$amlworkspace= "<>"
$amlAttachedAdbName = "<>"

# Log in to Azure using the service principal
az login --service-principal --username $clientId --password $clientSecret --tenant $tenantId
# Set the Azure subscription context (if you have multiple subscriptions)
az account set --subscription "<>"

#Detach the AML Attached Databricks Compute
$tokenEndpoint = "https://login.microsoftonline.com/$tenantId/oauth2/token"
$body = @{"grant_type" = "client_credentials";"client_id" = $clientId;"client_secret" = $clientSecret;"resource" = "https://management.azure.com/"}
# Convert the token request parameters to URL-encoded form data
$formData = $body.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, [System.Web.HttpUtility]::UrlEncode($_.Value) }
$formData = $formData -join "&"
$headers = @{ "Content-Type" = "application/x-www-form-urlencoded" }
$response = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Headers $headers -Body $formData
$accessToken = $response.access_token
# Define the compute delete URL
$deleteUrl = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourcegroup/providers/Microsoft.MachineLearningServices/workspaces/$amlworkspace/computes/"+$amlAttachedAdbName+"?api-version=2023-06-01-preview&underlyingResourceAction=Detach"
# Send the DELETE request
$headers = @{ "Authorization" = "Bearer $accessToken" }
$response = Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers

#Delete The ADB Workspace
az config set extension.use_dynamic_install=yes_without_prompt
Write-Output "Provisioning Azure Databricks workspace..."
$deleteDatabricks = az databricks workspace delete --name $adbwsname --resource-group $resourcegroup --yes | ConvertFrom-Json

$keyVaultName = "<>"
$secretName = $adbwsname+"-token"

# Delete the Added the secret to the Key Vault
$deletedSecret = az keyvault secret delete --name $secretName --vault-name $keyVaultName | ConvertFrom-Json
$purgeSecret = az keyvault secret purge --name $secretName --vault-name $keyVaultName | ConvertFrom-Json
Write-Output "Secret '$secretName' has been Deleted & Purged From Key Vault '$keyVaultName'."
