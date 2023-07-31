$clientId = "<>"
$clientSecret = "<>"
$tenantId = "<>"
$resourcegroup = "<>"
$subscription = "<>"
$synapsewsname = "<>"
$synapsewsStorageName = "<>"
$keyVaultName = "<>"
$sparkPoolName = "sparkpool"
$amlAttachedSynapseName = "synparkpool"
$amlworkspace = "<>"

# Log in to Azure using the service principal
az login --service-principal --username $clientId --password $clientSecret --tenant $tenantId

# Set the Azure subscription context (if you have multiple subscriptions)
az account set --subscription $subscription

#Detach Synapse Spark Pool from Azure ML Workspace
$tokenEndpoint = "https://login.microsoftonline.com/$tenantId/oauth2/token"
$body = @{"grant_type" = "client_credentials";"client_id" = $clientId;"client_secret" = $clientSecret;"resource" = "https://management.azure.com/"}
$formData = $body.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, [System.Web.HttpUtility]::UrlEncode($_.Value) }
$formData = $formData -join "&"
$headers = @{ "Content-Type" = "application/x-www-form-urlencoded" }
$response = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Headers $headers -Body $formData
$accessToken = $response.access_token
# Define the compute Detach URL
$deleteUrl = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourcegroup/providers/Microsoft.MachineLearningServices/workspaces/$amlworkspace/computes/"+$amlAttachedSynapseName+"?api-version=2023-06-01-preview&underlyingResourceAction=Detach"
# Send the DETACH request
$headers = @{ "Authorization" = "Bearer $accessToken" }
$response = Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers

# Delete Access Policy For Synapse On the Key Vault
# Retrive Provisioned Azure Synapse WS's Managed Identity For Revoking the Key Vault Access Policies
$synapseMI = az synapse workspace show --name $synapsewsname --resource-group $resourcegroup | Out-String
$synapseMI = $synapseMI | ConvertFrom-Json

# Delete the access policy for the specified Managed Identity from the Key Vault
az keyvault delete-policy --name $keyVaultName --object-id $synapseMI.identity.principalId --resource-group $resourcegroup


#Delete Spark Pool
$synapseSparkPoolDeleteStatus = az synapse spark pool delete --name $sparkPoolName --workspace-name $synapsewsname --resource-group $resourcegroup --yes | ConvertFrom-Json
Write-Output "Synapse Spark Pool $sparkPoolName Deleted state: $($synapseSparkPoolDeleteStatus.provisioningState)"

#Delete Synapse Workspace
$synapseWSDeleteStatus = az synapse workspace delete --name $synapsewsname --resource-group $resourcegroup --yes | ConvertFrom-Json
Write-Output "Synapse WS Delete state: $($synapseWSDeleteStatus.provisioningState)"

#Delete Synapse Associated Storage Account
$synapseStorageDeleteStatus = az storage account delete -n $synapsewsStorageName -g $resourcegroup --yes | ConvertFrom-Json
Write-Output "Synapse ADLS Gen2 Delete state: $($synapseStorageDeleteStatus.provisioningState)"

