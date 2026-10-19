<#
.SYNOPSIS
  Issues a client certificate for a web browser (Chrome on PC or Android),
  signed by the "OB Max Enrollment CA" intermediate.

.DESCRIPTION
  For the admin page and Jellyfin's web interface once the old root leaves
  Caddy's trust_pool. Run on the PC that holds the intermediate key.
  Produces, in -OutDir:
    <Name>.p12   key + certificate + intermediate, protected by the password
                 typed at the openssl prompt: to import into the browser
    <Name>.crt   certificate alone, for reference
  The private key never exists unencrypted on disk after the script ends.
  Not recorded by obmax-enroll: it does not appear in the admin page and
  cannot be revoked there. Keep -Days short and the .p12 private.

.EXAMPLE
  .\make-browser-cert.ps1 -Name ollivv-navigateur
#>
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9._-]{1,40}$')][string]$Name,
    [string]$CaCert = 'E:\obmax-keys\enroll-ca\obmax-enroll-ca.crt',
    [string]$CaKey = 'E:\obmax-keys\enroll-ca\obmax-enroll-ca.key',
    [string]$OutDir = 'E:\obmax-keys\browser',
    [int]$Days = 730
)

$ErrorActionPreference = 'Continue'
# Git for Windows' openssl first: other copies on the PATH (conda...) may lack
# the console prompt or the default providers.
$openssl = "$env:ProgramFiles\Git\mingw64\bin\openssl.exe"
if (-not (Test-Path $openssl)) { $openssl = (Get-Command openssl -ErrorAction SilentlyContinue).Source }
if (-not $openssl) { throw "openssl introuvable (installé avec Git for Windows)." }
foreach ($f in @($CaCert, $CaKey)) { if (-not (Test-Path $f)) { throw "Fichier introuvable : $f" } }

# The certificate must not outlive the intermediate.
$caEnd = [datetime]::ParseExact(
    ((& $openssl x509 -in $CaCert -noout -enddate) -replace '^notAfter=', '' -replace '\s+', ' ').Trim(),
    'MMM d HH:mm:ss yyyy GMT', [Globalization.CultureInfo]::InvariantCulture)
$maxDays = [int][math]::Floor(($caEnd - (Get-Date).ToUniversalTime()).TotalDays) - 1
if ($Days -gt $maxDays) {
    Write-Host "Durée ramenée à $maxDays jours (la CA expire le $($caEnd.ToString('dd/MM/yyyy')))." -ForegroundColor Yellow
    $Days = $maxDays
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$p12 = Join-Path $OutDir "$Name.p12"
$crt = Join-Path $OutDir "$Name.crt"
if (Test-Path $p12) { throw "$p12 existe déjà : choisissez un autre nom pour ne rien écraser." }
$work = Join-Path $env:TEMP "obmax-browser-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory $work | Out-Null
$key = Join-Path $work 'leaf.key'
$csr = Join-Path $work 'leaf.csr'
$ext = Join-Path $work 'leaf.ext'

try {
    [System.IO.File]::WriteAllText($ext, @"
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
"@)
    # RSA rather than EC: Windows' legacy key import (used by some tools and
    # older Android builds) rejects EC keys from a .p12.
    & $openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out $key
    if ($LASTEXITCODE -ne 0) { throw 'Génération de la clé en échec' }
    & $openssl req -new -key $key -subj "/CN=$Name/O=OB Max" -out $csr
    if ($LASTEXITCODE -ne 0) { throw 'Génération du CSR en échec' }
    & $openssl x509 -req -in $csr -CA $CaCert -CAkey $CaKey -set_serial "0x$([guid]::NewGuid().ToString('N'))" `
        -days $Days -sha256 -extfile $ext -out $crt
    if ($LASTEXITCODE -ne 0) { throw 'Signature en échec' }

    # Caddy trusts the intermediate as an anchor: check the same way.
    & $openssl verify -partial_chain -CAfile $CaCert $crt
    if ($LASTEXITCODE -ne 0) { throw 'Le certificat ne se vérifie pas avec la CA OB Max' }

    # SHA1/3DES protection: the only one every Android KeyChain and Windows
    # store accept. The password is what protects it, so make it long.
    Write-Host ''
    Write-Host 'Choisissez le mot de passe du fichier .p12 (demandé au moment de l''import) :' -ForegroundColor Cyan
    $passArgs = if ($env:OBMAX_P12_PASS) { @('-passout', 'env:OBMAX_P12_PASS') } else { @() }
    & $openssl pkcs12 -export -inkey $key -in $crt -certfile $CaCert -name "OB Max - $Name" `
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 @passArgs -out $p12
    if ($LASTEXITCODE -ne 0) {
        Remove-Item $crt -ErrorAction SilentlyContinue
        throw 'Création du .p12 en échec (mots de passe différents ?). Relancez le script.'
    }
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

Write-Host ''
& $openssl x509 -in $crt -noout -subject -issuer -enddate
Write-Host ''
Write-Host "Créé : $p12" -ForegroundColor Green
Write-Host 'À importer dans Chrome (Windows : double-clic sur le .p12 ; Android : Paramètres >'
Write-Host 'Sécurité > Chiffrement et identifiants > Installer un certificat > Certificat utilisateur VPN et appli).'
