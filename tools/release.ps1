<#
.SYNOPSIS
  Builds and prepares an OB Max release (Android mobile + Android TV).

.DESCRIPTION
  1. Bumps the version in pubspec.yaml (versionCode = previous + 1, shared by both flavors).
  2. Builds the signed release APKs, each holding both arm64-v8a and armeabi-v7a
     (32-bit TV boxes), and checks every native library exists for both.
     Once tools\rotate_signing_key.ps1 has run, re-signs them with the previous
     key, the new key and the rotation lineage, then checks both fingerprints.
  3. Renames them, computes their SHA-256 and writes version.json into dist\v<Version>\.
  4. Shows a summary and asks before `gh release create` on the public releases repo.
  With -MacOS and/or -Windows, the macOS .dmg and the Windows installer are
  built at the same time on GitHub Actions (.github/workflows/obmax-macos.yml,
  obmax-windows.yml, from the pushed code), then downloaded and published with
  the APKs; version.json lists them under assets.macos and assets.windows.

.EXAMPLE
  .\tools\release.ps1 -Version 1.0.1 -Notes "Corrections et améliorations."
.EXAMPLE
  .\tools\release.ps1 -Version 1.0.0 -VersionCode 1 -NoPublish
.EXAMPLE
  .\tools\release.ps1 -Version 1.1.0 -Notes "Nouvelle version obligatoire." -Mandatory
.EXAMPLE
  .\tools\release.ps1 -Version 2.1.0 -Notes "Arrivée des versions Mac et Windows." -MacOS -Windows
#>
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [string]$Notes = 'Corrections et améliorations.',
    [switch]$Mandatory,
    [string]$ReleasesRepo = 'ollivv-hash/obmax-releases',
    # Explicit versionCode (default: previous + 1), e.g. 1 for the very first release.
    [int]$VersionCode = 0,
    # Build, checksums and version.json only: no publication, pubspec.yaml restored afterwards.
    [switch]$NoPublish,
    # Publish without the confirmation prompt (the summary is still printed).
    [switch]$Yes,
    # Only for a throwaway test build: a debug-signed APK cannot update a release-signed install.
    [switch]$AllowDebugSigning,
    # Also build the macOS .dmg / the Windows installer on GitHub Actions, from
    # the code pushed to $SourceRepo.
    [switch]$MacOS,
    [switch]$Windows,
    [string]$SourceRepo = 'ollivv-hash/obmax'
)

# Not 'Stop': Windows PowerShell turns any stderr line of a native command
# (flutter prints warnings there) into a terminating error once the output
# is redirected. Failures are caught through $LASTEXITCODE and explicit throws.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
. "$PSScriptRoot\obmax_env.ps1"
. "$PSScriptRoot\obmax_signing.ps1"

# The ABIs every APK carries. A 32-bit box (armeabi-v7a only) crashes at launch
# on an arm64-only APK: "Could not find 'libflutter.so'".
$apkAbis = @('arm64-v8a', 'armeabi-v7a')

# Lists lib/<abi>/*.so in an APK. Throws when an ABI is missing, has no
# libflutter.so / libapp.so, or when another ABI folder is present (a device
# of that ABI would pick it and find no Flutter engine). Libraries present for
# one ABI only are returned, for the summary.
function Get-ObMaxApkAbiReport([string]$Apk) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $libs = @{}
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Apk)
    try {
        foreach ($e in $zip.Entries) {
            if ($e.FullName -match '^lib/([^/]+)/([^/]+\.so)$') {
                if (-not $libs.ContainsKey($Matches[1])) { $libs[$Matches[1]] = [System.Collections.Generic.SortedSet[string]]::new() }
                [void]$libs[$Matches[1]].Add($Matches[2])
            }
        }
    } finally { $zip.Dispose() }
    $name = Split-Path -Leaf $Apk
    $extra = @($libs.Keys | Where-Object { $_ -notin $apkAbis })
    if ($extra) { throw "$name contient une ABI inattendue : $($extra -join ', ')" }
    foreach ($abi in $apkAbis) {
        foreach ($so in 'libflutter.so', 'libapp.so') {
            if (-not $libs.ContainsKey($abi) -or -not $libs[$abi].Contains($so)) { throw "$name : $so absent de lib/$abi" }
        }
    }
    $arm64 = $libs['arm64-v8a']; $armv7 = $libs['armeabi-v7a']
    [pscustomobject]@{
        Arm64     = $arm64.Count
        Armv7     = $armv7.Count
        Arm64Only = @($arm64 | Where-Object { -not $armv7.Contains($_) })
        Armv7Only = @($armv7 | Where-Object { -not $arm64.Contains($_) })
    }
}

