$clientId = "<>"
$clientSecret = "<>"
$tenantId = "<>"
$resourcegroup = "<>"
$subscription ="<>"
$keyVaultName = "<>"
$synapsewsStorageName = "<>"
$synapsewsStoragefsName = "synapse"
$synapsewsLocation = "West US 2"
$synapsewsname = "<>"
$synapsewsSqlAdminLoginUserName = "<>"
$synapsewsSqlAdminLoginPassword = "<>"
$linkedServiceName = "LS_KV"
$sparkPoolName = "sparkpool"
$sparkPoolNodeSize = "Medium"
$sparkVersion ="3.3"
$sparkPoolNodeCount = "3"
$ruleName = "AllowAll"
$startIp = "0.0.0.0"
$endIp = "255.255.255.255"
$amlworkspace = "<>"
$amlAttachedSynapseName = "<>"  #$synapsewsname+"-"+$sparkPoolName #It can include letters, digits and dashes. It must start with a letter, end with a letter or digit, and be between 2 and 16 characters in length.
$roleName = "Synapse Administrator"

function getAccessToken{
  param(
    [string]$tenantId,
    [string]$clientId,
    [string]$clientSecret
  )
    $tokenEndpoint = "https://login.microsoftonline.com/$tenantId/oauth2/token"
    $body = @{"grant_type" = "client_credentials";"client_id" = $clientId;"client_secret" = $clientSecret;"resource" = "https://management.azure.com/"}
    # Convert the token request parameters to URL-encoded form data
    $formData = $body.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, [System.Web.HttpUtility]::UrlEncode($_.Value) }
    $formData = $formData -join "&"
    $headers = @{ "Content-Type" = "application/x-www-form-urlencoded" }
    $response = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Headers $headers -Body $formData
    $accessToken = $response.access_token
    return $accessToken
}


