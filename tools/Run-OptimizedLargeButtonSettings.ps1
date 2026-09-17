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

# The first optimizer version tried to patch the beginning of Show-ButtonSettings
# after v17 had already rewritten that function. Replace only the optimizer's own
# final dispatch block with a simpler insertion that does not depend on the old
# function body at all.
$tailStart = $text.LastIndexOf("`n`$text = Replace-LiteralExactlyOnce", [System.StringComparison]::Ordinal)
$tailEnd = $text.LastIndexOf("`n`$utf8 = New-Object System.Text.UTF8Encoding", [System.StringComparison]::Ordinal)
if ($tailStart -lt 0 -or $tailEnd -le $tailStart) {
    throw 'Optimizer runner could not locate the final dispatch block.'
}

$newTail = @'
$largeDispatch = @(
    'function Show-ButtonSettings {'
    '    if ($script:IsConnected -and $script:DetectedButtonCount -gt 12) {'
    '        Show-LargeButtonSettings'
    '        return'
    '    }'
    ''
) -join "`n"
$largeDispatch += "`n"

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText 'function Show-ButtonSettings {' `
    -NewText ($largeEditor + $largeDispatch) `
    -Label 'insert optimized large button editor and dispatch'
'@

$text = $text.Substring(0, $tailStart + 1) + $newTail + $text.Substring($tailEnd)

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('MugenDeej-OptimizeLargeButtons-' + [Guid]::NewGuid().ToString('N') + '.ps1')
try {
    [System.IO.File]::WriteAllText(
        $temp,
        $text,
        (New-Object System.Text.UTF8Encoding($false))
    )
    & $temp -Path $Path
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
