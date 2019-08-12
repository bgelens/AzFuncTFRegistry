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
  Where-Object -FilterScript {
    $_.version -eq [version]$Request.Params.version
  }

if ($null -eq $module) {
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::NotFound
      Body = '{"errors":["Not Found"]}'
    })
} else {
  $sasArgs = @{
    Context = $st.Context
    Container = $env:ModuleContainer
    Permission = 'r'
    Blob = ($module.Link -split '/')[-1]
    ExpiryTime = [datetime]::UtcNow.AddHours(1)
  }
  $sasToken = New-AzStorageBlobSASToken @sasArgs

  #increment download count
  $module.Downloads++
  $null = Update-TFModule -Table $table -TFModule $module

  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::NoContent
      ContentType = 'text/plain'
      Headers = @{
        "X-Terraform-Get" = $module.Link + $sasToken
      }
      Body = [string]::Empty
    })
}
