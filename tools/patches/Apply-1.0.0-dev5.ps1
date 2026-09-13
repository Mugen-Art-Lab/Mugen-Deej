param(
    [Parameter(Mandatory = $true)][string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$dev4Patch = Join-Path $PSScriptRoot 'Apply-1.0.0-dev4.ps1'
if (-not (Test-Path -LiteralPath $dev4Patch -PathType Leaf)) {
    throw "Required dev4 patch was not found: $dev4Patch"
}

& $dev4Patch -Path $Path

$text = [System.IO.File]::ReadAllText($Path)

function Replace-ExactOnce {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][string]$New,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $first = $Text.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Patch marker was not found: $Label" }
    $second = $Text.IndexOf($Old, $first + $Old.Length, [System.StringComparison]::Ordinal)
    if ($second -ge 0) { throw "Patch marker is not unique: $Label" }
    return $Text.Substring(0, $first) + $New + $Text.Substring($first + $Old.Length)
}

$text = Replace-ExactOnce -Text $text -Old '# Mugen Deej 1.0.0-dev4' -New '# Mugen Deej 1.0.0-dev5' -Label 'header version'
$text = Replace-ExactOnce -Text $text -Old '$script:AppVersion = ''1.0.0-dev4''' -New '$script:AppVersion = ''1.0.0-dev5''' -Label 'runtime version'

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($Path, $text, $utf8Bom)

Write-Host 'Applied Mugen Deej 1.0.0-dev5 packaging milestone patch.'
