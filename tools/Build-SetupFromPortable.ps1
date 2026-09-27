param(
    [Parameter(Mandatory = $true)][string]$PortableZip,
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$OutputDir = 'artifacts'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Require-File {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file is missing: $Path"
    }
}

function Get-GoCommand {
    $go = Get-Command 'go.exe' -ErrorAction SilentlyContinue
    if ($null -eq $go) { $go = Get-Command 'go' -ErrorAction SilentlyContinue }
    return $go
}

function Assert-PowerShell51Parse {
    param([Parameter(Mandatory = $true)][string]$Path)

    $windowsPowerShell = Get-Command 'powershell.exe' -ErrorAction SilentlyContinue
    if ($null -eq $windowsPowerShell) {
        throw 'powershell.exe (Windows PowerShell 5.1) was not found.'
    }

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
    [Console]::Error.WriteLine(('Could not decode Setup source as UTF-8: {0}' -f $_.Exception.Message))
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
        & $windowsPowerShell.Source -NoProfile -ExecutionPolicy Bypass -Command $parseCommand
        if ($LASTEXITCODE -ne 0) {
            throw "Setup wizard script failed the Windows PowerShell 5.1 parse check with exit code $LASTEXITCODE."
        }
    }
    finally {
        $env:MUGEN_DEEJ_PARSE_TARGET = $oldParseTarget
    }
}

if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$') {
    throw "Invalid release version '$Version'."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$setupDir = Join-Path $repoRoot 'src\setup'
$iconPath = Join-Path $repoRoot 'MugenDeej.ico'

Require-File $PortableZip
Require-File (Join-Path $setupDir 'main.go')
Require-File (Join-Path $setupDir 'go.mod')
Require-File (Join-Path $setupDir 'setup.ps1')
Require-File $iconPath

$portableZipPath = (Resolve-Path -LiteralPath $PortableZip).Path
if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $outputRoot = $OutputDir
}
else {
    $outputRoot = Join-Path $repoRoot $OutputDir
}
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$outputRoot = (Resolve-Path -LiteralPath $outputRoot).Path

$setupPath = Join-Path $outputRoot ("Mugen-Deej-$Version-Setup.exe")
$setupChecksumPath = $setupPath + '.sha256'

foreach ($path in @($setupPath, $setupChecksumPath)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

$go = Get-GoCommand
if ($null -eq $go) {
    throw 'Go was not found in PATH. Building the Setup EXE requires Go 1.20+.'
}

$payloadHash = (Get-FileHash -LiteralPath $portableZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$setupBuildDir = Join-Path $outputRoot ('.setup-build-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $setupBuildDir -Force | Out-Null

try {
    Copy-Item -LiteralPath (Join-Path $setupDir 'main.go') -Destination (Join-Path $setupBuildDir 'main.go') -Force
    Copy-Item -LiteralPath (Join-Path $setupDir 'go.mod') -Destination (Join-Path $setupBuildDir 'go.mod') -Force
    Copy-Item -LiteralPath (Join-Path $setupDir 'setup.ps1') -Destination (Join-Path $setupBuildDir 'setup.ps1') -Force
    Copy-Item -LiteralPath $portableZipPath -Destination (Join-Path $setupBuildDir 'payload.zip') -Force

    $stagedSetupScript = Join-Path $setupBuildDir 'setup.ps1'
    Assert-PowerShell51Parse -Path $stagedSetupScript

    $setupResource = Join-Path $setupBuildDir 'rsrc_windows_amd64.syso'
    $oldGOOS = $env:GOOS
    $oldGOARCH = $env:GOARCH
    $oldCGO = $env:CGO_ENABLED

    Push-Location $setupBuildDir
    try {
        Write-Host 'Generating Windows Setup icon resource...'
        & $go.Source run 'github.com/akavel/rsrc@v0.10.2' '-arch' 'amd64' '-ico' $iconPath '-o' $setupResource
        if ($LASTEXITCODE -ne 0) { throw "setup rsrc failed with exit code $LASTEXITCODE" }

        $env:GOOS = 'windows'
        $env:GOARCH = 'amd64'
        $env:CGO_ENABLED = '0'
        $setupLdFlags = "-H windowsgui -s -w -X main.version=$Version"

        Write-Host 'Building self-extracting Setup EXE from the existing portable payload...'
        & $go.Source build '-trimpath' '-ldflags' $setupLdFlags '-o' $setupPath '.'
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
    if (Test-Path -LiteralPath $setupBuildDir) {
        Remove-Item -LiteralPath $setupBuildDir -Recurse -Force
    }
}

Require-File $setupPath
if ((Get-Item -LiteralPath $setupPath).Length -lt 500000) {
    throw 'Built Setup EXE is unexpectedly small; refusing to publish it.'
}

$setupHash = (Get-FileHash -LiteralPath $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText(
    $setupChecksumPath,
    "$setupHash  $([System.IO.Path]::GetFileName($setupPath))`r`n",
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ''
Write-Host "Portable payload:       $portableZipPath"
Write-Host "Portable SHA-256:       $payloadHash"
Write-Host "Setup package ready:    $setupPath"
Write-Host "Setup SHA-256:          $setupHash"
Write-Host "Setup checksum:         $setupChecksumPath"