# --- 0. Preconditions ---------------------------------------------------------
if (-not $AllowDebugSigning -and -not (Test-Path 'android\keystore.properties')) {
    throw "android\keystore.properties manquant : le build serait signé avec la clé debug et ne pourrait pas mettre à jour une installation existante. Voir docs\obmax\RELEASE.md."
}
if ((Test-Path 'android\keystore.properties') -and (Select-String -Path 'android\keystore.properties' -Pattern 'A_REMPLACER' -Quiet)) {
    throw "android\keystore.properties contient encore A_REMPLACER : renseignez les mots de passe du keystore."
}
$signing = Read-ObMaxProperties
$rotation = Test-ObMaxRotation $signing
if ($rotation) {
    foreach ($f in 'previousStoreFile', 'lineageFile', 'storeFile') {
        if (-not (Test-Path $signing[$f])) { throw "$f introuvable : $($signing[$f])" }
    }
    $newSha = Get-CertSha256 $signing['storeFile'] $signing['keyAlias'] $signing['storePassword']
    $oldSha = Get-CertSha256 $signing['previousStoreFile'] $signing['previousKeyAlias'] $signing['previousStorePassword']
    if (-not $newSha -or -not $oldSha) { throw 'Impossible de lire les certificats de signature (mot de passe ?).' }
    Write-Host "Signature : rotation $(Format-Fingerprint $oldSha) -> $(Format-Fingerprint $newSha)" -ForegroundColor Cyan
}
$dirty = git status --porcelain --untracked-files=no
if ($dirty) { Write-Warning "Le dépôt a des modifications non commitées :`n$dirty" }

# gh may be installed but missing from the PATH of a shell opened before it.
$gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $gh -and (Test-Path "$env:ProgramFiles\GitHub CLI\gh.exe")) { $gh = "$env:ProgramFiles\GitHub CLI\gh.exe" }
$desktop = @()
if ($MacOS) { $desktop += @{ Label = 'macOS'; Workflow = 'obmax-macos.yml'; Artifact = 'obmax-macos'; Key = 'macos'; Name = "obmax-macos-$Version.dmg" } }
if ($Windows) { $desktop += @{ Label = 'Windows'; Workflow = 'obmax-windows.yml'; Artifact = 'obmax-windows'; Key = 'windows'; Name = "obmax-windows-$Version.exe" } }
if ($desktop) {
    if (-not $gh) { throw '-MacOS et -Windows demandent la CLI GitHub (gh).' }
    # GitHub Actions builds what is pushed, not this working copy.
    $branch = git rev-parse --abbrev-ref HEAD
    git fetch -q origin $branch
    if ((git rev-parse HEAD) -ne (git rev-parse "origin/$branch")) {
        throw "-MacOS et -Windows construisent le code poussé : faites d'abord git push origin $branch."
    }
}

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

