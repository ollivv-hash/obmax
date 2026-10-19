<#
.SYNOPSIS
  Writes the private OB Max build values, which git ignores.

.DESCRIPTION
  The server addresses and the application id identify the owner, so they
  stay out of the repository. This script writes them where each build reads
  them:
    lib/obmax/obmax_private.dart                   (Dart: server and enrollment URLs)
    android/obmax.properties                       (Gradle: applicationId)
    macos/Runner/Configs/ObMaxPrivate.xcconfig     (Xcode: bundle id)
  The desktop workflows write the same files from the repository secrets
  OBMAX_SERVER_URL, OBMAX_ENROLL_URL and OBMAX_APP_ID.

.EXAMPLE
  .\tools\obmax_private.ps1 -ServerUrl https://jellyfin.example.com -EnrollUrl https://enroll.example.com -AppId com.example.obmax
#>
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^https://[^/\s]+$')][string]$ServerUrl,
    [Parameter(Mandatory = $true)][ValidatePattern('^https://[^/\s]+$')][string]$EnrollUrl,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$')][string]$AppId
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)

[System.IO.File]::WriteAllText((Join-Path $root 'lib\obmax\obmax_private.dart'), @"
// Private OB Max build values (ignored by git), written by tools/obmax_private.ps1.
const kObMaxPrivateServerUrl = '$ServerUrl';
const kObMaxPrivateEnrollUrl = '$EnrollUrl';

"@.Replace("`r`n", "`n"), $utf8)

[System.IO.File]::WriteAllText((Join-Path $root 'android\obmax.properties'), @"
# Private OB Max build values (ignored by git), written by tools/obmax_private.ps1.
applicationId=$AppId

"@.Replace("`r`n", "`n"), $utf8)

[System.IO.File]::WriteAllText((Join-Path $root 'macos\Runner\Configs\ObMaxPrivate.xcconfig'), @"
// Private OB Max build values (ignored by git), written by tools/obmax_private.ps1.
PRODUCT_BUNDLE_IDENTIFIER = $AppId

"@.Replace("`r`n", "`n"), $utf8)

Write-Host 'Valeurs privées écrites (lib/obmax/obmax_private.dart, android/obmax.properties, macos/Runner/Configs/ObMaxPrivate.xcconfig).' -ForegroundColor Green
