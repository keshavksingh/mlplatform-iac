$clientId = "<>"
$clientSecret = "<>"
$tenantId = "<>"
$resourcegroup = "<>"
$subscription = "<>"
$adfName = "<>"
$linkedServiceName = "LS_AML"
$ADFPipelineName = "PL_AML_MASTER"
$AdfTriggerName = "TR_OFFLINE_MODELX"

# Log in to Azure using the service principal
az login --service-principal --username $clientId --password $clientSecret --tenant $tenantId

# Set the Azure subscription context (if you have multiple subscriptions)
az account set --subscription $subscription

#Delete ADF Trigger
az datafactory trigger delete --factory-name $ADFPipelineName `
                              --resource-group $resourcegroup `
                              --name $AdfTriggerName `
                              --yes
#Delete ADF Pipeline
az datafactory pipeline delete --factory-name $adfName `
                               --name $ADFPipelineName `
                               --resource-group $resourcegroup `
                               --yes

#Delete ADF Linked Service
az datafactory linked-service delete --factory-name $ADFPipelineName `
                                     --name $linkedServiceName `
                                     --resource-group $resourcegroup `
                                     --yes
#Delete ADF
az datafactory delete --name $adfName --resource-group $resourcegroup --yes
