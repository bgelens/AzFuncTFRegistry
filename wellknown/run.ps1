using namespace System.Net

param($Request, $TriggerMetadata)

$body = @{
    "modules.v1" = "/v1/modules"
} | ConvertTo-Json


Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $body
    ContentType = 'application/json'
})
