#Requires -Version 5.1
<#
  FNVVR Reborn - Epic Games helper
  ---------------------------------
  Helps install the original FNVVR Reborn mod on the Epic Games build of
  Fallout: New Vegas.

  It does NOT include or redistribute:
    - the Epic Games Patcher
    - the Steam/patched FalloutNV.exe
    - Microsoft DirectX files

  The Epic Games Patcher must be downloaded by the user from its official
  Nexus Mods page (mod 81281). This script only runs it if the user already
  placed Patcher.exe, patch.xdelta and xdelta3.exe in the game folder.

  Usage:
    Double-click Run-Installer.bat and follow the dialogs.
    The script asks for the game folder and the FNVVR zip if it cannot
    find them automatically.

  Advanced (optional) switches:
      -GamePath <folder>     Use a specific game folder
      -FnvVrZip <zip>        Use a specific FNVVR package
      -CheckOnly             Only check, do not install anything
      -Restore               Restore the original Epic executable

  The script is intentionally verbose and safe: it backs up files it
  replaces and can restore the original Epic executable with -Restore.
#>

[CmdletBinding()]
param(
  [string]$GamePath,
  [string]$FnvVrZip,
  [string]$FnvVrSource,
  [switch]$RunPatcher,
  [switch]$SkipDirectX,
  [switch]$CheckOnly,
  [switch]$Restore,
  [switch]$NoGui
)

$ErrorActionPreference = 'Stop'
if (-not $PSScriptRoot) { $PSScriptRoot = (Get-Location).Path }

$script:LogFile = Join-Path ([IO.Path]::GetTempPath()) ("FNVVR-Epic-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$script:Problems = New-Object System.Collections.ArrayList
$script:CheckOnly = [bool]$CheckOnly

$script:GuiAvailable = $false
try {
  Add-Type -AssemblyName System.Windows.Forms
  $script:GuiAvailable = $true
} catch { }
if ($NoGui) { $script:GuiAvailable = $false }

function Show-Info {
  param([string]$Message, [string]$Title = 'FNVVR Epic helper')
  if ($script:GuiAvailable) {
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title,
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Information)
  }
}

function Show-ErrorBox {
  param([string]$Message, [string]$Title = 'FNVVR Epic helper')
  if ($script:GuiAvailable) {
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title,
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Error)
  }
}

function Show-Question {
  param([string]$Message, [string]$Title = 'FNVVR Epic helper')
  if (-not $script:GuiAvailable) { return $false }
  return ([System.Windows.Forms.MessageBox]::Show($Message, $Title,
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question) -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Select-FolderDialog {
  param([string]$Description = 'Select the folder that contains FalloutNV.exe')
  if (-not $script:GuiAvailable) { return $null }
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  $dialog.Description = $Description
  $dialog.ShowNewFolderButton = $false
  if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.SelectedPath }
  return $null
}

function Select-ZipDialog {
  param([string]$Title = 'Select the FNVVR Reborn zip file')
  if (-not $script:GuiAvailable) { return $null }
  $dialog = New-Object System.Windows.Forms.OpenFileDialog
  $dialog.Title = $Title
  $dialog.Filter = 'FNVVR package (*.zip)|*.zip|All files (*.*)|*.*'
  $dialog.CheckFileExists = $true
  $dialog.Multiselect = $false
  if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.FileName }
  return $null
}

function Write-Log {
  param(
    [string]$Message,
    [ValidateSet('INFO','WARN','ERROR','OK')]
    [string]$Level = 'INFO'
  )
  $line = "[{0}] {1,-5} {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
  Write-Host $line
  Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
}

function Add-Problem {
  param([string]$Message)
  [void]$script:Problems.Add($Message)
  Write-Log $Message 'WARN'
}

function Fail {
  param([string]$Message)
  Write-Log $Message 'ERROR'
  Write-Log "Log: $script:LogFile"
  exit 1
}

trap {
  Write-Log ("Unexpected error: " + $_.Exception.Message) 'ERROR'
  Write-Log ("Log: " + $script:LogFile) 'ERROR'
  exit 1
}

# ---------------------------------------------------------------------------
# PE helpers
# ---------------------------------------------------------------------------

