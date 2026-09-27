param(
    [string]$Version = '',
    [string]$OutputDir = 'artifacts',
    [string]$LauncherPath = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Require-File {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file is missing: $Path"
    }
}

function Get-ScriptVersion {
    param([Parameter(Mandatory = $true)][string]$Path)

    $firstLine = Get-Content -LiteralPath $Path -TotalCount 1 -Encoding UTF8
    if ($firstLine -notmatch '^# Mugen Deej (?<version>.+)$') {
        throw "Could not read the application version from $Path."
    }

    return $Matches['version'].Trim()
}

function Get-GoCommand {
    $go = Get-Command 'go.exe' -ErrorAction SilentlyContinue
    if ($null -eq $go) { $go = Get-Command 'go' -ErrorAction SilentlyContinue }
    return $go
}

function Get-DotNetCommand {
    $dotnet = Get-Command 'dotnet.exe' -ErrorAction SilentlyContinue
    if ($null -eq $dotnet) { $dotnet = Get-Command 'dotnet' -ErrorAction SilentlyContinue }
    return $dotnet
}

function Assert-Utf8Bom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
    if (
        $bytes.Length -lt 3 -or
        $bytes[0] -ne 0xEF -or
        $bytes[1] -ne 0xBB -or
        $bytes[2] -ne 0xBF
    ) {
        throw "$Label must carry a UTF-8 BOM for Windows PowerShell 5.1."
    }
}

function Assert-PowerShell51Parse {
    param(
        [Parameter(Mandatory = $true)]$PowerShellCommand,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $oldParseTarget = $env:MUGEN_DEEJ_PARSE_TARGET
    $env:MUGEN_DEEJ_PARSE_TARGET = $Path
    try {
        $parseCommand = @'
$tokens = $null
$parseErrors = $null
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
try {
    $sourceText = [System.IO.File]::ReadAllText($env:MUGEN_DEEJ_PARSE_TARGET, $utf8)
}
catch {
    [Console]::Error.WriteLine(('Could not decode PowerShell source as UTF-8: {0}' -f $_.Exception.Message))
    exit 3
}
[System.Management.Automation.Language.Parser]::ParseInput($sourceText, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) {
    foreach ($parseError in $parseErrors) {
        [Console]::Error.WriteLine(('PowerShell parse error at {0}:{1}: {2}' -f $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message))
    }
    exit 2
}
exit 0
'@
        & $PowerShellCommand.Source -NoProfile -ExecutionPolicy Bypass -Command $parseCommand
        if ($LASTEXITCODE -ne 0) {
            throw "$Label failed the Windows PowerShell 5.1 parse check with exit code $LASTEXITCODE."
        }
    }
    finally {
        $env:MUGEN_DEEJ_PARSE_TARGET = $oldParseTarget
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceScript = Join-Path $repoRoot 'MugenDeej.ps1'
$versionFile = Join-Path $repoRoot 'VERSION.txt'
$templatePath = Join-Path $repoRoot 'packaging\README.txt.template'
$launcherDir = Join-Path $repoRoot 'src\launcher'
$setupDir = Join-Path $repoRoot 'src\setup'
$virtualModuleSource = Join-Path $repoRoot 'src\virtual-gamepad-integration\MugenDeej.VirtualGamepad.ps1'
$helperProject = Join-Path $repoRoot 'src\virtual-gamepad-helper\MugenDeej.VirtualGamepadHost.csproj'
$helperDepsDir = Join-Path $repoRoot 'src\virtual-gamepad-helper\deps'
$prepareHidScript = Join-Path $repoRoot 'tools\Prepare-HIDMaestro.ps1'
$firmwareSource = Join-Path $repoRoot 'arduino\MugenDeejCardboardNanoPrototype\MugenDeejCardboardNanoPrototype.ino'
$iconPath = Join-Path $repoRoot 'MugenDeej.ico'

Require-File $sourceScript
Require-File $versionFile
Require-File $templatePath
Require-File $iconPath
Require-File (Join-Path $launcherDir 'main.go')
Require-File (Join-Path $launcherDir 'go.mod')
Require-File (Join-Path $setupDir 'main.go')
Require-File (Join-Path $setupDir 'go.mod')
Require-File (Join-Path $setupDir 'setup.ps1')
Require-File $virtualModuleSource
Require-File $helperProject
Require-File $prepareHidScript
Require-File $firmwareSource

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = (Get-Content -LiteralPath $versionFile -Raw -Encoding UTF8).Trim()
}

if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$') {
    throw "Invalid release version '$Version'. Expected a value such as 1.0.0, 1.0.0-rc1, or 0.9.0-dev25."
}

$sourceVersion = Get-ScriptVersion -Path $sourceScript
if ($sourceVersion -ne $Version) {
    throw "Version mismatch: VERSION/build request is '$Version' but MugenDeej.ps1 identifies itself as '$sourceVersion'. Update the source version before packaging."
}

if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $outputRoot = $OutputDir
}
else {
    $outputRoot = Join-Path $repoRoot $OutputDir
}

