#Requires -Version 5.1
<#
  Builds the release assets for FNVVR Epic Helper.

  Usage:
    powershell -ExecutionPolicy Bypass -File .\tools\Package-Release.ps1 -Version v1.0.0
    powershell -ExecutionPolicy Bypass -File .\tools\Package-Release.ps1 -Version v1.0.0 -FnvVrZip .\FNVVR-Reborn.zip

  If -FnvVrZip is omitted, the script looks for vendor\FNVVR-Reborn.zip or a
  FNVVR zip in the repository root. If none is found, the helper zip is built
  without the bundled FNVVR package (users must supply their own zip).
#>

[CmdletBinding()]
param(
  [string]$Version = 'v1.0.0',
  [string]$FnvVrZip
)

$ErrorActionPreference = 'Stop'

$root  = Split-Path -Parent $PSScriptRoot
$dist  = Join-Path $root 'dist'
$stage = Join-Path $dist ('stage-' + $Version)

if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
New-Item -ItemType Directory -Path $dist -Force | Out-Null

if (-not $FnvVrZip) {
  $candidates = @(
    (Join-Path $root 'vendor\FNVVR-Reborn.zip'),
    (Join-Path $root 'FNVVR-Reborn.zip')
  )
  $candidates += Get-ChildItem -LiteralPath $root -Filter '*.zip' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'fnvvr|dxvk' } | ForEach-Object { $_.FullName }

  $FnvVrZip = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

foreach ($file in @(
    'Install-FNVVR-Epic.ps1',
    'Run-Installer.bat',
    'README.md',
    'DOWNLOAD-LINKS.txt',
    'LICENSE',
    'THIRD_PARTY_NOTICES.md'
  )) {
  $source = Join-Path $root $file
  if (-not (Test-Path -LiteralPath $source)) { throw "Missing file: $source" }
  Copy-Item -LiteralPath $source -Destination $stage -Force
}

$licenses = Join-Path $root 'licenses'
if (Test-Path -LiteralPath $licenses) {
  Copy-Item -LiteralPath $licenses -Destination $stage -Recurse -Force
}

if ($FnvVrZip) {
  if (-not (Test-Path -LiteralPath $FnvVrZip)) { throw "FNVVR package not found: $FnvVrZip" }
  Copy-Item -LiteralPath $FnvVrZip -Destination (Join-Path $stage 'FNVVR-Reborn.zip') -Force
  Copy-Item -LiteralPath $FnvVrZip -Destination (Join-Path $dist 'FNVVR-Reborn.zip') -Force
  Write-Host "Bundled FNVVR package: $FnvVrZip"
} else {
  Write-Warning 'No FNVVR package supplied; the helper zip will not contain FNVVR-Reborn.zip.'
}

$helperZip = Join-Path $dist ("FNVVR-Epic-Helper-{0}.zip" -f $Version)
if (Test-Path -LiteralPath $helperZip) { Remove-Item -LiteralPath $helperZip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $helperZip -Force
Remove-Item -LiteralPath $stage -Recurse -Force

$sums = Join-Path $dist 'SHA256SUMS.txt'
$zipFiles = Get-ChildItem -LiteralPath $dist -Filter '*.zip' -File | Sort-Object Name
$lines = foreach ($zip in $zipFiles) {
  $hash = (Get-FileHash -LiteralPath $zip.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  "$hash  $($zip.Name)"
}
$lines | Set-Content -LiteralPath $sums -Encoding ASCII

Write-Host ''
Write-Host 'Release assets:'
Get-ChildItem -LiteralPath $dist -File | Select-Object Name, Length | Format-Table -AutoSize
