# OB Max: writes the keystore password into android\keystore.properties.
# The password is typed here (hidden), checked against the keystore with
# keytool, then written to the file, which git ignores.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$props = Join-Path $root 'android\keystore.properties'
if (-not (Test-Path $props)) { throw "Fichier introuvable : $props" }

$text = [System.IO.File]::ReadAllText($props)
$store = [regex]::Match($text, '(?m)^storeFile=(.+)$').Groups[1].Value.Trim()
$alias = [regex]::Match($text, '(?m)^keyAlias=(.+)$').Groups[1].Value.Trim()
$keytool = 'E:\jdk17\jdk-17.0.20.1+1\bin\keytool.exe'

$secure = Read-Host 'Mot de passe du keystore (saisie masquee)' -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

$env:OBMAX_KS_PASS = $plain
& $keytool -list -keystore $store -storetype PKCS12 -alias $alias -storepass:env OBMAX_KS_PASS *> $null
$ok = $LASTEXITCODE -eq 0
Remove-Item Env:\OBMAX_KS_PASS
if (-not $ok) {
    Write-Host 'Mot de passe refuse par le keystore. Rien n''a ete modifie, relancez le script.' -ForegroundColor Red
    exit 1
}

# Backslashes would be read as escapes by Java's Properties loader.
$escaped = $plain.Replace('\', '\\')
$text = [regex]::Replace($text, '(?m)^storePassword=.*$', { param($m) "storePassword=$escaped" })
$text = [regex]::Replace($text, '(?m)^keyPassword=.*$', { param($m) "keyPassword=$escaped" })
[System.IO.File]::WriteAllText($props, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Host 'Mot de passe verifie et enregistre dans android\keystore.properties.' -ForegroundColor Green