function Get-PeInfo {
  param([string]$Path)
  $fs = [IO.File]::OpenRead($Path)
  try {
    $br = New-Object IO.BinaryReader($fs)
    $fs.Position = 0x3C
    $peOffset = $br.ReadInt32()
    $fs.Position = $peOffset
    if ($br.ReadUInt32() -ne 0x00004550) { throw "Not a PE file: $Path" }

    $machine = $br.ReadUInt16()
    $numberOfSections = $br.ReadUInt16()
    [void]$br.ReadUInt32()
    [void]$br.ReadUInt32()
    [void]$br.ReadUInt32()
    $sizeOfOptionalHeader = $br.ReadUInt16()
    $characteristics = $br.ReadUInt16()

    $optionalHeaderOffset = $fs.Position
    $magic = $br.ReadUInt16()
    if ($magic -ne 0x10B) { throw "Not a PE32 (32-bit) file: $Path" }

    $fs.Position = $optionalHeaderOffset + 16
    $entryPointRva = $br.ReadUInt32()
    $fs.Position = $optionalHeaderOffset + 28
    $imageBase = $br.ReadUInt32()

    $sections = @()
    $fs.Position = $optionalHeaderOffset + $sizeOfOptionalHeader
    for ($i = 0; $i -lt $numberOfSections; $i++) {
      $nameBytes = $br.ReadBytes(8)
      $name = ([Text.Encoding]::ASCII.GetString($nameBytes)).TrimEnd([char]0)
      $virtualSize = $br.ReadUInt32()
      $virtualAddress = $br.ReadUInt32()
      $rawSize = $br.ReadUInt32()
      $rawPointer = $br.ReadUInt32()
      [void]$br.ReadUInt32()
      [void]$br.ReadUInt32()
      [void]$br.ReadUInt16()
      [void]$br.ReadUInt16()
      $sectionCharacteristics = $br.ReadUInt32()
      $sections += [pscustomobject]@{
        Name            = $name
        VirtualAddress  = $virtualAddress
        VirtualSize     = $virtualSize
        RawPointer      = $rawPointer
        RawSize         = $rawSize
        Characteristics = $sectionCharacteristics
      }
    }

    return [pscustomobject]@{
      Path            = (Resolve-Path -LiteralPath $Path).Path
      Machine         = $machine
      EntryPointRva   = $entryPointRva
      ImageBase       = $imageBase
      Characteristics = $characteristics
      Sections        = $sections
      Length          = $fs.Length
    }
  } finally {
    $fs.Dispose()
  }
}

function Convert-RvaToFileOffset {
  param($Pe, [uint32]$Rva)
  foreach ($s in $Pe.Sections) {
    $size = [Math]::Max([uint32]$s.VirtualSize, [uint32]$s.RawSize)
    if ($Rva -ge $s.VirtualAddress -and $Rva -lt ($s.VirtualAddress + $size)) {
      $delta = $Rva - $s.VirtualAddress
      if ($delta -lt $s.RawSize) { return [long]($s.RawPointer + $delta) }
    }
  }
  return $null
}

function Get-FileBytes {
  param([string]$Path, [long]$Offset, [int]$Count)
  $fs = [IO.File]::OpenRead($Path)
  try {
    $fs.Position = $Offset
    $buffer = New-Object byte[] $Count
    $read = $fs.Read($buffer, 0, $Count)
    if ($read -ne $Count) { return $null }
    return ,$buffer
  } finally {
    $fs.Dispose()
  }
}

function Read-PeBytesAtVa {
  param($Pe, [uint32]$Va, [int]$Count)
  if ($Va -lt $Pe.ImageBase) { return $null }
  $rva = $Va - $Pe.ImageBase
  $offset = Convert-RvaToFileOffset $Pe $rva
  if ($null -eq $offset) { return $null }
  return Get-FileBytes $Pe.Path $offset $Count
}

function Test-FnvVrHook {
  param([string]$ExePath)
  $pe = Get-PeInfo $ExePath
  if ($pe.Machine -ne 0x14C) { return $false }
  $bytes = Read-PeBytesAtVa $pe 0x0086EDE8 5
  if ($null -eq $bytes) { return $false }
  if ($bytes[0] -ne 0xE8) { return $false }
  $displacement = [BitConverter]::ToInt32($bytes, 1)
  $target = [int64]0x0086EDE8 + 5 + $displacement
  return ($target -eq [int64]0x0086FF70)
}

