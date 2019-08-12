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

# namespace is optional. If provided, limit result to namespace
if ($null -ne $Request.Params.namespace) {
  Write-Host "Filtered by namespace: $($Request.Params.namespace)"
  $modules = Get-TFModule -Table $table -Namespace $Request.Params.namespace |
    Group-Object -Property id |
    ForEach-Object {
      $_.group | Sort-Object -Property version -Descending | Select-Object -First 1
    }
} else {
  $modules = Get-TFModule -Table $table |
    Group-Object -Property id |
    ForEach-Object {
      $_.group | Sort-Object -Property version -Descending | Select-Object -First 1
    }
}

# optional query parameter, provider, If provided, limit result to provider
if ($null -ne $Request.Query.provider) {
  Write-Host "Filtered by provider: $($Request.Query.provider)"
  $modules = $modules | Where-Object -FilterScript { $_.Provider -eq $Request.Query.provider }
}

$body = @{
  modules = @($modules | ForEach-Object -Process { $_.ToTFPublicModule() })
} | ConvertTo-Json

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $body
    ContentType = 'application/json'
  })
