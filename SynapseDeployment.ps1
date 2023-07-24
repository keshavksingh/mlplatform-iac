$clientId = "<>"
$clientSecret = "<>"
$tenantId = "<>"
$resourcegroup = "<>"
$subscription = "<>"
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
$amlAttachedSynapseName = "synparkpool"#$synapsewsname+"-"+$sparkPoolName #It can include letters, digits and dashes. It must start with a letter, end with a letter or digit, and be between 2 and 16 characters in length.
$roleName = "Synapse Administrator"

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
$securePassword = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$psCredential = New-Object System.Management.Automation.PSCredential($clientId, $securePassword)
Connect-AzAccount -ServicePrincipal -TenantId $tenantId -Credential $psCredential
Select-AzSubscription -SubscriptionId $subscription
$workspaceInfo = Get-AzSynapseWorkspace -ResourceGroupName $resourcegroup -Name $synapsewsname
$managedIdentity = $workspaceInfo.Identity
$synapseMI = $managedIdentity.PrincipalId

# Add Access Policies to AKV for Synapse
Set-AzKeyVaultAccessPolicy -VaultName $keyVaultName -ResourceGroupName $resourcegroup -ObjectId $synapseMI -PermissionsToSecrets all -BypassObjectIdValidation

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

# Create Spark Pool
$createSparkPool = az synapse spark pool create --name $sparkPoolName `
--workspace-name $synapsewsname `
--resource-group $resourcegroup `
--spark-version $sparkVersion `
--node-count $sparkPoolNodeCount `
--node-size $sparkPoolNodeSize
#--spark-config-file-path 'path/configfile.txt'

#Attach Synapse Spark Pool to Azure Machine Learning Workspace, Make Sure To Install ml extension
#az extension remove -n azure-cli-ml
#az extension add -n ml
# YAML content
$yamlContent = @"
name: $amlAttachedSynapseName
type: synapsespark
resource_id: /subscriptions/$subscription/resourceGroups/$resourcegroup/providers/Microsoft.Synapse/workspaces/$synapsewsname/bigDataPools/$sparkPoolName
identity:
  type: system_assigned
"@

# Save the content to a YAML file
$yamlFilePath = "aml_synapse_compute_config.yaml"
$yamlContent | Out-File -FilePath $yamlFilePath -Encoding UTF8

# Use the created YAML file for AML attach
az ml compute attach --file $yamlFilePath `
                     --subscription $subscription `
                     --resource-group $resourcegroup `
                     --workspace-name $amlworkspace

# Delete the YAML file
Remove-Item $yamlFilePath

#Retrieve The Managed Identity of the AML Attached Synapse Compute

$attachedCompute = az ml compute show --name $amlAttachedSynapseName `
                                     --resource-group $resourcegroup `
                                     --workspace-name $amlworkspace

# Display the Managed Identity of the attached compute
$managedIdentity = $attachedCompute | ConvertFrom-Json
Write-Output "Managed Identity of the attached compute: $($managedIdentity.identity.principal_id)"

# Add this Managed Identity to the Synapse WS as Synapse Administrator
az synapse role assignment create `
  --workspace-name $synapsewsname `
  --role $roleName `
  --assignee $managedIdentity.identity.principal_id

# Completes Synapse Compute Deployment