function Get-ExeInfo {
  param([string]$ExePath)
  $version = ''
  try { $version = ((Get-Item -LiteralPath $ExePath).VersionInfo.FileVersion + '').Trim() } catch { }
  $sha1 = ''
  try { $sha1 = (Get-FileHash -LiteralPath $ExePath -Algorithm SHA1).Hash } catch { }
  $hook = $false
  try { $hook = Test-FnvVrHook $ExePath } catch { }

  $kind = 'Unknown'
  if ($hook) {
    $kind = 'FNVVR-compatible (1.4.0.525 code, hook found)'
  } elseif ($version -eq '1.4.0.1338') {
    $kind = 'Epic Games 1.4.0.1338 (unsupported by FNVVR until patched)'
  } elseif ($version -eq '1.4.0.525') {
    $kind = '1.4.0.525 but FNVVR hook NOT found'
  }

  return [pscustomobject]@{
    Version = $version
    Sha1    = $sha1
    Hook    = $hook
    Kind    = $kind
  }
}

# ---------------------------------------------------------------------------
# Game folder
# ---------------------------------------------------------------------------

function Test-GameFolder {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  $exe = Join-Path $Path 'FalloutNV.exe'
  $data = Join-Path $Path 'Data'
  return ((Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath $data))
}

function Resolve-GameFolder {
  param([string]$Requested)

  if ($Requested) {
    $Requested = $Requested.Trim().Trim('"')
    if (Test-GameFolder $Requested) { return (Resolve-Path -LiteralPath $Requested).Path }
    Fail "The -GamePath value does not contain FalloutNV.exe and Data: $Requested"
  }

  $candidates = New-Object System.Collections.ArrayList
  $candidates.Add((Join-Path $env:ProgramFiles 'Epic Games\FalloutNewVegas\Fallout New Vegas English')) | Out-Null
  if (${env:ProgramFiles(x86)}) {
    $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Epic Games\FalloutNewVegas\Fallout New Vegas English')) | Out-Null
  }
  $candidates.Add('F:\Epic Library\FalloutNewVegas\Fallout New Vegas English') | Out-Null
  $candidates.Add('D:\Epic Library\FalloutNewVegas\Fallout New Vegas English') | Out-Null
  $candidates.Add('C:\Epic Library\FalloutNewVegas\Fallout New Vegas English') | Out-Null

  $manifestDir = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
  if (Test-Path -LiteralPath $manifestDir) {
    foreach ($item in Get-ChildItem -LiteralPath $manifestDir -Filter '*.item' -File -ErrorAction SilentlyContinue) {
      try {
        $json = Get-Content -LiteralPath $item.FullName -Raw | ConvertFrom-Json
        if ($json.InstallLocation) {
          $candidates.Add((Join-Path $json.InstallLocation 'Fallout New Vegas English')) | Out-Null
          $sub = Get-ChildItem -LiteralPath $json.InstallLocation -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'Fallout New Vegas*' } | Select-Object -First 1
          if ($sub) { $candidates.Add($sub.FullName) | Out-Null }
        }
      } catch { }
    }
  }

  foreach ($candidate in ($candidates | Select-Object -Unique)) {
    if (Test-GameFolder $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
  }

  Write-Log 'Could not find the Epic Fallout: New Vegas folder automatically.' 'WARN'

  if ($script:GuiAvailable) {
    while ($true) {
      $picked = Select-FolderDialog 'Select the folder that contains FalloutNV.exe. It is usually the "Fallout New Vegas English" folder inside your Epic install.'
      if (-not $picked) { Fail 'Game folder not selected.' }
      if (Test-GameFolder $picked) { return (Resolve-Path -LiteralPath $picked).Path }
      Show-ErrorBox "That folder does not contain FalloutNV.exe and Data.`n`nPlease select the 'Fallout New Vegas English' folder inside your Epic install."
    }
  }

  $answer = Read-Host "Enter the folder that contains FalloutNV.exe (usually ...\FalloutNewVegas\Fallout New Vegas English)"
  if ($answer) { $answer = $answer.Trim().Trim('"') }
  if (Test-GameFolder $answer) { return (Resolve-Path -LiteralPath $answer).Path }

  Fail 'Game folder not found. Use -GamePath "F:\...\Fallout New Vegas English".'
}

function Test-WritableFolder {
  param([string]$Path)
  $probe = Join-Path $Path ('.fnvvr-write-test-' + [guid]::NewGuid().ToString('N'))
  try {
    [IO.File]::WriteAllText($probe, '')
    Remove-Item -LiteralPath $probe -Force
    return $true
  } catch {
    return $false
  }
}

