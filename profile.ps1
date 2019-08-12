using namespace System.Net

function Test-AuthenticationKey {
  param (
    $Headers
  )

  $authenticated = $true

  if ($null -ne $env:authenticationKeys) {
    $authenticationKeys = $env:authenticationKeys -split ';'
    if ($Headers.ContainsKey('Authorization')) {
      $authKey = ($Headers["Authorization"] -split ' ')[-1]
      if (-not ($authKey -in $authenticationKeys)) {
        $authenticated = $false
      }
    } else {
      $authenticated = $false
    }
  }

  if (-not $authenticated) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::Unauthorized
      Body = ''
    })
  }

  $authenticated
}
