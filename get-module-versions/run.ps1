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

$modules = Get-TFModule -Table $table -Id $moduleId |
  Sort-Object -Property version -Descending

#body (iwr https://registry.terraform.io/v1/modules/Azure/vnet/azurerm/versions).content | clip

if ($null -eq $modules) {
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::NotFound
      Body = '{"errors":["Not Found"]}'
    })
} else {
  # build return json
  $versionList = [System.Collections.ArrayList]::new()
  foreach ($m in $modules) {
    [void] $versionList.Add(
      @{
        version = $m.version.ToString()
        root = @{
          providers = @(
            @{
              name = $m.provider
              version = ''
            }
          )
          dependencies = @()
        }
        submodules = @()
      }
    )
  }

  $body = @{
    modules = @(
      @{
        source = $modules[0].Id
        versions = $versionList
      }
    )
  } | ConvertTo-Json -Depth 10 -Compress

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $body
    ContentType = 'application/json'
  })
}