# ---------------------------------------------------------------------------
# DirectX 9 d3dx9_38.dll
# ---------------------------------------------------------------------------

function Test-D3dx9_38 {
  param([string]$GameFolder)

  $gameDll = Join-Path $GameFolder 'd3dx9_38.dll'
  if (Test-Path -LiteralPath $gameDll) {
    try {
      $pe = Get-PeInfo $gameDll
      if ($pe.Machine -eq 0x14C) { return $true }
    } catch { }
  }

  $sysWow = Join-Path $env:windir 'SysWOW64\d3dx9_38.dll'
  if (Test-Path -LiteralPath $sysWow) {
    try {
      $pe = Get-PeInfo $sysWow
      if ($pe.Machine -eq 0x14C) { return $true }
    } catch { }
  }

  return $false
}

function Install-D3dx9_38 {
  param([string]$GameFolder)

  $cache = Join-Path ([IO.Path]::GetTempPath()) 'FNVVR-Epic\directx'
  New-Item -ItemType Directory -Path $cache -Force | Out-Null

  $redist = Join-Path $cache 'directx_Jun2010_redist.exe'
  if (-not (Test-Path -LiteralPath $redist)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = 'https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe'
    Write-Log 'Downloading Microsoft DirectX June 2010 redistributable (about 100 MB)...'
    Invoke-WebRequest -Uri $url -OutFile $redist -UseBasicParsing
  }

  $signature = Get-AuthenticodeSignature -LiteralPath $redist
  if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'CN=Microsoft Corporation') {
    Fail "The DirectX redistributable failed its Microsoft signature check: $redist"
  }

  $extract = Join-Path $cache 'extracted'
  $cab = Join-Path $extract 'JUN2008_d3dx9_38_x86.cab'
  if (-not (Test-Path -LiteralPath $cab)) {
    if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
    New-Item -ItemType Directory -Path $extract -Force | Out-Null
    Write-Log 'Extracting DirectX redistributable...'
    $process = Start-Process -FilePath $redist -ArgumentList @('/Q', "/T:`"$extract`"") -Wait -PassThru
    if ($process.ExitCode -ne 0) { Fail "DirectX redist extraction failed with exit code $($process.ExitCode)." }
  }

  if (-not (Test-Path -LiteralPath $cab)) { Fail 'JUN2008_d3dx9_38_x86.cab was not found in the DirectX redistributable.' }

  $dllDir = Join-Path $cache 'dll32'
  New-Item -ItemType Directory -Path $dllDir -Force | Out-Null
  $dll = Join-Path $dllDir 'd3dx9_38.dll'
  if (-not (Test-Path -LiteralPath $dll)) {
    & "$env:windir\System32\expand.exe" -F:d3dx9_38.dll $cab $dllDir | Out-Null
  }
  if (-not (Test-Path -LiteralPath $dll)) { Fail 'Could not extract d3dx9_38.dll from the DirectX redistributable.' }

  $pe = Get-PeInfo $dll
  if ($pe.Machine -ne 0x14C) { Fail 'The extracted d3dx9_38.dll is not 32-bit.' }

  $destination = Join-Path $GameFolder 'd3dx9_38.dll'
  if (Test-Path -LiteralPath $destination) {
    try {
      $old = Get-PeInfo $destination
      if ($old.Machine -eq 0x14C) { return }
    } catch { }
    Copy-Item -LiteralPath $destination -Destination ($destination + '.not-32bit-backup') -Force
  }

  Copy-Item -LiteralPath $dll -Destination $destination -Force
  Write-Log "Installed 32-bit d3dx9_38.dll into the game folder." 'OK'
}

# ---------------------------------------------------------------------------
# FNVVR package
# ---------------------------------------------------------------------------

function Find-FnvVrSource {
  param([string]$Zip, [string]$Source)

  if ($Source) {
    $Source = $Source.Trim().Trim('"')
    if (-not (Test-Path -LiteralPath $Source)) { Fail "FnvVrSource not found: $Source" }
    return (Resolve-Path -LiteralPath $Source).Path
  }

  if (-not $Zip) {
    $local = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.zip' -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match 'fnvvr|dxvk' } | Select-Object -First 1
    if ($local) { $Zip = $local.FullName }
  }

  if (-not $Zip -and -not $script:CheckOnly -and $script:GuiAvailable) {
    Write-Log 'No FNVVR zip was found next to the helper; asking the user to select it.'
    $Zip = Select-ZipDialog
  }

  if ($Zip) {
    $Zip = $Zip.Trim().Trim('"')
    if (-not (Test-Path -LiteralPath $Zip)) { Fail "FnvVrZip not found: $Zip" }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('FNVVR-Epic\package-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    Write-Log "Extracting FNVVR package: $Zip"
    Expand-Archive -LiteralPath $Zip -DestinationPath $temp -Force
    return $temp
  }

  return $null
}

function Test-FnvVrDll {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  try {
    $pe = Get-PeInfo $Path
    if ($pe.Machine -ne 0x14C) { return $false }
  } catch { return $false }
  if ((Get-Item -LiteralPath $Path).Length -lt 5MB) { return $false }
  try {
    $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Path))
    return ($text -match 'FNVVR|DXVK')
  } catch {
    return $false
  }
}

function Backup-File {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    $backup = $Path + '.before-fnvvr'
    if (-not (Test-Path -LiteralPath $backup)) {
      Copy-Item -LiteralPath $Path -Destination $backup -Force
      Write-Log "Backed up $([IO.Path]::GetFileName($Path)) to $([IO.Path]::GetFileName($backup))"
    }
  }
}

function Test-VrBackendOpenVr {
  param([string]$ConfPath)
  if (-not (Test-Path -LiteralPath $ConfPath)) { return $false }
  foreach ($line in (Get-Content -LiteralPath $ConfPath)) {
    if ($line -match '^\s*\[') { break }
    if ($line -match '^\s*d3d9\.vrBackend\s*=\s*openvr\s*$') { return $true }
  }
  return $false
}

function Ensure-VrBackendOpenVr {
  param([string]$ConfPath)

  $lines = @(Get-Content -LiteralPath $ConfPath)
  $firstSection = $lines.Count
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*\[') { $firstSection = $i; break }
  }

  for ($i = 0; $i -lt $firstSection; $i++) {
    if ($lines[$i] -match '^\s*d3d9\.vrBackend\s*=') {
      $lines[$i] = 'd3d9.vrBackend = openvr'
      Set-Content -LiteralPath $ConfPath -Value $lines -Encoding ASCII
      Write-Log 'Set d3d9.vrBackend = openvr in dxvk.conf.'
      return
    }
  }

  $newLines = @('d3d9.vrBackend = openvr') + $lines
  Set-Content -LiteralPath $ConfPath -Value $newLines -Encoding ASCII
  Write-Log 'Added d3d9.vrBackend = openvr to the top of dxvk.conf.'
}

function Install-FnvVrFiles {
  param([string]$SourceRoot, [string]$GameFolder)

  $d3d9 = Get-ChildItem -LiteralPath $SourceRoot -Filter 'd3d9.dll' -Recurse -File -ErrorAction SilentlyContinue |
    Sort-Object Length -Descending | Select-Object -First 1
  if (-not $d3d9) { Fail "No d3d9.dll found in the FNVVR package: $SourceRoot" }

  $pe = Get-PeInfo $d3d9.FullName
  if ($pe.Machine -ne 0x14C) { Fail "The package's d3d9.dll is not 32-bit: $($d3d9.FullName)" }

  $destinationD3d9 = Join-Path $GameFolder 'd3d9.dll'
  if ((Test-Path -LiteralPath $destinationD3d9) -and
      ((Get-FileHash -LiteralPath $destinationD3d9 -Algorithm SHA256).Hash -eq
       (Get-FileHash -LiteralPath $d3d9.FullName -Algorithm SHA256).Hash)) {
    Write-Log 'd3d9.dll is already the same FNVVR build.' 'OK'
  } else {
    Backup-File $destinationD3d9
    Copy-Item -LiteralPath $d3d9.FullName -Destination $destinationD3d9 -Force
    Write-Log "Installed d3d9.dll from $($d3d9.FullName)" 'OK'
  }

  $openvrDestination = Join-Path $GameFolder 'openvr_api.dll'
  if (-not (Test-Path -LiteralPath $openvrDestination)) {
    $openvr = Get-ChildItem -LiteralPath $SourceRoot -Filter 'openvr_api.dll' -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object {
        try { (Get-PeInfo $_.FullName).Machine -eq 0x14C } catch { $false }
      } | Select-Object -First 1
    if ($openvr) {
      Copy-Item -LiteralPath $openvr.FullName -Destination $openvrDestination -Force
      Write-Log "Installed openvr_api.dll from $($openvr.FullName)" 'OK'
    } else {
      Add-Problem 'openvr_api.dll is missing from the game folder and was not found in the FNVVR package.'
    }
  } else {
    Write-Log 'openvr_api.dll already present; left it alone.' 'OK'
  }

  $conf = Join-Path $GameFolder 'dxvk.conf'
  if (-not (Test-Path -LiteralPath $conf)) {
    $sourceConf = Get-ChildItem -LiteralPath $SourceRoot -Filter 'dxvk.conf' -Recurse -File -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($sourceConf) {
      Copy-Item -LiteralPath $sourceConf.FullName -Destination $conf -Force
      Write-Log "Installed dxvk.conf from $($sourceConf.FullName)" 'OK'
    } else {
      @(
        'd3d9.vrBackend = openvr',
        'd3d9.hideNvidiaGpu = False',
        'dxvk.logLevel = info'
      ) | Set-Content -LiteralPath $conf -Encoding ASCII
      Write-Log 'Created a minimal dxvk.conf.' 'OK'
    }
  }
  Ensure-VrBackendOpenVr $conf

  $fnvvrDestination = Join-Path $GameFolder 'fnvvr'
  New-Item -ItemType Directory -Path $fnvvrDestination -Force | Out-Null

  $jsonFiles = New-Object System.Collections.ArrayList
  $packageFnvvr = Join-Path $SourceRoot 'fnvvr'
  if (Test-Path -LiteralPath $packageFnvvr) {
    Get-ChildItem -LiteralPath $packageFnvvr -Filter '*.json' -File -Recurse -ErrorAction SilentlyContinue |
      ForEach-Object { [void]$jsonFiles.Add($_) }
  }
  $sourceOpenVr = Join-Path $SourceRoot 'src\d3d9\vr\openvr'
  if (Test-Path -LiteralPath $sourceOpenVr) {
    Get-ChildItem -LiteralPath $sourceOpenVr -Filter '*.json' -File -ErrorAction SilentlyContinue |
      ForEach-Object { [void]$jsonFiles.Add($_) }
  }

  $copiedJson = 0
  foreach ($file in ($jsonFiles | Sort-Object FullName -Unique)) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $fnvvrDestination $file.Name) -Force
    $copiedJson++
  }
  if ($copiedJson -gt 0) {
    Write-Log "Installed $copiedJson action/binding JSON file(s) into fnvvr." 'OK'
  } else {
    Add-Problem 'No FNVVR action/binding JSON files were found in the package or game folder.'
  }

  $textDestination = Join-Path $fnvvrDestination 'texts'
  New-Item -ItemType Directory -Path $textDestination -Force | Out-Null
  $textSources = @(
    (Join-Path $SourceRoot 'fnvvr\texts'),
    (Join-Path $SourceRoot 'src\d3d9\vr\texts')
  )
  foreach ($textSource in $textSources) {
    if (Test-Path -LiteralPath $textSource) {
      Copy-Item -Path (Join-Path $textSource '*.txt') -Destination $textDestination -Force -ErrorAction SilentlyContinue
    }
  }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Log "FNVVR Epic helper started. Log: $script:LogFile"

$game = Resolve-GameFolder $GamePath
Write-Log "Game folder: $game"

$exe = Join-Path $game 'FalloutNV.exe'
$backup = Join-Path $game 'FalloutNV_backup.exe'

if (Get-Process -Name 'FalloutNV' -ErrorAction SilentlyContinue) {
  Fail 'FalloutNV.exe is running. Close the game first.'
}

if (-not (Test-WritableFolder $game)) {
  Fail 'The game folder is not writable. Run this script as Administrator, or move the game out of Program Files.'
}

if ($Restore) {
  if (-not (Test-Path -LiteralPath $backup)) {
    Fail "No FalloutNV_backup.exe found in $game. Nothing to restore."
  }
  $patchedCopy = Join-Path $game 'FalloutNV.patched.exe'
  if (Test-Path -LiteralPath $patchedCopy) { Remove-Item -LiteralPath $patchedCopy -Force }
  Move-Item -LiteralPath $exe -Destination $patchedCopy
  Copy-Item -LiteralPath $backup -Destination $exe -Force
  Write-Log 'Restored the original FalloutNV.exe. The patched copy is FalloutNV.patched.exe.' 'OK'
  Write-Log "Log: $script:LogFile"
  exit 0
}

$info = Get-ExeInfo $exe
Write-Log "FalloutNV.exe: version $($info.Version), SHA-1 $($info.Sha1)" 'INFO'
Write-Log "Detected: $($info.Kind)" 'INFO'

if (-not $info.Hook) {
  if ($info.Version -eq '1.4.0.1338') {
    $patcherFiles = @('Patcher.exe', 'patch.xdelta', 'xdelta3.exe')
    $missing = @($patcherFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $game $_)) })

    if ($missing.Count -gt 0) {
      $message = "This is the Epic 1.4.0.1338 executable. FNVVR needs the 1.4.0.525 code. " +
        "Download the Epic Games Patcher from https://www.nexusmods.com/newvegas/mods/81281 " +
        "and extract Patcher.exe, patch.xdelta and xdelta3.exe into '$game', then rerun this script. " +
        "Missing: $($missing -join ', ')"
      if ($CheckOnly) {
        Add-Problem $message
      } else {
        $open = Show-Question ("This is the Epic 1.4.0.1338 build. FNVVR needs the 1.4.0.525 code.`n`n" +
          "Download the Epic Games Patcher from Nexus Mods, extract Patcher.exe, patch.xdelta and xdelta3.exe into the game folder, then run this helper again.`n`n" +
          "Open the Nexus page now?")
        if ($open) { Start-Process 'https://www.nexusmods.com/newvegas/mods/81281' }
        Show-ErrorBox ("The Epic Games Patcher files are not in the game folder.`n`n" +
          "Download the patcher from Nexus Mods, extract it into:`n$game`n`nThen run this helper again.")
        Fail $message
      }
    } elseif ($CheckOnly) {
      Add-Problem 'Epic Games Patcher files are present but were not run because -CheckOnly is set.'
    } else {
      $run = $false
      if ($RunPatcher) {
        $run = $true
      } elseif ($script:GuiAvailable) {
        $run = Show-Question 'The Epic Games Patcher files were found. Run Patcher.exe now?'
      } else {
        $run = (Read-Host 'Epic Games Patcher files found. Run Patcher.exe now? [y/N]') -match '^[yY]'
      }
      if ($run) {
        Write-Log 'Running Epic Games Patcher...'
        $process = Start-Process -FilePath (Join-Path $game 'Patcher.exe') -WorkingDirectory $game -Wait -PassThru -NoNewWindow
        Write-Log "Patcher exit code: $($process.ExitCode)"
        Start-Sleep -Seconds 1
        $info = Get-ExeInfo $exe
        Write-Log "FalloutNV.exe is now version $($info.Version), SHA-1 $($info.Sha1)"
        Write-Log "Detected: $($info.Kind)"
        if (-not $info.Hook) {
          Fail 'The patcher ran, but the FNVVR hook was still not found. Verify the game files on Epic, then run the patcher again.'
        }
      } else {
        Fail 'Run Patcher.exe in the game folder, then rerun this script.'
      }
    }
  } else {
    $message = "Unsupported or unexpected FalloutNV.exe version '$($info.Version)'. " +
      'FNVVR supports the 1.4.0.525 code. If this is the Epic build, run the Epic Games Patcher.'
    if ($CheckOnly) { Add-Problem $message } else { Fail $message }
  }
}

