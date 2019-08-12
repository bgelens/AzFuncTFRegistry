using namespace System.Net

param(
  $Request,
  $TriggerMetadata
)

if (-not (Test-AuthenticationKey -Headers $Request.Headers)) {
  return
}

$st = New-AzStorageContext -ConnectionString $env:AzureWebJobsStorage
$table = (Get-AzStorageTable -Context $st.Context -Name $env:TFRegTableName).CloudTable

$moduleId = $Request.Params.namespace, $Request.Params.name, $Request.Params.provider -join '/'

$module = Get-TFModule -Table $table -Id $moduleId |
  Sort-Object -Property version -Descending | Select-Object -First 1

if ($null -eq $module) {
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::NotFound
    Body = '{"errors":["Not Found"]}'
  })
} else {
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $module.ToTFPublicModule() | ConvertTo-Json -Compress
  })
}
