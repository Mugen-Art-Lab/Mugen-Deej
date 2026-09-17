param(
    [Parameter(Mandatory = $true)][string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'Optimize-LargeButtonSettings.ps1'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Missing optimizer script: $source"
}

$text = [System.IO.File]::ReadAllText($source, [System.Text.Encoding]::UTF8)

$oldTail = @'
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText 'function Show-ButtonSettings {' `
    -NewText ($largeEditor + "function Show-ButtonSettings {") `
    -Label 'insert optimized large button editor'

$dispatchOld = @'
function Show-ButtonSettings {
    if (
        -not $script:IsConnected -or
        $script:DetectedButtonCount -le 0
'@
$dispatchNew = @'
function Show-ButtonSettings {
    if ($script:IsConnected -and $script:DetectedButtonCount -gt 12) {
        Show-LargeButtonSettings
        return
    }

    if (
        -not $script:IsConnected -or
        $script:DetectedButtonCount -le 0
'@
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $dispatchOld `
    -NewText $dispatchNew `
    -Label 'dispatch large controllers to optimized editor'
'@

$newTail = @'
$largeDispatch = @'
function Show-ButtonSettings {
    if ($script:IsConnected -and $script:DetectedButtonCount -gt 12) {
        Show-LargeButtonSettings
        return
    }
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText 'function Show-ButtonSettings {' `
    -NewText ($largeEditor + $largeDispatch) `
    -Label 'insert optimized large button editor and dispatch'
'@

$first = $text.IndexOf($oldTail, [System.StringComparison]::Ordinal)
$last = $text.LastIndexOf($oldTail, [System.StringComparison]::Ordinal)
if ($first -lt 0 -or $first -ne $last) {
    throw 'Optimizer runner expected exactly one dispatch-tail anchor.'
}

$text = $text.Substring(0, $first) + $newTail + $text.Substring($first + $oldTail.Length)

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('MugenDeej-OptimizeLargeButtons-' + [Guid]::NewGuid().ToString('N') + '.ps1')
try {
    [System.IO.File]::WriteAllText($temp, $text, (New-Object System.Text.UTF8Encoding($false)))
    & $temp -Path $Path
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