if (-not (Test-D3dx9_38 $game)) {
  if ($CheckOnly) {
    Add-Problem '32-bit d3dx9_38.dll is missing. The patched Steam code needs it.'
  } elseif ($SkipDirectX) {
    Add-Problem '32-bit d3dx9_38.dll is missing and -SkipDirectX was set.'
  } else {
    Install-D3dx9_38 $game
  }
} else {
  Write-Log '32-bit d3dx9_38.dll is available.' 'OK'
}

$fnvvrSource = Find-FnvVrSource $FnvVrZip $FnvVrSource
$d3d9Path = Join-Path $game 'd3d9.dll'

if ($fnvvrSource) {
  if ($CheckOnly) {
    Write-Log "FNVVR package found at $fnvvrSource; not installing because -CheckOnly is set." 'INFO'
  } else {
    Install-FnvVrFiles $fnvvrSource $game
  }
} elseif (Test-FnvVrDll $d3d9Path) {
  Write-Log 'An FNVVR d3d9.dll is already installed; no package supplied, leaving it alone.' 'OK'
} else {
  $message = 'FNVVR is not installed. Download the FNVVR Reborn package (the zip with d3d9.dll), then run this helper again and select the zip when asked.'
  if ($CheckOnly) {
    Add-Problem $message
  } else {
    Show-ErrorBox ("FNVVR is not installed yet.`n`nDownload the FNVVR Reborn package (the zip that contains d3d9.dll), then run this helper again and select the zip when asked.")
    Fail $message
  }
}

