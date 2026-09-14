param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$appSource = Join-Path $repoRoot 'MugenDeej.ps1'
$setupSource = Join-Path $repoRoot 'src\setup\setup.ps1'
$appPatch = Join-Path $repoRoot 'tools\patches\Apply-1.0.0.ps1'
$setupPatch = Join-Path $repoRoot 'tools\patches\Apply-Setup-UX.ps1'

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

function Assert-PowerShell51Parse {
    param(
        [Parameter(Mandatory = $true)]$PowerShellCommand,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $oldTarget = $env:MUGEN_DEEJ_PROMOTION_PARSE_TARGET
    $env:MUGEN_DEEJ_PROMOTION_PARSE_TARGET = $Path
    try {
        $parseCommand = @'
$tokens = $null
$parseErrors = $null
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
try {
    $sourceText = [System.IO.File]::ReadAllText($env:MUGEN_DEEJ_PROMOTION_PARSE_TARGET, $utf8)
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
        $env:MUGEN_DEEJ_PROMOTION_PARSE_TARGET = $oldTarget
    }
}

Require-File $appSource
Require-File $setupSource
Require-File $appPatch
Require-File $setupPatch

$windowsPowerShell = Get-Command 'powershell.exe' -ErrorAction SilentlyContinue
if ($null -eq $windowsPowerShell) {
    throw 'powershell.exe (Windows PowerShell 5.1) was not found. Run this promotion on Windows.'
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('MugenDeej-Promote-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $tempApp = Join-Path $tempRoot 'MugenDeej.ps1'
    $tempSetup = Join-Path $tempRoot 'setup.ps1'
    Copy-Item -LiteralPath $appSource -Destination $tempApp -Force
    Copy-Item -LiteralPath $setupSource -Destination $tempSetup -Force

    $currentVersion = Get-ScriptVersion -Path $tempApp
    if ($currentVersion -eq '0.9.0-dev25') {
        Write-Host 'Promoting MugenDeej.ps1 from the tested 0.9.0-dev25 baseline to final 1.0.0...'
        & $appPatch -Path $tempApp
    }
    elseif ($currentVersion -eq '1.0.0') {
        Write-Host 'MugenDeej.ps1 is already at 1.0.0; leaving it unchanged.'
    }
    else {
        throw "Unexpected MugenDeej.ps1 version '$currentVersion'. Expected 0.9.0-dev25 or 1.0.0."
    }

    $setupText = [System.IO.File]::ReadAllText($tempSetup)
    $setupAlreadyPromoted = (
        $setupText.Contains('[System.Windows.Forms.TextRenderer]::MeasureText') -and
        $setupText.Contains('Mugen Deej was not launched automatically.')
    )

    if (-not $setupAlreadyPromoted) {
        Write-Host 'Promoting the tested staged Setup UX into src/setup/setup.ps1...'
        & $setupPatch -Path $tempSetup
    }
    else {
        Write-Host 'src/setup/setup.ps1 already contains the final Setup UX; leaving it unchanged.'
    }

    if ((Get-ScriptVersion -Path $tempApp) -ne '1.0.0') {
        throw 'Promoted MugenDeej.ps1 does not identify itself as 1.0.0.'
    }

    $finalAppText = [System.IO.File]::ReadAllText($tempApp)
    foreach ($requiredMarker in @(
        "$script:AppVersion = '1.0.0'",
        "button-actions.json",
        'BackupMenu',
        'MugenDeej_PreRestore_'
    )) {
        if (-not $finalAppText.Contains($requiredMarker)) {
            throw "Promoted MugenDeej.ps1 is missing expected marker: $requiredMarker"
        }
    }

    $finalSetupText = [System.IO.File]::ReadAllText($tempSetup)
    foreach ($requiredMarker in @(
        '[System.Windows.Forms.TextRenderer]::MeasureText',
        'LaunchSuppressedByOtherInstance',
        'Mugen Deej was not launched automatically.'
    )) {
        if (-not $finalSetupText.Contains($requiredMarker)) {
            throw "Promoted setup.ps1 is missing expected marker: $requiredMarker"
        }
    }

    Assert-PowerShell51Parse -PowerShellCommand $windowsPowerShell -Path $tempApp -Label 'Promoted MugenDeej.ps1'
    Assert-PowerShell51Parse -PowerShellCommand $windowsPowerShell -Path $tempSetup -Label 'Promoted setup.ps1'

    Copy-Item -LiteralPath $tempApp -Destination $appSource -Force
    Copy-Item -LiteralPath $tempSetup -Destination $setupSource -Force

    Write-Host ''
    Write-Host 'Source promotion completed successfully.' -ForegroundColor Green
    Write-Host 'Changed source files:'
    Write-Host '  MugenDeej.ps1'
    Write-Host '  src\setup\setup.ps1'
    Write-Host ''
    Write-Host 'Next: review the Git diff. Do not delete tools\patches yet; the builder still references them until the cleanup commit.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