$packageBaseName = "Mugen-Deej-$Version-Portable"
$stageDir = Join-Path $outputRoot $packageBaseName
$zipPath = Join-Path $outputRoot ($packageBaseName + '.zip')
$zipChecksumPath = $zipPath + '.sha256'
$setupPath = Join-Path $outputRoot ("Mugen-Deej-$Version-Setup.exe")
$setupChecksumPath = $setupPath + '.sha256'

foreach ($path in @($stageDir, $zipPath, $zipChecksumPath, $setupPath, $setupChecksumPath)) {
    if (Test-Path -LiteralPath $path) {
        if ((Get-Item -LiteralPath $path).PSIsContainer) { Remove-Item -LiteralPath $path -Recurse -Force }
        else { Remove-Item -LiteralPath $path -Force }
    }
}

New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

$stagedScript = Join-Path $stageDir 'MugenDeej.ps1'
$virtualRoot = Join-Path $stageDir 'virtual-gamepad'
$hostOut = Join-Path $virtualRoot 'host'
$stagedVirtualModule = Join-Path $virtualRoot 'MugenDeej.VirtualGamepad.ps1'
$firmwareRoot = Join-Path $stageDir 'firmware\MugenDeejCardboardNanoPrototype'
New-Item -ItemType Directory -Path $hostOut -Force | Out-Null
New-Item -ItemType Directory -Path $firmwareRoot -Force | Out-Null

Copy-Item -LiteralPath $sourceScript -Destination $stagedScript -Force
Copy-Item -LiteralPath $virtualModuleSource -Destination $stagedVirtualModule -Force
Copy-Item -LiteralPath $firmwareSource -Destination (Join-Path $firmwareRoot 'MugenDeejCardboardNanoPrototype.ino') -Force

$windowsPowerShell = Get-Command 'powershell.exe' -ErrorAction SilentlyContinue
if ($null -eq $windowsPowerShell) {
    throw 'powershell.exe (Windows PowerShell 5.1) was not found. Release packages must be built on Windows.'
}

Assert-Utf8Bom -Path $stagedScript -Label 'Staged MugenDeej.ps1'
Assert-Utf8Bom -Path $stagedVirtualModule -Label 'Staged virtual-gamepad module'
Assert-PowerShell51Parse -PowerShellCommand $windowsPowerShell -Path $stagedScript -Label 'Staged MugenDeej.ps1'
Assert-PowerShell51Parse -PowerShellCommand $windowsPowerShell -Path $stagedVirtualModule -Label 'Staged virtual-gamepad module'
Assert-PowerShell51Parse -PowerShellCommand $windowsPowerShell -Path (Join-Path $setupDir 'setup.ps1') -Label 'Setup wizard script'

# Reproduce the pinned virtual-controller backend used by the hardware-proven RC.
& $prepareHidScript -DestinationDir $helperDepsDir
$hidLicense = Join-Path $helperDepsDir 'HIDMaestro-LICENSE.txt'
Require-File (Join-Path $helperDepsDir 'HIDMaestro.Core.dll')
Require-File $hidLicense
Copy-Item -LiteralPath $hidLicense -Destination (Join-Path $virtualRoot 'HIDMaestro-LICENSE.txt') -Force