# ---------------------------------------------------------------------------
# Final checks
# ---------------------------------------------------------------------------

Write-Log '--- Final checks ---'

$finalInfo = Get-ExeInfo $exe
if ($finalInfo.Hook) {
  Write-Log 'FalloutNV.exe has the FNVVR hook (0x0086EDE8 -> 0x0086FF70).' 'OK'
} else {
  Add-Problem 'FalloutNV.exe does NOT have the FNVVR hook.'
}

if (Test-D3dx9_38 $game) {
  Write-Log '32-bit d3dx9_38.dll: OK' 'OK'
} else {
  Add-Problem '32-bit d3dx9_38.dll: missing'
}

if (Test-FnvVrDll $d3d9Path) {
  Write-Log 'd3d9.dll: FNVVR 32-bit DLL present' 'OK'
} else {
  Add-Problem 'd3d9.dll: FNVVR 32-bit DLL not detected'
}

$openvrPath = Join-Path $game 'openvr_api.dll'
if (Test-Path -LiteralPath $openvrPath) {
  try {
    $openvrPe = Get-PeInfo $openvrPath
    if ($openvrPe.Machine -eq 0x14C) {
      Write-Log 'openvr_api.dll: 32-bit, present' 'OK'
    } else {
      Add-Problem 'openvr_api.dll is present but is not 32-bit.'
    }
  } catch {
    Add-Problem 'openvr_api.dll could not be read as a 32-bit PE file.'
  }
} else {
  Add-Problem 'openvr_api.dll is missing from the game folder.'
}

