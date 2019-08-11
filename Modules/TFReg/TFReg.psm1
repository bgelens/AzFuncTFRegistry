#requires -module @{ModuleName = 'Az.Storage'; ModuleVersion = '1.1.0'}
#requires -version 6.0

using module Az.Storage
using namespace Microsoft.Azure.Cosmos.Table

$partitionKey = 'tfreg'

class TFPublicModule {
  [string] $Id

  [string] $Description

  [string] $Owner

  [string] $Namespace

  [string] $Name

  [string] $Version

  [string] $Provider

  [System.DateTimeOffset] $Published_At

  [uint32] $Downloads

  TFPublicModule ([TFModule] $TFRegRow) {
    $this.Description = $TFRegRow.Description
    $this.Downloads = $TFRegRow.Downloads
    $this.Id = $TFRegRow.Id, $TFRegRow.Version -join '/'
    $this.Name = $TFRegRow.Name
    $this.Namespace = $TFRegRow.Namespace
    $this.Owner = $TFRegRow.Owner
    $this.Provider = $TFRegRow.Provider
    $this.Published_At = $TFRegRow.Published_At
    $this.Version = $TFRegRow.Version
  }
}

class TFModule {
  hidden [string] $PartitionKey

  [string] $RowKey

  [System.DateTimeOffset] $Timestamp

  hidden [string] $ETag

  [string] $Id

  [string] $Description

  [string] $Owner

  [string] $Namespace

  [string] $Name

  [version] $Version

  [string] $Provider

  [System.DateTimeOffset] $Published_At

  [uint32] $Downloads

  [string] $Link

  TFModule ([string] $namespace, [string] $name, [string] $provider) {
    $this.RowKey = [guid]::NewGuid().Guid
    $this.PartitionKey = $script:partitionKey
    $this.Namespace = $namespace
    $this.Name = $name
    $this.Provider = $provider
    $this.Id = $namespace, $name, $provider -join '/'
    $this.Published_At = [System.DateTimeOffset]::Now
  }

  TFModule ([DynamicTableEntity]$Entity) {
    $this.PartitionKey = $Entity.PartitionKey
    $this.RowKey = $Entity.RowKey
    $this.Timestamp = $Entity.Timestamp
    $this.ETag = $Entity.ETag
    $this.Description = $Entity.Properties['Description'].StringValue
    $this.Downloads = $Entity.Properties['Downloads'].Int32Value
    $this.Link = $Entity.Properties['Link'].StringValue
    $this.Name = $Entity.Properties['Name'].StringValue
    $this.Namespace = $Entity.Properties['Namespace'].StringValue
    $this.Owner = $Entity.Properties['Owner'].StringValue
    $this.Provider = $Entity.Properties['Provider'].StringValue
    $this.Published_At = $Entity.Properties['Published_At'].DateTimeOffsetValue
    $this.Version = $Entity.Properties['Version'].StringValue
    $this.Id = $Entity.Properties['Id'].StringValue
  }

  [DynamicTableEntity] UpdateEntity() {
    $update = [DynamicTableEntity]::new($this.PartitionKey, $this.RowKey)
    @(
      'Description', 'Owner', 'Namespace', 'Name', 'Provider', 'Link', 'Id'
    ).ForEach{
      if ($null -eq $this."$_") {
        $update.Properties.Add($_, [string]::Empty)
      } else {
        $update.Properties.Add($_, $this."$_")
      }
    }
    $update.Properties.Add('Version', [EntityProperty]::GeneratePropertyForString($this.Version))
    $update.Properties.Add('Downloads', [EntityProperty]::GeneratePropertyForInt($this.Downloads))
    $update.Properties.Add('Published_At', [EntityProperty]::GeneratePropertyForDateTimeOffset($this.Published_At))
    return $update
  }

  [TableEntity] GetEntity() {
    $entity = [TableEntity]::new($this.PartitionKey, $this.RowKey)
    $entity.ETag = $this.ETag
    return $entity
  }

  [TFPublicModule] ToTFPublicModule () {
    return [TFPublicModule]::new($this)
  }
}

function Get-TFModule {
  [OutputType([TFModule])]
  [CmdletBinding(DefaultParameterSetName = 'all')]
  param (
    [Parameter(Mandatory)]
    [CloudTable] $Table,

    [Parameter(Mandatory, ParameterSetName = 'byNamespace')]
    [AllowEmptyString()]
    [string] $Namespace,

    [Parameter(Mandatory, ParameterSetName = 'byId')]
    [string] $Id
  )

  $tableQuery = [TableQuery]::new()

  $TableQuery.FilterString = switch ($PSCmdlet.ParameterSetName) {
    byNamespace {
      [TableQuery]::GenerateFilterCondition(
        'Namespace',
        [QueryComparisons]::Equal,
        $Namespace
      )
    }
    byId {
      [TableQuery]::GenerateFilterCondition(
        'Id',
        [QueryComparisons]::Equal,
        $Id
      )
    }
  }

  if (-not [string]::IsNullOrEmpty($TableQuery.FilterString)) {
    Write-Verbose -Message "Using Filter: $($TableQuery.FilterString)"
  }

  if (($null -ne $TableQuery.FilterString) -or ($PSCmdlet.ParameterSetName -eq 'all')) {
    $Table.ExecuteQuery($tableQuery) | ForEach-Object -Process {
      [TFModule]::new($_)
    }
}
}

function New-TFModuleObject {
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
  [OutputType([TFModule])]
  param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $Namespace,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $Name,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $Provider
  )
  [TFModule]::new($Namespace, $Name, $Provider)
}

function Update-TFModule {
  [CmdletBinding(SupportsShouldProcess)]
  [Alias('New-TFModule')]
  param (
    [Parameter(Mandatory)]
    [CloudTable] $Table,

    [Parameter(Mandatory, ValueFromPipeline)]
    [TFModule] $TFModule,

    [Parameter()]
    [switch] $Replace
  )

  process {
    if ($Replace) {
      $operation = [TableOperation]::InsertOrReplace($TFModule.UpdateEntity())
    } else {
      $operation = [TableOperation]::InsertOrMerge($TFModule.UpdateEntity())
    }
    if ($PSCmdlet.ShouldProcess($operation.Entity.RowKey)) {
      $result = $Table.Execute(
        $operation
      )

      if ($result.HttpStatusCode -ne '204') {
        Write-Error -Message "Failed Table Operation for $($TFModule.ToTFPublicModule().Id). StatusCode: $($result.HttpStatusCode)" -ErrorAction Continue
      }
    }
  }
}

function Remove-TFModule {
  [CmdletBinding(SupportsShouldProcess)]
  param (
    [Parameter(Mandatory)]
    [CloudTable] $Table,

    [Parameter(Mandatory, ValueFromPipeline)]
    [TFModule] $TFModule
  )

  process {
    $operation = [TableOperation]::Delete($TFModule.GetEntity())
    if ($PSCmdlet.ShouldProcess($operation.Entity.RowKey)) {
      $result = $Table.Execute(
        $operation
      )

      if ($result.HttpStatusCode -ne '204') {
        Write-Error -Message "Failed Table Operation for $($TFModule.ToTFPublicModule().Id). StatusCode: $($result.HttpStatusCode)" -ErrorAction Continue
      }
    }
  }
}

Export-ModuleMember -Function *-TFModule* -Alias *-TFModule*
