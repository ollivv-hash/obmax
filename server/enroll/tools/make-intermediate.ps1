<#
.SYNOPSIS
  One-off ceremony: creates the "OB Max Enrollment CA" intermediate, signed by
  the offline root (ca.key / ca.crt).

.DESCRIPTION
  Run on the PC that holds the root key. Produces, in -OutDir:
    obmax-enroll-ca.key   intermediate private key (EC P-256): goes to the Pi,
                          into the service's data volume (ca/), and into the
                          password manager
    obmax-enroll-ca.crt   intermediate certificate: goes to the Pi (ca/) and
                          into Caddy's trust_pool
  The root key is only read. Nothing is sent anywhere.

.EXAMPLE
  .\make-intermediate.ps1 -RootCert E:\ca\ca.crt -RootKey E:\ca\ca.key -OutDir E:\obmax-keys\enroll-ca
#>
param(
    [Parameter(Mandatory = $true)][string]$RootCert,
    [Parameter(Mandatory = $true)][string]$RootKey,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [int]$Days = 1095
)

$ErrorActionPreference = 'Continue'
$openssl = (Get-Command openssl -ErrorAction SilentlyContinue).Source
if (-not $openssl -and (Test-Path "$env:ProgramFiles\Git\mingw64\bin\openssl.exe")) {
    $openssl = "$env:ProgramFiles\Git\mingw64\bin\openssl.exe"
}
if (-not $openssl) { throw "openssl introuvable (installé avec Git for Windows)." }
foreach ($f in @($RootCert, $RootKey)) { if (-not (Test-Path $f)) { throw "Fichier introuvable : $f" } }

New-Item -ItemType Directory -Force $OutDir | Out-Null
$key = Join-Path $OutDir 'obmax-enroll-ca.key'
$csr = Join-Path $OutDir 'obmax-enroll-ca.csr'
$crt = Join-Path $OutDir 'obmax-enroll-ca.crt'
$ext = Join-Path $OutDir 'intermediate.ext'
if (Test-Path $key) { throw "$key existe déjà : choisissez un autre dossier pour ne rien écraser." }

[System.IO.File]::WriteAllText($ext, @"
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
extendedKeyUsage = clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
"@)

& $openssl ecparam -name prime256v1 -genkey -noout -out $key
if ($LASTEXITCODE -ne 0) { throw 'Génération de la clé en échec' }
& $openssl req -new -key $key -subj '/CN=OB Max Enrollment CA/O=OB Max' -out $csr
if ($LASTEXITCODE -ne 0) { throw 'Génération du CSR en échec' }
Write-Host 'Signature par la CA racine (saisissez son mot de passe si elle en a un)...' -ForegroundColor Cyan
& $openssl x509 -req -in $csr -CA $RootCert -CAkey $RootKey -CAcreateserial -days $Days -sha256 -extfile $ext -out $crt
if ($LASTEXITCODE -ne 0) { throw 'Signature en échec' }
Remove-Item $csr, $ext -ErrorAction SilentlyContinue

& $openssl verify -CAfile $RootCert $crt
if ($LASTEXITCODE -ne 0) { throw 'La chaîne ne se vérifie pas' }
Write-Host ''
& $openssl x509 -in $crt -noout -subject -issuer -dates -ext basicConstraints,keyUsage,extendedKeyUsage
Write-Host ''
Write-Host "Fichiers créés dans $OutDir :" -ForegroundColor Green
Write-Host "  obmax-enroll-ca.crt  -> Pi (données du service, dossier ca/) + trust_pool de Caddy"
Write-Host "  obmax-enroll-ca.key  -> Pi (dossier ca/, droits 600) + coffre de mots de passe"
Write-Host "Ensuite : supprimer ca.key du Pi (~/caddy/certs/)." -ForegroundColor Yellow
