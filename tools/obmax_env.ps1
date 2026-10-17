# OB Max: build environment for this Windows machine. Dot-source it:
#   . .\tools\obmax_env.ps1
# Process-scoped only, nothing global is changed.
#  - JDK 17: :file_picker fails with JDK 21 (Java 17 / Kotlin 21 target mismatch).
#  - core.longpaths: pub get on the media_kit git dependency hits "Filename too long".
#  - PUB_CACHE on a short path for the same reason.

$env:JAVA_HOME = if ($env:OBMAX_JAVA_HOME) { $env:OBMAX_JAVA_HOME } else { 'E:\jdk17\jdk-17.0.20.1+1' }
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'core.longpaths'
$env:GIT_CONFIG_VALUE_0 = 'true'
$env:PUB_CACHE = if ($env:OBMAX_PUB_CACHE) { $env:OBMAX_PUB_CACHE } else { 'E:\pubc' }

$script:Flutter = if ($env:OBMAX_FLUTTER) { $env:OBMAX_FLUTTER } else { "$env:USERPROFILE\fvm\versions\stable\bin\flutter.bat" }
if (-not (Test-Path $script:Flutter)) { throw "Flutter not found at $script:Flutter (set OBMAX_FLUTTER)" }