# --- 1b. Desktop builds on GitHub Actions, alongside the Android builds -------
foreach ($d in $desktop) {
    $since = (Get-Date).ToUniversalTime().AddSeconds(-30)
    & $gh workflow run $d.Workflow --repo $SourceRepo --ref $branch -f "version=$Version" -f "version_code=$versionCode"
    if ($LASTEXITCODE -ne 0) { throw "Impossible de lancer le build $($d.Label) sur GitHub Actions." }
    for ($i = 0; $i -lt 20 -and -not $d.RunId; $i++) {
        Start-Sleep -Seconds 3
        $runs = & $gh run list --repo $SourceRepo --workflow $d.Workflow --event workflow_dispatch --limit 5 --json databaseId,createdAt | ConvertFrom-Json
        $d.RunId = ($runs | Where-Object { ([datetime]$_.createdAt).ToUniversalTime() -ge $since } | Select-Object -First 1).databaseId
    }
    if (-not $d.RunId) { throw "Build $($d.Label) lancé, mais introuvable dans GitHub Actions." }
    Write-Host "Build $($d.Label) lancé : https://github.com/$SourceRepo/actions/runs/$($d.RunId)" -ForegroundColor Cyan
}

# --- 2. Builds ----------------------------------------------------------------
$platforms = 'android-arm,android-arm64'
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
    $target = Join-Path $dist $b.Name
    if ($rotation) {
        Invoke-ObMaxRotationSign $signing $apk $target
        Assert-ObMaxRotationSignature $target $oldSha $newSha
    } else {
        Copy-Item $apk $target -ErrorAction Stop
    }
    $b.Abi = Get-ObMaxApkAbiReport $target
}

foreach ($d in $desktop) {
    Write-Host "Attente du build $($d.Label) (GitHub Actions, 20 à 45 min)..." -ForegroundColor Cyan
    & $gh run watch $d.RunId --repo $SourceRepo --exit-status --interval 30 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Build $($d.Label) en échec : https://github.com/$SourceRepo/actions/runs/$($d.RunId)" }
    & $gh run download $d.RunId --repo $SourceRepo --name $d.Artifact --dir $dist
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $dist $d.Name))) { throw "$($d.Name) introuvable après téléchargement." }
    $builds += @{ Flavor = $d.Key; Key = $d.Key; Name = $d.Name }
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
Write-Host "Signature    : $(if ($rotation) { 'rotation vers ' + (Format-Fingerprint $newSha) } else { 'clé unique (keystore.properties)' })"
Write-Host "Notes        : $Notes"
Write-Host "Dépôt        : $ReleasesRepo (public)"
foreach ($b in $builds) {
    Write-Host ("{0,-24} {1,8:N1} Mo  sha256 {2}" -f $b.Name, ($b.Size / 1MB), $b.Sha)
}
foreach ($b in $builds | Where-Object { $_.Abi }) {
    Write-Host ("{0,-24} .so : {1} arm64-v8a, {2} armeabi-v7a" -f $b.Name, $b.Abi.Arm64, $b.Abi.Armv7)
    if ($b.Abi.Arm64Only) { Write-Warning "$($b.Name) : seulement en arm64-v8a : $($b.Abi.Arm64Only -join ', ')" }
    if ($b.Abi.Armv7Only) { Write-Warning "$($b.Name) : seulement en armeabi-v7a : $($b.Abi.Armv7Only -join ', ')" }
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

if (-not $gh) {
    Write-Warning "La CLI GitHub (gh) n'est pas installée : winget install GitHub.cli, puis gh auth login. Relancez ensuite la commande ci-dessus."
    exit 0
}
# Without a console (a non-interactive shell) Read-Host fails and leaves
# $answer null, and `$null -notmatch` is not $true: only an explicit yes
# publishes.
$answer = ''
if ($Yes) {
    $answer = 'o'
} else {
    try { $answer = Read-Host 'Publier cette release ? (o/N)' -ErrorAction Stop }
    catch { Write-Warning 'Pas de console pour confirmer : relancez la commande ci-dessus, ou le script avec -Yes.' }
}
if (-not ("$answer" -match '^(o|oui|y|yes)$')) {
    Write-Host 'Publication annulée. Les fichiers restent dans dist\.' -ForegroundColor Yellow
    exit 0
}
& $gh @ghArgs
if ($LASTEXITCODE -ne 0) { throw 'gh release create a échoué' }
Write-Host "Publié. Pensez à commiter pubspec.yaml : git commit -am 'release: OB Max $Version'" -ForegroundColor Green
