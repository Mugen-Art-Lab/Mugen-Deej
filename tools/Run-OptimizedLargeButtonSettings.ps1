param(
    [Parameter(Mandatory = $true)][string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Replace-OptimizerLiteralExactlyOnce {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$OldText,
        [Parameter(Mandatory = $true)][string]$NewText,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $first = $Text.IndexOf($OldText, [System.StringComparison]::Ordinal)
    $last = $Text.LastIndexOf($OldText, [System.StringComparison]::Ordinal)
    if ($first -lt 0 -or $first -ne $last) {
        throw "Optimizer runner patch '$Label' expected exactly one literal match."
    }

    return $Text.Substring(0, $first) + $NewText + $Text.Substring($first + $OldText.Length)
}

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

# v21 linked ListView.SelectedIndexChanged -> selectButton -> item.Selected = $true
# -> SelectedIndexChanged again. Windows PowerShell therefore recursed until its
# script call-depth limit was exhausted. Add an explicit selection-synchronizing
# guard before staging the optimizer so programmatic list selection cannot re-enter
# the same handler.
$stateOld = @'
        ActionMap = New-Object System.Collections.ArrayList
        SuppressCombo = $false
    }
'@
$stateNew = @'
        ActionMap = New-Object System.Collections.ArrayList
        SuppressCombo = $false
        SuppressListSelection = $false
    }
'@
$text = Replace-OptimizerLiteralExactlyOnce `
    -Text $text `
    -OldText $stateOld `
    -NewText $stateNew `
    -Label 'add assignment-list selection guard state'

$selectOld = @'
        foreach ($item in $assignmentList.Items) {
            if ([int]$item.Tag -eq $Index) {
                $item.Selected = $true
                $item.EnsureVisible()
                break
            }
        }
'@
$selectNew = @'
        $state.SuppressListSelection = $true
        try {
            foreach ($item in $assignmentList.Items) {
                if ([int]$item.Tag -eq $Index) {
                    if (-not $item.Selected) {
                        $item.Selected = $true
                    }
                    $item.EnsureVisible()
                    break
                }
            }
        }
        finally {
            $state.SuppressListSelection = $false
        }
'@
$text = Replace-OptimizerLiteralExactlyOnce `
    -Text $text `
    -OldText $selectOld `
    -NewText $selectNew `
    -Label 'guard programmatic assignment-list selection'

$listHandlerOld = @'
    $assignmentList.Add_SelectedIndexChanged({
        if ($assignmentList.SelectedItems.Count -eq 0) { return }
        & $selectButton -Index ([int]$assignmentList.SelectedItems[0].Tag)
    })
'@
$listHandlerNew = @'
    $assignmentList.Add_SelectedIndexChanged({
        if ($state.SuppressListSelection) { return }
        if ($assignmentList.SelectedItems.Count -eq 0) { return }

        $targetIndex = [int]$assignmentList.SelectedItems[0].Tag
        if ($targetIndex -eq [int]$state.Selected) { return }
        & $selectButton -Index $targetIndex
    })
'@
$text = Replace-OptimizerLiteralExactlyOnce `
    -Text $text `
    -OldText $listHandlerOld `
    -NewText $listHandlerNew `
    -Label 'block recursive assignment-list SelectedIndexChanged'

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

# Adaptive status UI v24 accidentally used $host as a local panel variable.
# PowerShell variable names are case-insensitive, so this collides with the
# built-in read-only $Host automatic variable and throws as soon as an encoder
# indicator is created. Older staged runtimes still need this repair; newer
# polished status UI already uses an explicitly safe encoder host variable.
$runtime = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path, [System.Text.Encoding]::UTF8)
$encoderStartMarker = 'function Ensure-MainEncoderIndicators {'
$encoderEndMarker = 'function Update-AdaptiveInputIndicators {'
$encoderStart = $runtime.IndexOf($encoderStartMarker, [System.StringComparison]::Ordinal)
$encoderEnd = if ($encoderStart -ge 0) {
    $runtime.IndexOf($encoderEndMarker, $encoderStart, [System.StringComparison]::Ordinal)
}
else {
    -1
}

if ($encoderStart -lt 0 -or $encoderEnd -le $encoderStart) {
    throw 'Adaptive encoder Host-collision fix could not locate the generated encoder indicator block.'
}

$encoderBlock = $runtime.Substring($encoderStart, $encoderEnd - $encoderStart)
$hostCount = [regex]::Matches($encoderBlock, '\$host\b').Count

if ($hostCount -eq 8) {
    $fixedEncoderBlock = $encoderBlock.Replace('$host', '$encoderHost')
    $runtime = $runtime.Substring(0, $encoderStart) + $fixedEncoderBlock + $runtime.Substring($encoderEnd)

    [System.IO.File]::WriteAllText(
        (Resolve-Path -LiteralPath $Path).Path,
        $runtime,
        (New-Object System.Text.UTF8Encoding($false))
    )

    Write-Host 'Fixed Adaptive encoder UI collision with PowerShell automatic $Host variable.'
}
elif ($hostCount -eq 0 -and $encoderBlock -match '\$encoder(?:Item)?Host\b') {
    Write-Host 'Adaptive encoder UI already uses a safe host variable; legacy Host-collision repair skipped.'
}
else {
    throw "Adaptive encoder Host-collision compatibility check found unexpected encoder block state: `$host references=$hostCount."
}
