param(
  [byte[]] $InputBlob,

  $TriggerMetadata
)

$stContext = New-AzStorageContext -ConnectionString $env:AzureWebJobsStorage
$table = (Get-AzStorageTable -Name $env:TFRegTableName -Context $stContext).CloudTable

# required info, rest is optional
@(
  'namespace',
  'name',
  'provider',
  'version'
).ForEach{
  if (-not ($_ -in $TriggerMetadata.Metadata.Keys)) {
    throw "invalid blob $($TriggerMetadata.Name), missing one of the required metadata values"
  }
}

$moduleId = $TriggerMetadata.Metadata['namespace'], $TriggerMetadata.Metadata['name'], $TriggerMetadata.Metadata['provider'] -join '/'
$modules = Get-TFModule -Table $table -Id $moduleId

# update to existing module version is published
if ($modules.Version -contains $TriggerMetadata.Metadata['version']) {
  $replaceModule = $modules | Where-Object -FilterScript {
    $_.Version -eq $TriggerMetadata.Metadata['version']
  }

  #$removeBlob = ($replaceModule.Link -split '/')[-1]
  #try {
  #  $null = Remove-AzStorageBlob -Context $stContext -Container $env:ModuleContainer -Blob $removeBlob -Force
  #} catch {
  #  Write-Error -Message "Failed to delete $removeBlob" -ErrorAction Continue
  #}

  $replaceModule.Link = $TriggerMetadata.Uri
  $replaceModule.Published_At = $TriggerMetadata.Properties.Created
  $replaceModule.Owner = $TriggerMetadata.Metadata['owner']
  $replaceModule.Description = $TriggerMetadata.Metadata['description']
  $replaceModule.Version = $TriggerMetadata.Metadata['version']

  Update-TFModule -Table $table -TFModule $replaceModule
} else {
  # new entry
  $insert = New-TFModuleObject -Namespace $TriggerMetadata.Metadata['namespace'] -Name $TriggerMetadata.Metadata['name'] -Provider $TriggerMetadata.Metadata['provider']
  $insert.Link = $TriggerMetadata.Uri
  $insert.Published_At = $TriggerMetadata.Properties.Created
  $insert.Owner = $TriggerMetadata.Metadata['owner']
  $insert.Description = $TriggerMetadata.Metadata['description']
  $insert.Version = $TriggerMetadata.Metadata['version']

  New-TFModule -Table $table -TFModule $insert
}
