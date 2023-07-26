$clientId = "<>"
$clientSecret = "<>"
$tenantId = "<>"
$resourcegroup = "<>"
$adbwsname = "<>"
$subscription = "<>"
$amlworkspace = "<>"
$adbWorkspaceName = "<>"
$amlAttachedAdbName = "adbcompute"
$subscription = "<>"
$location = "West US 2"

# Log in to Azure using the service principal
az login --service-principal --username $clientId --password $clientSecret --tenant $tenantId

# Set the Azure subscription context (if you have multiple subscriptions)
az account set --subscription "<>"

$location = "East US 2"
$sku = "premium"

# Create the Azure Databricks workspace
az config set extension.use_dynamic_install=yes_without_prompt
Write-Output "Provisioning Azure Databricks workspace..."
az databricks workspace create --resource-group $resourcegroup `
                               --name $adbwsname `
                               --location $location `
                               --sku $sku

#Provision ADB WS
$workspaceStatus = az databricks workspace show --resource-group $resourcegroup --name $adbwsname --output json
$workspaceStatus = $workspaceStatus | ConvertFrom-Json
$provisioningState = $workspaceStatus.provisioningState
Write-Output "Provisioning state: $($workspaceStatus.provisioningState)"

#Check Status and Report Appropriately
if ($provisioningState -eq "Succeeded") {
    Write-Output "Azure Databricks workspace provisioning succeeded!"
    Write-Output "Workspace ID: $($workspaceStatus.workspaceId)"
    Write-Output "Managed Resource Group: $($workspaceStatus.managedResourceGroupId)"
    Write-Output "Endpoint: $($workspaceStatus.workspaceUrl)"
    #Generate ADB Secret Token
    $DATABRICKS_TOKEN = (az account get-access-token --resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" | ConvertFrom-Json).accessToken
    $DATABRICKS_HOST = "https://" + $workspaceStatus.workspaceUrl
    $apiUrl = "$DATABRICKS_HOST/api/2.0/token/create"
    $tokenData = @{comment = "SecretToken"} | ConvertTo-Json
    $headers = @{Authorization = "Bearer $DATABRICKS_TOKEN"; ContentType = "application/json"}
    $result = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $tokenData -Headers $headers

    # Get the generated secret token value And Add it to the Spoke AML Key Vault
    $secretToken = $result.token_value
    Write-Output "Azure Databricks secret token created successfully."
    Write-Output "Secret Token: $secretToken"

    $keyVaultName = "<>"
    $secretName = $adbwsname+"-token"
    $secretValue = $secretToken

    # Add the secret to the Key Vault
    az keyvault secret set --name $secretName --vault-name $keyVaultName --value $secretValue
    Write-Output "Secret '$secretName' has been added to Key Vault '$keyVaultName'."

    # Get Key Vault ResourceId and Add the ResourceId to the Azure Databricks secret scope with the name "secret"
    $keyVaultName = "<>"
    $keyVaultResourceId=$(az keyvault show --name $keyVaultName --query id --output tsv)

    $secretScopeName = "secret"
    $kv_dns_name="https://$keyVaultName.vault.azure.net/"
    $metadata = @{resource_id = $keyVaultResourceId;dns_name=$kv_dns_name}
    $DATABRICKS_TOKEN = (az account get-access-token --resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" | ConvertFrom-Json).accessToken
    $DATABRICKS_HOST = "https://" + $workspaceStatus.workspaceUrl
    $apiUrl = "$DATABRICKS_HOST/api/2.0/secrets/scopes/create"
    $tokenData = @{scope = $secretScopeName;initial_manage_principal = "users";scope_backend_type = "AZURE_KEYVAULT";backend_azure_keyvault = $metadata} | ConvertTo-Json
    $headers = @{Authorization = "Bearer $DATABRICKS_TOKEN"; ContentType = "application/json"}
    $result = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $tokenData -Headers $headers
    Write-Output "Databricks secret scope for Keyvvault $kv_dns_name created successfully with the name: $secretScopeName"

    # Create ADB Cluster Add a Environment Variable secretscope=secret

    $DATABRICKS_TOKEN = (az account get-access-token --resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" | ConvertFrom-Json).accessToken
    $DATABRICKS_HOST = "https://" + $workspaceStatus.workspaceUrl
    $apiUrl = "$DATABRICKS_HOST/api/2.0/clusters/create"

    $clusterData ='{
                        "autoscale": {
                            "min_workers": 2,
                            "max_workers": 2
                        },
                        "cluster_name": "cluster",
                        "spark_version": "12.2.x-scala2.12",
                        "spark_conf": {},
                        "azure_attributes": {
                            "first_on_demand": 1,
                            "availability": "ON_DEMAND_AZURE",
                            "spot_bid_max_price": -1
                        },
                        "node_type_id": "Standard_DS3_v2",
                        "ssh_public_keys": [],
                        "custom_tags": {},
                        "spark_env_vars": {
                            "PYSPARK_PYTHON": "/databricks/python3/bin/python3",
                            "secretscope": "secret"
                        },
                        "autotermination_minutes": 120,
                        "cluster_source": "UI",
                        "init_scripts": [],
                        "data_security_mode": "NONE",
                        "runtime_engine": "STANDARD"
                    }'

    $clusterData = ConvertFrom-Json $clusterData
    $clusterData = $clusterData | ConvertTo-Json
    $headers = @{Authorization = "Bearer $DATABRICKS_TOKEN"; ContentType = "application/json"}
    $result = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $clusterData -Headers $headers
    $adb_clusterid=$result.cluster_id
    Write-Output "Databricks Compute Cluster created successfully ClusterID: $adb_clusterid"

} elseif ($provisioningState -eq "Failed") {
    Write-Output "Azure Databricks workspace provisioning failed."
}
#Test On ADB by Simply
#import os
#secretscope = os.environ['secretscope']
#print(dbutils.secrets.get(scope = secretscope, key = "adbmlopseus02-token"))

# Attach the ADB Instance to the AML WorkSpace
#https://learn.microsoft.com/en-us/rest/api/azureml/2023-06-01-preview/compute/create-or-update?tabs=HTTP#databricksproperties
#https://learn.microsoft.com/en-us/azure/templates/microsoft.machinelearningservices/workspaces/computes?pivots=deployment-language-bicep

$tokenEndpoint = "https://login.microsoftonline.com/$tenantId/oauth2/token"
$body = @{"grant_type" = "client_credentials";"client_id" = $clientId;"client_secret" = $clientSecret;"resource" = "https://management.azure.com/"}
# Convert the token request parameters to URL-encoded form data
$formData = $body.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, [System.Web.HttpUtility]::UrlEncode($_.Value) }
$formData = $formData -join "&"
$headers = @{ "Content-Type" = "application/x-www-form-urlencoded" }
$response = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Headers $headers -Body $formData
$accessToken = $response.access_token
# Define the compute attach URL
$attachUrl = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourcegroup/providers/Microsoft.MachineLearningServices/workspaces/$amlworkspace/computes/"+$amlAttachedAdbName+"?api-version=2023-06-01-preview"
# Define the compute attach payload
$payload = @{"location"=$location;"properties" = @{"computeType" = "Databricks";"isAttachedCompute" = "true";"properties" = @{"databricksAccessToken" = $secretValue;"workspaceUrl" = "https://" + $workspaceStatus.workspaceUrl};"resourceId"="/subscriptions/$subscription/resourceGroups/$resourcegroup/providers/Microsoft.Databricks/workspaces/$adbWorkspaceName"}}
$jsonPayload = $payload | ConvertTo-Json
$headers = @{ "Authorization" = "Bearer $accessToken"; "Content-Type" = "application/json" }
$response = Invoke-RestMethod -Uri $attachUrl -Method Put -Headers $headers -Body $jsonPayload
