$clientId = "<>"
$clientSecret = "<>"
$tenantId = "<>"
$resourcegroup = "<>"
$subscription = "<>"
$amlworkspace = "<>"
$adfName = "<>"
$logAnalyticsWorkspace = "<>"
$logAnalyticsResourceId = "/subscriptions/$subscription/resourceGroups/$resourcegroup/providers/microsoft.operationalinsights/workspaces/$logAnalyticsWorkspace"
$linkedServiceName = "LS_AML"
$ADFPipelineName = "PL_AML_MASTER"
$AdfTriggerName = "TR_OFFLINE_MODELX"

# Log in to Azure using the service principal
az login --service-principal --username $clientId --password $clientSecret --tenant $tenantId

# Set the Azure subscription context (if you have multiple subscriptions)
az account set --subscription $subscription

#Provision Azure Data Factory and Integrated the Central Application Insights for Logger
$adfProvisionStatus = az datafactory create --resource-group $resourcegroup `
--factory-name $adfName | ConvertFrom-Json
Write-Output "Azure Datafactory Provisioning state: $($adfProvisionStatus.provisioningState)"
$adfResourceId = $adfProvisionStatus.id

$settingsName = "DataFactoryDiagnosticSettings"
$workspaceId = $logAnalyticsResourceId
$logCategories = "[{category:PipelineRuns,enabled:true,retention-policy:{enabled:false,days:0}},{category:TriggerRuns,enabled:true,retention-policy:{enabled:false,days:0}},{category:ActivityRuns,enabled:true,retention-policy:{enabled:false,days:0}}]"
$metrics = "[{category:AllMetrics,enabled:true,retention-policy:{enabled:false,days:0}}]"

az monitor diagnostic-settings create `
    --name $settingsName `
    --resource $adfResourceId `
    --resource-group $resourcegroup `
    --workspace $logAnalyticsResourceId `
    --logs $logCategories `
    --metrics $metrics

#Deploy Linked Service on the Provisoned ADF For the AML Workspace
# Create the Linked Service on ADF
$linkedServiceProperties = @{
                            "type"= "AzureMLService"
                            "typeProperties"= @{
                                "subscriptionId"= $subscription
                                "resourceGroupName"= $resourcegroup
                                "mlWorkspaceName"= $amlworkspace
                                "servicePrincipalId"= $clientId
                                "servicePrincipalKey"= @{
                                    "value"= $clientSecret
                                    "type"= "SecureString"
                                }
                                "tenant"= $tenantId
                            }
                        }


$jsonString = $linkedServiceProperties | ConvertTo-Json -Depth 10
$jsonFile = "linkedServiceProperties.json"
$jsonString | Out-File -FilePath $jsonFile -Encoding UTF8
az datafactory linked-service create --resource-group $resourcegroup `
    --factory-name $adfName --linked-service-name $linkedServiceName `
    --properties @$jsonFile
Remove-Item $jsonFile

#Deploy ADF Master Pipeline
$masterpipeline = @"
{
    "activities": [
        {
            "name": "Machine Learning Execute Pipeline",
            "type": "AzureMLExecutePipeline",
            "dependsOn": [],
            "policy": {
                "timeout": "7.00:00:00",
                "retry": 0,
                "retryIntervalInSeconds": 30,
                "secureOutput": false,
                "secureInput": false
            },
            "userProperties": [],
            "typeProperties": {
                "mlPipelineParameters": {
                    "BatchRunCorrelationId": {
                        "value": "@pipeline().RunId",
                        "type": "Expression"
                    },
                    "ADFPipeline": {
                        "value": "@pipeline().Pipeline",
                        "type": "Expression"
                    },
                    "TriggerName": {
                        "value": "@pipeline().TriggerName",
                        "type": "Expression"
                    },
                    "DatafactoryName": {
                        "value": "@pipeline().DataFactory",
                        "type": "Expression"
                    }
                },
                "mlExecutionType": "pipeline",
                "mlPipelineId": {
                    "value": "@pipeline().parameters.AMLPipelineId",
                    "type": "Expression"
                }
            },
            "linkedServiceName": {
                "referenceName": "$linkedServiceName",
                "type": "LinkedServiceReference"
            }
        }
    ],
    "parameters": {
        "WindowStart": {
          "type": "string",
          "defaultValue": ""
        },
        "WindowEnd": {
          "type": "string",
          "defaultValue": ""
        },
        "AMLPipelineId": {
            "type": "string",
            "defaultValue": ""
        }
    }
}
"@

$jsonMasterPipelineFile = "masterpipeline.json"
$masterpipeline | Out-File -FilePath $jsonMasterPipelineFile -Encoding UTF8
az datafactory pipeline create --factory-name $adfName `
                                --pipeline @$jsonMasterPipelineFile `
                                --name $ADFPipelineName `
                                --resource-group $resourcegroup
Remove-Item $jsonMasterPipelineFile

#Create ADF Trigger
#https://learn.microsoft.com/en-us/azure/data-factory/concepts-pipeline-execution-triggers
$TriggerProperties = @"
{
  "type": "ScheduleTrigger",
  "pipelines": [
     {
        "parameters": {
          "WindowStart": "@trigger().outputs.windowStartTime",
          "WindowEnd": "@trigger().outputs.windowEndTime",
          "AMLPipelineId": "AMLPipelineId"
        },
        "pipelineReference": {
           "type": "PipelineReference",
           "referenceName": "$ADFPipelineName"
        }
     }
  ],
  "typeProperties": {
     "recurrence": {
        "endTime": "2023-10-01T00:55:13.8441801Z",
        "frequency": "Day",
        "interval": 1,
        "startTime": "2023-08-01T00:39:13.8441801Z",
        "timeZone": "UTC"
     }
  }
}
"@

$jsonADFTriggerFile = "triggerpipeline.json"
$TriggerProperties | Out-File -FilePath $jsonADFTriggerFile -Encoding UTF8
az datafactory trigger create --factory-name $adfName `
                              --resource-group $resourcegroup `
                              --properties @$jsonADFTriggerFile `
                              --name $AdfTriggerName
Remove-Item $jsonADFTriggerFile
