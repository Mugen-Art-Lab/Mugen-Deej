param(
    [Parameter(Mandatory = $true)][string[]]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

# The integration workflow calls this after every feature-stage patch has been
# applied. Use that final runtime pass to apply topology hardening after the
# compact #30 UI revision, then normalize encoding for Windows PowerShell 5.1.
$topologyHardener = Join-Path $PSScriptRoot 'Harden-AdaptiveTopologyUi.ps1'
if (-not (Test-Path -LiteralPath $topologyHardener -PathType Leaf)) {
    throw "Missing Adaptive topology hardener: $topologyHardener"
}

$adaptiveMappings = Join-Path $PSScriptRoot 'Add-AdaptiveControlMappings.ps1'
if (-not (Test-Path -LiteralPath $adaptiveMappings -PathType Leaf)) {
    throw "Missing Adaptive controls mapping patch: $adaptiveMappings"
}

foreach ($candidate in @($Path)) {
    $resolved = (Resolve-Path -LiteralPath $candidate).Path

    if ([System.IO.Path]::GetFileName($resolved) -ieq 'MugenDeej.ps1') {
        & $topologyHardener -Path $resolved
        & $adaptiveMappings -Path $resolved
    }

    $bytes = [System.IO.File]::ReadAllBytes($resolved)

    $offset = 0
    if (
        $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    ) {
        $offset = 3
    }

    $text = $utf8Strict.GetString($bytes, $offset, ($bytes.Length - $offset))
    [System.IO.File]::WriteAllText($resolved, $text, $utf8Bom)

    $written = [System.IO.File]::ReadAllBytes($resolved)
    if (
        $written.Length -lt 3 -or
        $written[0] -ne 0xEF -or
        $written[1] -ne 0xBB -or
        $written[2] -ne 0xBF
    ) {
        throw "Failed to write UTF-8 BOM: $resolved"
    }

    Write-Host "Windows PowerShell UTF-8 BOM ensured: $resolved"
}