$confPath = Join-Path $game 'dxvk.conf'
if (Test-VrBackendOpenVr $confPath) {
  Write-Log 'dxvk.conf: d3d9.vrBackend = openvr' 'OK'
} else {
  Add-Problem 'dxvk.conf does not set d3d9.vrBackend = openvr in its global section.'
}

$actionsPath = Join-Path $game 'fnvvr\actions.json'
if (Test-Path -LiteralPath $actionsPath) {
  Write-Log 'fnvvr\actions.json: present' 'OK'
} else {
  Add-Problem 'fnvvr\actions.json is missing.'
}

$steamVr = Get-Process -Name 'vrserver', 'vrmonitor', 'vrcompositor' -ErrorAction SilentlyContinue
if ($steamVr) {
  Write-Log 'SteamVR processes: running' 'OK'
} else {
  Write-Log 'SteamVR does not appear to be running. Start SteamVR before launching the game.' 'WARN'
}

Write-Log '--- Summary ---'
Write-Log "Game folder: $game"
Write-Log "FalloutNV.exe: $($finalInfo.Version) / $($finalInfo.Sha1)"
Write-Log "Detected: $($finalInfo.Kind)"
Write-Log "Log: $script:LogFile"

if ($script:Problems.Count -gt 0) {
  Write-Log 'Problems found:' 'WARN'
  foreach ($problem in $script:Problems) { Write-Log " - $problem" 'WARN' }
  if (-not $CheckOnly) {
    Show-ErrorBox ("Installation finished with problems:`n`n" + ($script:Problems -join "`n`n") + "`n`nLog: $script:LogFile")
    exit 1
  }
  Show-Info ("Some checks failed:`n`n" + ($script:Problems -join "`n`n") + "`n`nLog: $script:LogFile")
  exit 0
}

if ($CheckOnly) {
  Write-Log 'All checks passed.' 'OK'
  Show-Info 'All checks passed.'
} else {
  Write-Log 'Installation checks passed. Start SteamVR, then launch Fallout: New Vegas from Epic.' 'OK'
  Show-Info ("FNVVR is installed.`n`nStart SteamVR first, then launch Fallout: New Vegas from Epic.`n`nLog: $script:LogFile")
}
exit 0