function attach_SynapseSparkPool
{
  param (
    [string]$amlAttachedSynapseName,
    [string]$subscriptionId,
    [string]$resourcegroup,
    [string]$synapsewsname,
    [string]$sparkPoolName,
    [string]$amlworkspace,
    [string]$roleName,
    [string]$location,
    [string]$tenantId,
    [string]$clientId,
    [string]$clientSecret
)
    #Attach Synapse Compute with System Assigned Managed Identity
    $accessToken = getAccessToken -tenantId $tenantId -clientId $clientId -clientSecret $clientSecret 
    # Define the compute attach URL
    $attachUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourcegroup/providers/Microsoft.MachineLearningServices/workspaces/$amlworkspace/computes/"+$amlAttachedSynapseName+"?api-version=2023-06-01-preview"
    # Define the compute attach payload
    $payload = @{"location"=$location;"identity"= @{"type"="SystemAssigned"};"properties" = @{"computeType" = "SynapseSpark";"isAttachedCompute" = "true";"resourceId"="/subscriptions/$subscription/resourceGroups/$resourcegroup/providers/Microsoft.Synapse/workspaces/$synapsewsname/bigDataPools/$sparkPoolName"}}
    $jsonPayload = $payload | ConvertTo-Json
    $headers = @{ "Authorization" = "Bearer $accessToken"; "Content-Type" = "application/json" }
    $computeAttachStatus = Invoke-RestMethod -Uri $attachUrl -Method Put -Headers $headers -Body $jsonPayload

    #Retrieve The Managed Identity of the AML Attached Synapse Compute
    $accessToken = getAccessToken -tenantId $tenantId -clientId $clientId -clientSecret $clientSecret 
    $GetUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourcegroup/providers/Microsoft.MachineLearningServices/workspaces/$amlworkspace/computes/"+$amlAttachedSynapseName+"?api-version=2023-06-01-preview"
    $headers = @{ "Authorization" = "Bearer $accessToken" }
    $GetAttachedSynapseComputeStatus = Invoke-RestMethod -Uri $GetUrl -Method Get -Headers $headers
    $AttachedSynapseMI = $GetAttachedSynapseComputeStatus.identity.principalId

    # Add this Managed Identity to the Synapse WS as Synapse Administrator
    $addManagedIdentityStatus = az synapse role assignment create `
                                --workspace-name $synapsewsname `
                                --role $roleName `
                                --assignee $AttachedSynapseMI
    return $computeAttachStatus, $addManagedIdentityStatus
}

# Log in to Azure using the service principal
az login --service-principal --username $clientId --password $clientSecret --tenant $tenantId

# Set the Azure subscription context (if you have multiple subscriptions)
az account set --subscription $subscription

# Create the ADLS Gen2 account For Synapse WS
$synapseStorageStatus = az storage account create `
    --name $synapsewsStorageName `
    --resource-group $resourcegroup `
    --location $synapsewsLocation `
    --sku Standard_LRS `
    --kind StorageV2 `
    --t Account `
    --hns true  | ConvertFrom-Json

Write-Output "Synapse ADLS Storage Provisioning state: $($synapseStorageStatus.provisioningState)"

# Create ADLS Gen2 File System (Container)
$synapseStorageFSStatus = az storage fs create -n $synapsewsStoragefsName `
                                               --account-name $synapsewsStorageName --auth-mode login  | ConvertFrom-Json

Write-Output "Synapse ADLS File System Provisioning state: $($synapseStorageFSStatus.provisioningState)"

# Provision Azure Synapse
$workspaceStatus = az synapse workspace create --name $synapsewsname --resource-group $resourcegroup `
                            --storage-account $synapsewsStorageName --file-system $synapsewsStoragefsName `
                            --sql-admin-login-user $synapsewsSqlAdminLoginUserName --sql-admin-login-password $synapsewsSqlAdminLoginPassword `
                            --location $synapsewsLocation | ConvertFrom-Json

# Add network firewall rule

az synapse workspace firewall-rule create --name $ruleName `
                                          --resource-group $resourcegroup `
                                          --workspace-name $synapsewsname `
                                          --start-ip-address $startIp `
                                          --end-ip-address $endIp

Write-Output "Synapse WS Provisioning state: $($workspaceStatus.provisioningState)"

# Retrive Provisioned Azure Synapse WS's Managed Identity For Adding to Key Vault Access Policies
$synapseMI = az synapse workspace show --name $synapsewsname --resource-group $resourcegroup | Out-String
$synapseMI = $synapseMI | ConvertFrom-Json

# Add Access Policies to AKV for Synapse
az keyvault set-policy --name $keyVaultName `
                       --resource-group $resourcegroup `
                       --object-id $synapseMI.identity.principalId `
                       --secret-permissions get list set delete backup restore recover purge

# Create Spark Pool
$createSparkPool = az synapse spark pool create --name $sparkPoolName `
--workspace-name $synapsewsname `
--resource-group $resourcegroup `
--spark-version $sparkVersion `
--node-count $sparkPoolNodeCount `
--node-size $sparkPoolNodeSize

# Create the Linked Service in Azure Synapse Analytics
$linkedServiceProperties = @{"name"= "$linkedServiceName"
              "properties"= @{
                                type = "AzureKeyVault"
                                typeProperties = @{
                                    baseUrl = "https://$keyVaultName.vault.azure.net"
                                }
                             }
                            }

$jsonString = $linkedServiceProperties | ConvertTo-Json
$jsonFile = "linkedServiceProperties.json"
$jsonString | Out-File -FilePath $jsonFile -Encoding UTF8
$linkedService = az synapse linked-service create --file @$jsonFile `
                                                  --name $linkedServiceName `
                                                  --workspace-name $synapsewsname

Remove-Item $jsonFile

$computeAttachStatus, $addManagedIdentityStatus = attach_SynapseSparkPool -amlAttachedSynapseName $amlAttachedSynapseName `
                                                                          -subscriptionId $subscription `
                                                                          -resourcegroup $resourcegroup `
                                                                          -synapsewsname $synapsewsname `
                                                                          -sparkPoolName $sparkPoolName `
                                                                          -amlworkspace $amlworkspace `
                                                                          -roleName $roleName `
                                                                          -location $synapsewsLocation `
                                                                          -tenantId $tenantId `
                                                                          -clientId $clientId `
                                                                          -clientSecret $clientSecret

# Completes Synapse Compute Deployment



