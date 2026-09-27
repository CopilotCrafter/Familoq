<#
  Familoq - one-time CloudKit schema fix for family invitations (docs/11).

  Creates the system record type "cloudkit.share" in the CloudKit DEVELOPMENT
  environment by saving one test share through Apple's CloudKit Web Services
  (api.apple-cloudkit.com). Only Apple services are used - no extra apps.
  Afterwards: CloudKit Console -> Development -> Deploy Schema Changes.

  Run in Windows PowerShell:
     powershell -ExecutionPolicy Bypass -File .\cloudkit-share-schema.ps1
#>
$ErrorActionPreference = 'Stop'
$container = 'iCloud.com.carolandmartin.familoq'
$base = "https://api.apple-cloudkit.com/database/1/$container/development/private"
$zoneName = 'schema-bootstrap'

Write-Host ''
Write-Host 'Familoq - prepare iCloud for family invitations (Development environment)' -ForegroundColor Cyan
$apiToken = ((Read-Host 'Paste the CloudKit API token (step 1 in docs/11)') -replace '[^0-9a-fA-F]', '')
Write-Host "Token: $($apiToken.Length) characters"
if ($apiToken.Length -ne 64) {
    Write-Host 'An API token is 64 characters (0-9, a-f). Copy it again from the CloudKit Console.' -ForegroundColor Red
    exit 1
}
$script:webToken = $null

function Invoke-CK([string]$Method, [string]$Path, $Body) {
    $url = "$base/$Path" + "?ckAPIToken=$apiToken"
    if ($script:webToken) { $url += '&ckWebAuthToken=' + [Uri]::EscapeDataString($script:webToken) }
    $params = @{ Uri = $url; Method = $Method; UseBasicParsing = $true; ContentType = 'application/json' }
    if ($null -ne $Body) { $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress) }
    $headers = $null
    try {
        $response = Invoke-WebRequest @params
        $text = $response.Content
        $headers = $response.Headers
    } catch {
        $text = $_.ErrorDetails.Message
        if (-not $text -and $_.Exception.Response) {
            try {
                $reader = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
                $text = $reader.ReadToEnd()
            } catch { }
        }
        if (-not $text) { throw }
    }
    # Apple hands out a fresh web token with each response.
    if ($headers) {
        $fresh = $headers['X-Apple-CloudKit-Web-Auth-Token']
        if ($fresh) { $script:webToken = [string](@($fresh)[0]) }
    }
    $json = $text | ConvertFrom-Json
    if ($json.ckWebAuthToken) { $script:webToken = [string]$json.ckWebAuthToken }
    return $json
}

function Assert-OK($Result, [string]$What) {
    $bad = @()
    if ($Result.serverErrorCode) { $bad += "$($Result.serverErrorCode): $($Result.reason)" }
    foreach ($item in @($Result.records) + @($Result.zones)) {
        if ($item -and $item.serverErrorCode) { $bad += "$($item.serverErrorCode): $($item.reason)" }
    }
    if ($bad.Count -gt 0) {
        Write-Host "X $What failed: $($bad -join '; ')" -ForegroundColor Red
        exit 1
    }
    Write-Host "OK $What" -ForegroundColor Green
}

# 1. Sign in with your Apple Account (the one that owns the family).
$first = Invoke-CK 'GET' 'users/current' $null
if (-not $first.redirectURL) {
    Write-Host "Unexpected answer: $($first | ConvertTo-Json -Compress)" -ForegroundColor Red
    if ($first.serverErrorCode -eq 'AUTHENTICATION_FAILED') {
        Write-Host 'Apple does not know this token in the DEVELOPMENT environment.' -ForegroundColor Yellow
        Write-Host 'API tokens belong to one environment: in the CloudKit Console switch the environment'
        Write-Host '(top of the page) to DEVELOPMENT first, then Tokens & Keys -> API Tokens -> + (docs/11 step 1).'
    }
    exit 1
}
Write-Host ''
Write-Host 'Your browser opens the Apple sign-in. Sign in with YOUR Apple Account.'
Write-Host 'Afterwards the browser shows an error page for "localhost" - that is expected.'
Write-Host 'Copy the COMPLETE address from the address bar (it contains ckWebAuthToken=...).'
Start-Process $first.redirectURL
$pasted = (Read-Host 'Paste the address here').Trim()
if ($pasted -notmatch 'ckWebAuthToken=([^&#]+)') {
    Write-Host 'No ckWebAuthToken found in that address.' -ForegroundColor Red
    exit 1
}
$script:webToken = [Uri]::UnescapeDataString($Matches[1])

$me = Invoke-CK 'GET' 'users/current' $null
Assert-OK $me 'Signed in'

# 2. Test zone
$zone = Invoke-CK 'POST' 'zones/modify' @{ operations = @(@{ operationType = 'create'; zone = @{ zoneID = @{ zoneName = $zoneName } } }) }
Assert-OK $zone 'Test zone created'

try {
    # 3. Test record (record type FQFamilyItem already exists, docs/10)
    $recordName = 'family-' + [guid]::NewGuid().ToString().ToUpper()
    $rec = Invoke-CK 'POST' 'records/modify' @{
        operations = @(@{
            operationType = 'create'
            record = @{
                recordType = 'FQFamilyItem'
                recordName = $recordName
                # Shared records need a short GUID ("stable URL").
                createShortGUID = $true
                fields = @{ kind = @{ value = 'family' }; payload = @{ value = '{}' } }
            }
        })
        zoneID = @{ zoneName = $zoneName }
    }
    Assert-OK $rec 'Test record saved'
    $changeTag = $rec.records[0].recordChangeTag
    if (-not $rec.records[0].shortGUID) {
        # Older behaviour: ask for the short GUID with an update.
        $upd = Invoke-CK 'POST' 'records/modify' @{
            operations = @(@{
                operationType = 'update'
                record = @{ recordType = 'FQFamilyItem'; recordName = $recordName; recordChangeTag = $changeTag; createShortGUID = $true; fields = @{ kind = @{ value = 'family' } } }
            })
            zoneID = @{ zoneName = $zoneName }
        }
        Assert-OK $upd 'Test record got a share link'
        $changeTag = $upd.records[0].recordChangeTag
    }

    # 4. Test share -> creates the record type cloudkit.share
    $share = Invoke-CK 'POST' 'records/modify' @{
        operations = @(@{
            operationType = 'create'
            record = @{
                recordType = 'cloudkit.share'
                createShortGUID = $true
                fields = @{}
                forRecord = @{ recordName = $recordName; recordChangeTag = $changeTag }
                publicPermission = 'NONE'
            }
        })
        zoneID = @{ zoneName = $zoneName }
    }
    Assert-OK $share 'Test share saved - cloudkit.share now exists in Development'
}
finally {
    # 5. Clean up
    $del = Invoke-CK 'POST' 'zones/modify' @{ operations = @(@{ operationType = 'delete'; zone = @{ zoneID = @{ zoneName = $zoneName } } }) }
    if (-not $del.serverErrorCode) { Write-Host 'OK Test zone deleted again' -ForegroundColor Green }
}

Write-Host ''
Write-Host 'Done. Now: CloudKit Console -> Development -> Schema -> Record Types shows cloudkit.share' -ForegroundColor Cyan
Write-Host '-> Deploy Schema Changes -> Deploy. Then invite again in Familoq.' -ForegroundColor Cyan
