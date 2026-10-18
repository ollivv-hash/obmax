<#
.SYNOPSIS
  Switches OB Max signing to a new key through an APK Signature Scheme v3 rotation.

.DESCRIPTION
  Run once, from the repo root: .\tools\rotate_signing_key.ps1
  1. Asks the password of the new keystore (hidden) and checks both keys'
     SHA-256 fingerprints against the expected ones.
  2. Creates the rotation lineage (the previous key vouches for the new one).
  3. Rewrites android\keystore.properties: the new key becomes the signing key,
     the previous key and the lineage are kept for release.ps1.
  The previous keystore.properties is saved next to the previous keystore.
  Running it again once the rotation is set up only re-checks it.
#>
param(
    [string]$NewStore = 'D:\secrets\obmax-release.jks',
    [string]$NewAlias = 'obmax',
    # Registered in the Android Developer Console for com.example.obmax.
    [string]$ExpectedNewSha256 = '26:58:2F:C5:5D:FF:AF:F8:C7:85:0C:06:A5:53:09:D3:20:BE:D6:E0:9C:9D:01:F5:0C:B2:74:0C:7C:E4:71:D2',
    # Key that signed OB Max 1.0.0 to 2.0.0.
    [string]$ExpectedOldSha256 = 'B4:6E:F4:5D:03:2D:2C:48:FC:EB:9C:C0:C9:9F:C8:D4:F7:35:08:1D:D8:0C:1A:4A:9B:96:83:6E:A1:7C:8D:0C',
    [string]$Lineage = 'D:\secrets\obmax-rotation.lineage',
    [string]$Properties = ''
)

# Not 'Stop': Windows PowerShell turns native stderr lines into terminating
# errors. Failures are caught through $LASTEXITCODE and explicit throws.
$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\obmax_env.ps1"
. "$PSScriptRoot\obmax_signing.ps1"
if (-not $Properties) { $Properties = $script:KeystoreProperties }
$normalize = { param($s) $s.Replace(':', '').ToLowerInvariant() }
$props = Read-ObMaxProperties $Properties
if (-not $props['storeFile']) { throw "Fichier introuvable ou incomplet : $Properties" }
$apksigner = Get-ObMaxApkSigner

function Assert-Fingerprint([string]$Label, [string]$Actual, [string]$Expected) {
    if (-not $Actual) { throw "$Label : impossible de lire le certificat (mot de passe ou alias incorrect)." }
    Write-Host ("{0,-16} {1}" -f $Label, (Format-Fingerprint $Actual))
    if ($Actual -ne (& $normalize $Expected)) {
        throw "$Label : empreinte inattendue, attendu $Expected. Rien n'a été modifié."
    }
}

if (Test-ObMaxRotation $props) {
    Write-Host 'La rotation est déjà en place, vérification :' -ForegroundColor Cyan
    Assert-Fingerprint 'Ancienne clé' (Get-CertSha256 $props['previousStoreFile'] $props['previousKeyAlias'] $props['previousStorePassword']) $ExpectedOldSha256
    Assert-Fingerprint 'Nouvelle clé' (Get-CertSha256 $props['storeFile'] $props['keyAlias'] $props['storePassword']) $ExpectedNewSha256
    & $apksigner lineage --in $props['lineageFile'] --print-certs
    exit $LASTEXITCODE
}

# --- 1. New key password and fingerprints ------------------------------------
if (-not (Test-Path $NewStore)) { throw "Keystore introuvable : $NewStore" }
$newPass = $env:OBMAX_NEW_KS_PASS
if (-not $newPass) {
    $secure = Read-Host "Mot de passe de $NewStore (saisie masquee)" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $newPass = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

$old = @{
    Store = $props['storeFile']; Alias = $props['keyAlias']
    StorePass = $props['storePassword']; KeyPass = $props['keyPassword']
}
Assert-Fingerprint 'Ancienne clé' (Get-CertSha256 $old.Store $old.Alias $old.StorePass) $ExpectedOldSha256
Assert-Fingerprint 'Nouvelle clé' (Get-CertSha256 $NewStore $NewAlias $newPass) $ExpectedNewSha256

# --- 2. Rotation lineage -------------------------------------------------------
if (Test-Path $Lineage) {
    Write-Host "Lignée existante réutilisée : $Lineage" -ForegroundColor Yellow
} else {
    $env:OBMAX_OLD_STORE_PASS = $old.StorePass
    $env:OBMAX_OLD_KEY_PASS = $old.KeyPass
    $env:OBMAX_NEW_STORE_PASS = $newPass
    try {
        # A PKCS12 keystore has one password for the store and its keys.
        & $apksigner rotate --out $Lineage `
            --old-signer --ks $old.Store --ks-key-alias $old.Alias `
            --ks-pass env:OBMAX_OLD_STORE_PASS --key-pass env:OBMAX_OLD_KEY_PASS `
            --new-signer --ks $NewStore --ks-key-alias $NewAlias `
            --ks-pass env:OBMAX_NEW_STORE_PASS --key-pass env:OBMAX_NEW_STORE_PASS
        if ($LASTEXITCODE -ne 0) { throw 'apksigner rotate a échoué. Rien n''a été modifié.' }
    } finally {
        'OBMAX_OLD_STORE_PASS', 'OBMAX_OLD_KEY_PASS', 'OBMAX_NEW_STORE_PASS' |
            ForEach-Object { Remove-Item "Env:\$_" -ErrorAction SilentlyContinue }
    }
    Write-Host "Lignée créée : $Lineage" -ForegroundColor Green
}
& $apksigner lineage --in $Lineage --print-certs
if ($LASTEXITCODE -ne 0) { throw 'Lignée illisible.' }

# --- 3. keystore.properties -----------------------------------------------------
$backup = Join-Path (Split-Path -Parent $old.Store) 'keystore.properties.avant-rotation'
Copy-Item $Properties $backup -Force -ErrorAction Stop
$fwd = { param($p) $p.Replace('\', '/') }
$newPassValue = ConvertTo-PropertyValue $newPass
$text = @"
# OB Max release signing. Ignored by git: never commit this file.
# Written by tools\rotate_signing_key.ps1. Signing key registered in the
# Android Developer Console ($ExpectedNewSha256).
storeFile=$(& $fwd $NewStore)
storeType=$(Get-KeystoreType $NewStore)
keyAlias=$NewAlias
storePassword=$newPassValue
keyPassword=$newPassValue

# Key rotation (APK Signature Scheme v3): release.ps1 signs with both keys and
# this lineage, so devices running a build signed with the previous key
# (OB Max 1.0.0 to 2.0.0) accept the update. Keep all three files forever.
previousStoreFile=$(& $fwd $old.Store)
previousKeyAlias=$($old.Alias)
previousStorePassword=$(ConvertTo-PropertyValue $old.StorePass)
previousKeyPassword=$(ConvertTo-PropertyValue $old.KeyPass)
lineageFile=$(& $fwd $Lineage)
"@
[System.IO.File]::WriteAllText($Properties, $text.Replace("`r`n", "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host ''
Write-Host "keystore.properties mis à jour (ancienne version : $backup)." -ForegroundColor Green
Write-Host "Sauvegardez $Lineage avec les deux keystores." -ForegroundColor Yellow
