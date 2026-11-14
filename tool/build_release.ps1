<#
.SYNOPSIS
  Builds Shorjeh for Android release, with the Dart code obfuscated.

.DESCRIPTION
  --obfuscate renames the Dart classes and functions inside the compiled app
  (libapp.so), so a decompiler shows a1/b2 instead of WalletService.withdraw
  and the app's logic stops reading like its source. (Java/Kotlin is already
  shrunk and renamed by R8, which Flutter turns on for every release build.)

  The map back to the real names goes to build/symbols/<version> and never
  into the APK. Keep that folder for every build you ship: without it a
  Crashlytics stack trace from that build is unreadable. The script prints the
  upload command at the end.

  Bump the +N in pubspec.yaml before each release you distribute (the
  forced-update gate compares it).

.EXAMPLE
  .\tool\build_release.ps1           # split-per-abi APKs, to install directly
.EXAMPLE
  .\tool\build_release.ps1 -Bundle   # .aab for Google Play
#>
param([switch]$Bundle)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$symbols = "build/symbols/$($version -replace '\+', '_')"

if ($Bundle) {
    flutter build appbundle --release --obfuscate --split-debug-info=$symbols
} else {
    flutter build apk --release --split-per-abi --obfuscate --split-debug-info=$symbols
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$services = Get-Content android/app/google-services.json -Raw | ConvertFrom-Json
$appId = ($services.client | Where-Object {
    $_.client_info.android_client_info.package_name -eq 'com.balla.balla'
} | Select-Object -First 1).client_info.mobilesdk_app_id

Write-Host ""
Write-Host "Built $version. Symbols: $symbols (keep this folder)."
Write-Host "So Crashlytics can read this build's crashes, upload them once:"
Write-Host "  firebase crashlytics:symbols:upload --app=$appId $symbols"