$dotnet = Get-DotNetCommand
if ($null -eq $dotnet) {
    throw '.NET SDK was not found in PATH. Building the virtual-controller helper requires .NET 10.'
}

Write-Host 'Publishing self-contained virtual-controller helper...'
& $dotnet.Source publish $helperProject `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -o $hostOut
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE"
}

$helperExe = Join-Path $hostOut 'MugenDeej.VirtualGamepadHost.exe'
Require-File $helperExe
& $helperExe --help
if ($LASTEXITCODE -ne 0) {
    throw "Published virtual-controller helper smoke check failed with exit code $LASTEXITCODE"
}

$launcherOutput = Join-Path $stageDir 'MugenDeej.exe'

if (-not [string]::IsNullOrWhiteSpace($LauncherPath)) {
    $resolvedLauncher = (Resolve-Path -LiteralPath $LauncherPath).Path
    Require-File $resolvedLauncher
    Copy-Item -LiteralPath $resolvedLauncher -Destination $launcherOutput -Force
}
else {
    $go = Get-GoCommand
    if ($null -eq $go) {
        throw 'Go was not found in PATH. Install Go 1.20+ or pass -LauncherPath with a trusted prebuilt MugenDeej.exe.'
    }

    $resourceFile = Join-Path $launcherDir 'rsrc_windows_amd64.syso'
    $oldGOOS = $env:GOOS
    $oldGOARCH = $env:GOARCH
    $oldCGO = $env:CGO_ENABLED

    Push-Location $launcherDir
    try {
        if (Test-Path -LiteralPath $resourceFile) { Remove-Item -LiteralPath $resourceFile -Force }

        Write-Host 'Generating Windows launcher icon resource...'
        & $go.Source run 'github.com/akavel/rsrc@v0.10.2' '-arch' 'amd64' '-ico' $iconPath '-o' $resourceFile
        if ($LASTEXITCODE -ne 0) { throw "rsrc failed with exit code $LASTEXITCODE" }

        $env:GOOS = 'windows'
        $env:GOARCH = 'amd64'
        $env:CGO_ENABLED = '0'

        Write-Host 'Building MugenDeej.exe launcher...'
        & $go.Source build '-trimpath' '-ldflags' '-H windowsgui -s -w' '-o' $launcherOutput '.'
        if ($LASTEXITCODE -ne 0) { throw "go build failed with exit code $LASTEXITCODE" }
    }
    finally {
        Pop-Location
        if (Test-Path -LiteralPath $resourceFile) { Remove-Item -LiteralPath $resourceFile -Force }
        $env:GOOS = $oldGOOS
        $env:GOARCH = $oldGOARCH
        $env:CGO_ENABLED = $oldCGO
    }
}

Require-File $launcherOutput
if ((Get-Item -LiteralPath $launcherOutput).Length -lt 100000) {
    throw 'Built launcher is unexpectedly small; refusing to package it.'
}

$copyMap = @(
    @{ Source = 'MugenDeej.ico'; Destination = 'MugenDeej.ico' },
    @{ Source = 'MugenDeej-Debug.cmd'; Destination = 'MugenDeej-Debug.cmd' },
    @{ Source = 'LICENSE'; Destination = 'LICENSE' },
    @{ Source = 'THIRD_PARTY_NOTICES.md'; Destination = 'THIRD_PARTY_NOTICES.md' }
)

foreach ($item in $copyMap) {
    $source = Join-Path $repoRoot $item.Source
    Require-File $source
    Copy-Item -LiteralPath $source -Destination (Join-Path $stageDir $item.Destination) -Force
}

$readmeTemplate = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
$readmeText = $readmeTemplate.Replace('{{VERSION}}', $Version)
Write-Utf8NoBom -Path (Join-Path $stageDir 'README.txt') -Text $readmeText

$manifestFiles = @(
    Get-ChildItem -LiteralPath $stageDir -Recurse -File |
        Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
        Sort-Object FullName
)

$manifestLines = foreach ($file in $manifestFiles) {
    $relative = $file.FullName.Substring($stageDir.Length).TrimStart('\')
    $relative = $relative -replace '\\', '/'
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $relative"
}
Write-Utf8NoBom -Path (Join-Path $stageDir 'SHA256SUMS.txt') -Text (($manifestLines -join "`r`n") + "`r`n")

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $stageDir,
    $zipPath,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)

$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Utf8NoBom -Path $zipChecksumPath -Text ("$zipHash  $([System.IO.Path]::GetFileName($zipPath))`r`n")

# Build a self-contained Setup EXE around the exact portable ZIP produced above.
# The setup executable only extracts files and can create a desktop shortcut;
# it does not register an uninstall entry or write application installation keys.
$goSetup = Get-GoCommand
if ($null -eq $goSetup) {
    throw 'Go was not found in PATH. Building the Setup EXE requires Go 1.20+.'
}

$setupBuildDir = Join-Path $outputRoot ('.setup-build-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $setupBuildDir -Force | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $setupDir 'main.go') -Destination (Join-Path $setupBuildDir 'main.go') -Force
    Copy-Item -LiteralPath (Join-Path $setupDir 'go.mod') -Destination (Join-Path $setupBuildDir 'go.mod') -Force
    Copy-Item -LiteralPath (Join-Path $setupDir 'setup.ps1') -Destination (Join-Path $setupBuildDir 'setup.ps1') -Force
    Copy-Item -LiteralPath $zipPath -Destination (Join-Path $setupBuildDir 'payload.zip') -Force

    $stagedSetupScript = Join-Path $setupBuildDir 'setup.ps1'
    Assert-PowerShell51Parse -PowerShellCommand $windowsPowerShell -Path $stagedSetupScript -Label 'Staged Setup wizard script'

    $setupResource = Join-Path $setupBuildDir 'rsrc_windows_amd64.syso'
    $oldGOOS = $env:GOOS
    $oldGOARCH = $env:GOARCH
    $oldCGO = $env:CGO_ENABLED

    Push-Location $setupBuildDir
    try {
        Write-Host 'Generating Windows Setup icon resource...'
        & $goSetup.Source run 'github.com/akavel/rsrc@v0.10.2' '-arch' 'amd64' '-ico' $iconPath '-o' $setupResource
        if ($LASTEXITCODE -ne 0) { throw "setup rsrc failed with exit code $LASTEXITCODE" }

        $env:GOOS = 'windows'
        $env:GOARCH = 'amd64'
        $env:CGO_ENABLED = '0'
        $setupLdFlags = "-H windowsgui -s -w -X main.version=$Version"

        Write-Host 'Building self-extracting Setup EXE...'
        & $goSetup.Source build '-trimpath' '-ldflags' $setupLdFlags '-o' $setupPath '.'
        if ($LASTEXITCODE -ne 0) { throw "setup go build failed with exit code $LASTEXITCODE" }
    }
    finally {
        Pop-Location
        $env:GOOS = $oldGOOS
        $env:GOARCH = $oldGOARCH
        $env:CGO_ENABLED = $oldCGO
    }
}
finally {
    if (Test-Path -LiteralPath $setupBuildDir) { Remove-Item -LiteralPath $setupBuildDir -Recurse -Force }
}

Require-File $setupPath
if ((Get-Item -LiteralPath $setupPath).Length -lt 500000) {
    throw 'Built Setup EXE is unexpectedly small; refusing to publish it.'
}

$setupHash = (Get-FileHash -LiteralPath $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Utf8NoBom -Path $setupChecksumPath -Text ("$setupHash  $([System.IO.Path]::GetFileName($setupPath))`r`n")

Write-Host ''
Write-Host "Portable package ready: $zipPath"
Write-Host "Archive SHA-256:      $zipHash"
Write-Host "Archive checksum:     $zipChecksumPath"
Write-Host "Setup package ready:  $setupPath"
Write-Host "Setup SHA-256:        $setupHash"
Write-Host "Setup checksum:       $setupChecksumPath"
Write-Host "Staging directory:    $stageDir"
