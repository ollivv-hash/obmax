<#
.SYNOPSIS
  Builds and prepares an OB Max release (Android mobile + Android TV).

.DESCRIPTION
  1. Bumps the version in pubspec.yaml (versionCode = previous + 1, shared by both flavors).
  2. Builds the signed release APKs (arm64; -Armv7 adds 32-bit ARM to the same APKs).
  3. Renames them, computes their SHA-256 and writes version.json into dist\v<Version>\.
  4. Shows a summary and asks before `gh release create` on the public releases repo.

.EXAMPLE
  .\tools\release.ps1 -Version 1.0.1 -Notes "Corrections et améliorations."
.EXAMPLE
  .\tools\release.ps1 -Version 1.0.0 -VersionCode 1 -NoPublish
.EXAMPLE
  .\tools\release.ps1 -Version 1.1.0 -Notes "Nouvelle version obligatoire." -Mandatory
#>
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [string]$Notes = 'Corrections et améliorations.',
    [switch]$Mandatory,
    [switch]$Armv7,
    [string]$ReleasesRepo = 'ollivv-hash/obmax-releases',
    # Explicit versionCode (default: previous + 1), e.g. 1 for the very first release.
    [int]$VersionCode = 0,
    # Build, checksums and version.json only: no publication, pubspec.yaml restored afterwards.
    [switch]$NoPublish,
    # Only for a throwaway test build: a debug-signed APK cannot update a release-signed install.
    [switch]$AllowDebugSigning
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
. "$PSScriptRoot\obmax_env.ps1"

# --- 0. Preconditions ---------------------------------------------------------
if (-not $AllowDebugSigning -and -not (Test-Path 'android\keystore.properties')) {
    throw "android\keystore.properties manquant : le build serait signé avec la clé debug et ne pourrait pas mettre à jour une installation existante. Voir RELEASE.md."
}
if ((Test-Path 'android\keystore.properties') -and (Select-String -Path 'android\keystore.properties' -Pattern 'A_REMPLACER' -Quiet)) {
    throw "android\keystore.properties contient encore A_REMPLACER : renseignez les mots de passe du keystore."
}
$dirty = git status --porcelain --untracked-files=no
if ($dirty) { Write-Warning "Le dépôt a des modifications non commitées :`n$dirty" }

# --- 1. Version bump ----------------------------------------------------------
$pubspecPath = Join-Path $root 'pubspec.yaml'
$pubspec = [System.IO.File]::ReadAllText($pubspecPath)
$m = [regex]::Match($pubspec, '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
if (-not $m.Success) { throw "Ligne 'version:' introuvable dans pubspec.yaml" }
$previous = "$($m.Groups[1].Value)+$($m.Groups[2].Value)"
$versionCode = if ($VersionCode -gt 0) { $VersionCode } else { [int]$m.Groups[2].Value + 1 }
$originalPubspec = $pubspec
$pubspec = [regex]::Replace($pubspec, '(?m)^version:.*$', "version: $Version+$versionCode")
$pubspec = [regex]::Replace($pubspec, '(?m)^(\s*)android_tv_version:.*$', "`${1}android_tv_version: $Version")
$pubspec = [regex]::Replace($pubspec, '(?m)^(\s*)android_tv_build_number:.*$', "`${1}android_tv_build_number: $versionCode")
[System.IO.File]::WriteAllText($pubspecPath, $pubspec, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Version : $previous -> $Version+$versionCode" -ForegroundColor Cyan

# --- 2. Builds ----------------------------------------------------------------
$platforms = if ($Armv7) { 'android-arm,android-arm64' } else { 'android-arm64' }
& $script:Flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get a échoué' }

$builds = @(
    @{ Flavor = 'mobile';    Key = 'mobile';    Out = 'app-mobile-release.apk';    Name = "obmax-mobile-$Version.apk" },
    @{ Flavor = 'androidTv'; Key = 'androidTv'; Out = 'app-androidtv-release.apk'; Name = "obmax-tv-$Version.apk" }
)
$dist = Join-Path $root "dist\v$Version"
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Force $dist | Out-Null

foreach ($b in $builds) {
    Write-Host "Build $($b.Flavor) ($platforms)..." -ForegroundColor Cyan
    & $script:Flutter build apk --release --flavor $b.Flavor --target-platform $platforms `
        "--dart-define=OBMAX_FLAVOR=$($b.Key)"
    if ($LASTEXITCODE -ne 0) { throw "Build $($b.Flavor) en échec" }
    $apk = Join-Path $root "build\app\outputs\flutter-apk\$($b.Out)"
    if (-not (Test-Path $apk)) { throw "APK introuvable : $apk" }
    Copy-Item $apk (Join-Path $dist $b.Name)
}

# --- 3. Checksums and version.json -------------------------------------------
$base = "https://github.com/$ReleasesRepo/releases/download/v$Version"
$assets = [ordered]@{}
foreach ($b in $builds) {
    $file = Join-Path $dist $b.Name
    $b.Sha = (Get-FileHash -Algorithm SHA256 $file).Hash.ToLowerInvariant()
    $b.Size = (Get-Item $file).Length
    $assets[$b.Key] = [ordered]@{ url = "$base/$($b.Name)"; sha256 = $b.Sha }
}
$versionJson = [ordered]@{
    versionName = $Version
    versionCode = $versionCode
    mandatory   = [bool]$Mandatory
    notes       = $Notes
    assets      = $assets
} | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText((Join-Path $dist 'version.json'), $versionJson, (New-Object System.Text.UTF8Encoding($false)))

# --- 4. Summary, then publish only on confirmation -----------------------------
Write-Host ''
Write-Host '=== Récapitulatif de la release ===' -ForegroundColor Yellow
Write-Host "Version      : $Version (versionCode $versionCode)"
Write-Host "Obligatoire  : $([bool]$Mandatory)"
Write-Host "Notes        : $Notes"
Write-Host "Dépôt        : $ReleasesRepo (public)"
foreach ($b in $builds) {
    Write-Host ("{0,-24} {1,8:N1} Mo  sha256 {2}" -f $b.Name, ($b.Size / 1MB), $b.Sha)
}
Write-Host "version.json : $(Join-Path $dist 'version.json')"
Write-Host ''

if ($NoPublish) {
    [System.IO.File]::WriteAllText($pubspecPath, $originalPubspec, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host 'Mode -NoPublish : rien n''est publié, pubspec.yaml est restauré. Les fichiers sont dans dist\.' -ForegroundColor Yellow
    exit 0
}

$files = @($builds | ForEach-Object { Join-Path $dist $_.Name }) + (Join-Path $dist 'version.json')
$ghArgs = @('release', 'create', "v$Version") + $files + @('--repo', $ReleasesRepo, '--title', "OB Max $Version", '--notes', $Notes)
Write-Host "Commande : gh $($ghArgs -join ' ')" -ForegroundColor DarkGray

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Warning "La CLI GitHub (gh) n'est pas installée : winget install GitHub.cli, puis gh auth login. Relancez ensuite la commande ci-dessus."
    exit 0
}
$answer = Read-Host 'Publier cette release ? (o/N)'
if ($answer -notmatch '^(o|oui|y|yes)$') {
    Write-Host 'Publication annulée. Les fichiers restent dans dist\.' -ForegroundColor Yellow
    exit 0
}
& gh @ghArgs
if ($LASTEXITCODE -ne 0) { throw 'gh release create a échoué' }
Write-Host "Publié. Pensez à commiter pubspec.yaml : git commit -am 'release: OB Max $Version'" -ForegroundColor Green
