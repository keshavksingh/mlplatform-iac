$clientId = "<>"
$clientSecret = "<>"
$tenantId = "<>"
$resourcegroup = "<>"
$subscription = "<>"
$synapsewsname = "<>"
$synapsewsStorageName = "<>"
$keyVaultName = "<>"
$sparkPoolName = "<>"
$amlAttachedSynapseName = "<>"
$amlworkspace = "<>"

# Log in to Azure using the service principal
az login --service-principal --username $clientId --password $clientSecret --tenant $tenantId

# Set the Azure subscription context (if you have multiple subscriptions)
az account set --subscription $subscription

#Detach Synapse Spark Pool from Azure ML Workspace
az ml compute detach --name $amlAttachedSynapseName `
                     --subscription $subscription `
                     --resource-group $resourcegroup `
                     --workspace-name $amlworkspace

#Delete Spark Pool
$synapseSparkPoolDeleteStatus = az synapse spark pool delete --name $sparkPoolName --workspace-name $synapsewsname --resource-group $resourcegroup
Write-Output "Synapse Spark Pool $sparkPoolName Deleted state: $($synapseSparkPoolDeleteStatus.provisioningState)"

$synapseWSDeleteStatus = az synapse workspace delete --name $synapsewsname --resource-group $resourcegroup --yes | ConvertFrom-Json
Write-Output "Synapse WS Delete state: $($synapseWSDeleteStatus.provisioningState)"

#Delete Synapse Associated Storage Account
$synapseStorageDeleteStatus = az storage account delete -n $synapsewsStorageName -g $resourcegroup | ConvertFrom-Json
Write-Output "Synapse ADLS Gen2 Delete state: $($synapseStorageDeleteStatus.provisioningState)"

# Delete Access Policy For Synapse On the Key Vault
# Retrive Provisioned Azure Synapse WS's Managed Identity For Revoking the Key Vault Access Policies
$securePassword = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$psCredential = New-Object System.Management.Automation.PSCredential($clientId, $securePassword)
Connect-AzAccount -ServicePrincipal -TenantId $tenantId -Credential $psCredential
Select-AzSubscription -SubscriptionId $subscription
$workspaceInfo = Get-AzSynapseWorkspace -ResourceGroupName $resourcegroup -Name $synapsewsname
$managedIdentity = $workspaceInfo.Identity
$synapseMI = $managedIdentity.PrincipalId

# Delete the access policy for the specified Managed Identity from the Key Vault
Remove-AzKeyVaultAccessPolicy -VaultName $keyVaultName -ObjectId $synapseMI
