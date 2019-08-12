# Azure Function App: Terraform Registry

An Azure Function App written in PowerShell to host a Terraform Registry ([API Documentation](https://www.terraform.io/docs/registry/api.html)).

The app makes use of Azure Table and Blob storage using the account associated with the function app. Make sure the app is published using application settings as defined in this `local.settings.json` example:

```json
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "powershell",
    "AzureWebJobsStorage": "DefaultEndpointsProtocol=https;AccountName=mystorageaccount;AccountKey=storageaccountkey;EndpointSuffix=core.windows.net",
    "TFRegTableName": "TFReg",
    "ModuleContainer": "modules"
  }
}
```

Pre-create the Table and Container (with access policy private) defined in the application settings.

If you desire to use authentication keys with Terraform, add the application setting `authenticationKeys` and add values separated by `;`.

## Upload modules

Upload modules to the storage account directly. First create a tar.gz archive

```sh
tar -czvf mymodulearchive.tar.gz -C ./moduleFolder .
```

Next upload it to the storage container with additional metadata:

```powershell
$st = Get-AzStorageAccount -Name mystorageAccount -ResourceGroupName myRG
Set-AzStorageBlobContent -Container modules -Context $st.Context -File "./mymodulearchive.tar.gz" -Metadata @{
  description = 'My awesome module'
  owner = 'Me'
  namespace = 'Mynamespace'
  name = 'module-name'
  provider = 'azurerm'
  version = '1.0.0'
}
```

Once this is done, the `ingest-modules` function is triggered by a blob trigger which will add the module to the registry table (a module with the same version as one already in the registry will overwrite the module link to the new file).

## Quering the registry

Use the PowerShell module [TerraformRegistry](https://www.powershellgallery.com/packages/TerraformRegistry) to get data from the registry.

```powershell
Connect-TerraformRegistry -Url https://myregistry.azurewebsites.net
Get-TerraformModule
```

Note that the first time can be a little slow as the Function App needs to download the Az modules using DependencyManagement.

You can remove the dependency on DependencyManagement by using `Save-Module Az.Storage -Path ./Modules` and disabling the setting in `host.json`.

## Using the registry in Terraform

Add to your Terraform using:

* Explicit version

  ```tf
  module "vm01" {
    source              = "myregistry.azurewebsites.net/mynamespace/modulename/provider"
    version             = "1.0.0"
  }
  ```

* Latest version

  ```tf
  module "vm01" {
    source              = "myregistry.azurewebsites.net/mynamespace/modulename/provider"
  }
  ```

Run ```terraform init```

> When using Authentication keys you need to [add a configuration file](https://www.terraform.io/docs/cloud/registry/using.html#configuration) for Terraform containing a valid key.
