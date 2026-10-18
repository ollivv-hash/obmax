# OB Max: shared helpers for APK signing and the signing-key rotation.
# Dot-source after obmax_env.ps1 (JAVA_HOME must point at the JDK):
#   . .\tools\obmax_signing.ps1

$script:KeystoreProperties = Join-Path (Split-Path -Parent $PSScriptRoot) 'android\keystore.properties'

# Reads a Java .properties file into a hashtable (only the simple key=value
# lines this project writes; backslash escapes are undone).
function Read-ObMaxProperties([string]$Path = $script:KeystoreProperties) {
    $props = @{}
    if (-not (Test-Path $Path)) { return $props }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*[#!]' -or $line -notmatch '=') { continue }
        $i = $line.IndexOf('=')
        $props[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim().Replace('\\', '\')
    }
    return $props
}

function ConvertTo-PropertyValue([string]$Value) { $Value.Replace('\', '\\') }

# apksigner from the newest build-tools of the SDK named in android\local.properties.
function Get-ObMaxApkSigner {
    $local = Join-Path (Split-Path -Parent $PSScriptRoot) 'android\local.properties'
    $sdk = (Read-ObMaxProperties $local)['sdk.dir']
    if (-not $sdk) { $sdk = $env:ANDROID_HOME }
    if (-not $sdk) { throw 'SDK Android introuvable (sdk.dir dans android\local.properties).' }
    $sdk = $sdk.Replace('\:', ':')
    $tools = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory |
        Sort-Object { [version]($_.Name -replace '[^\d.].*$', '') } -Descending
    foreach ($t in $tools) {
        $bat = Join-Path $t.FullName 'apksigner.bat'
        if (Test-Path $bat) { return $bat }
    }
    throw "apksigner introuvable dans $sdk\build-tools."
}

function Get-KeystoreType([string]$Store) {
    $head = [System.IO.File]::ReadAllBytes($Store) | Select-Object -First 4
    if ($head[0] -eq 0xFE -and $head[1] -eq 0xED) { return 'JKS' }
    return 'PKCS12'
}

# SHA-256 of the certificate under $Alias, as lowercase hex without colons.
function Get-CertSha256([string]$Store, [string]$Alias, [string]$Password) {
    # Native stderr must not become a terminating error under Windows PowerShell.
    $ErrorActionPreference = 'Continue'
    $env:OBMAX_TMP_PASS = $Password
    try {
        $out = & "$env:JAVA_HOME\bin\keytool.exe" '-J-Duser.language=en' -list -v -keystore $Store -alias $Alias -storepass:env OBMAX_TMP_PASS 2>&1
        if ($LASTEXITCODE -ne 0) { return $null }
    } finally {
        Remove-Item Env:\OBMAX_TMP_PASS -ErrorAction SilentlyContinue
    }
    $m = [regex]::Match(($out -join "`n"), 'SHA[ -]?256:\s*([0-9A-Fa-f:]{95})')
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value.Replace(':', '').ToLowerInvariant()
}

function Format-Fingerprint([string]$Hex) {
    (($Hex.ToUpperInvariant() -split '(..)') -ne '') -join ':'
}

# True once keystore.properties describes a rotation (previous key + lineage).
function Test-ObMaxRotation([hashtable]$Props) {
    return [bool]($Props['previousStoreFile'] -and $Props['lineageFile'])
}

# Signs $InApk into $OutApk with the previous key (v2, Android 7 to 8.1) and the
# current key with the rotation lineage (v3, Android 9 and later), so devices
# that run a build signed with the previous key accept the update.
function Invoke-ObMaxRotationSign([hashtable]$Props, [string]$InApk, [string]$OutApk) {
    $ErrorActionPreference = 'Continue'
    $apksigner = Get-ObMaxApkSigner
    $env:OBMAX_OLD_STORE_PASS = $Props['previousStorePassword']
    $env:OBMAX_OLD_KEY_PASS = $Props['previousKeyPassword']
    $env:OBMAX_NEW_STORE_PASS = $Props['storePassword']
    $env:OBMAX_NEW_KEY_PASS = $Props['keyPassword']
    try {
        & $apksigner sign `
            --ks $Props['previousStoreFile'] --ks-key-alias $Props['previousKeyAlias'] `
            --ks-pass env:OBMAX_OLD_STORE_PASS --key-pass env:OBMAX_OLD_KEY_PASS `
            --next-signer `
            --ks $Props['storeFile'] --ks-key-alias $Props['keyAlias'] `
            --ks-pass env:OBMAX_NEW_STORE_PASS --key-pass env:OBMAX_NEW_KEY_PASS `
            --lineage $Props['lineageFile'] --rotation-min-sdk-version 28 `
            --out $OutApk $InApk
        if ($LASTEXITCODE -ne 0) { throw "apksigner sign a échoué pour $InApk" }
    } finally {
        'OBMAX_OLD_STORE_PASS', 'OBMAX_OLD_KEY_PASS', 'OBMAX_NEW_STORE_PASS', 'OBMAX_NEW_KEY_PASS' |
            ForEach-Object { Remove-Item "Env:\$_" -ErrorAction SilentlyContinue }
    }
    $idsig = "$OutApk.idsig"
    if (Test-Path $idsig) { Remove-Item $idsig }
}

# Checks that Android 9+ sees the new key and Android 7 to 8.1 the previous one.
function Assert-ObMaxRotationSignature([string]$Apk, [string]$OldSha, [string]$NewSha) {
    $ErrorActionPreference = 'Continue'
    $apksigner = Get-ObMaxApkSigner
    $checks = @(
        @{ Range = @('--min-sdk-version', '28'); Sha = $NewSha; Label = 'Android 9+ (v3)' },
        @{ Range = @('--min-sdk-version', '24', '--max-sdk-version', '27'); Sha = $OldSha; Label = 'Android 7 à 8.1 (v2)' }
    )
    foreach ($c in $checks) {
        $out = (& $apksigner verify --print-certs @($c.Range) $Apk 2>&1 | ForEach-Object { "$_" }) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $out -notmatch "(?m)Signer: certificate SHA-256 digest: $($c.Sha)\s*$") {
            throw "Signature inattendue pour $Apk ($($c.Label)) :`n$out"
        }
    }
}
