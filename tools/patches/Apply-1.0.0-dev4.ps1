param(
    [Parameter(Mandatory = $true)][string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$dev3Patch = Join-Path $PSScriptRoot 'Apply-1.0.0-dev3.ps1'
if (-not (Test-Path -LiteralPath $dev3Patch -PathType Leaf)) {
    throw "Required dev3 patch was not found: $dev3Patch"
}

& $dev3Patch -Path $Path

$text = [System.IO.File]::ReadAllText($Path)

function Replace-ExactOnce {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][string]$New,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $first = $Text.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($first -lt 0) {
        throw "Patch marker was not found: $Label"
    }

    $second = $Text.IndexOf($Old, $first + $Old.Length, [System.StringComparison]::Ordinal)
    if ($second -ge 0) {
        throw "Patch marker is not unique: $Label"
    }

    return $Text.Substring(0, $first) + $New + $Text.Substring($first + $Old.Length)
}

$text = Replace-ExactOnce -Text $text -Old '# Mugen Deej 1.0.0-dev3' -New '# Mugen Deej 1.0.0-dev4' -Label 'header version'
$text = Replace-ExactOnce -Text $text -Old '$script:AppVersion = ''1.0.0-dev3''' -New '$script:AppVersion = ''1.0.0-dev4''' -Label 'runtime version'

$oldLaunchMinimized = '$script:LaunchMinimized = [bool]$script:Config.app.startMinimized'
$newLaunchMinimized = @'
$script:ForceShowAfterRestore = ($env:MUGEN_DEEJ_SHOW_AFTER_RESTORE -eq '1')
if ($script:ForceShowAfterRestore) {
    Remove-Item Env:\MUGEN_DEEJ_SHOW_AFTER_RESTORE -ErrorAction SilentlyContinue
    Write-Log 'One-shot visible launch requested after backup restore.' 'INFO'
}
$script:LaunchMinimized = ([bool]$script:Config.app.startMinimized) -and (-not $script:ForceShowAfterRestore)
'@
$text = Replace-ExactOnce -Text $text -Old $oldLaunchMinimized -New ($newLaunchMinimized.TrimEnd()) -Label 'one-shot visible launch state'

$oldShownStartMinimized = '    $startMinimized = [bool]$script:Config.app.startMinimized'
$newShownStartMinimized = '    $startMinimized = ([bool]$script:Config.app.startMinimized) -and (-not $script:ForceShowAfterRestore)'
$text = Replace-ExactOnce -Text $text -Old $oldShownStartMinimized -New $newShownStartMinimized -Label 'shown handler start-minimized override'

$oldRestartStart = @'
        Write-Log ('Restarting Mugen Deej via launcher: {0}' -f $script:ExecutablePath) 'INFO'
        Start-Process -FilePath $script:ExecutablePath -WorkingDirectory $script:BaseDir
'@
$newRestartStart = @'
        Write-Log ('Restarting Mugen Deej via launcher with one-shot visible window: {0}' -f $script:ExecutablePath) 'INFO'
        $env:MUGEN_DEEJ_SHOW_AFTER_RESTORE = '1'
        try {
            Start-Process -FilePath $script:ExecutablePath -WorkingDirectory $script:BaseDir
        }
        finally {
            Remove-Item Env:\MUGEN_DEEJ_SHOW_AFTER_RESTORE -ErrorAction SilentlyContinue
        }
'@
$text = Replace-ExactOnce -Text $text -Old ($oldRestartStart.TrimEnd()) -New ($newRestartStart.TrimEnd()) -Label 'restart one-shot visibility handoff'

$oldBadge = @'
    $badge.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
    $badge.Text = if ($Kind -eq 'Info') { 'i' } else { '!' }
'@
$newBadge = @'
    $badge.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 18)
    $badge.Text = if ($Kind -eq 'Info') { 'ⓘ' } elseif ($Kind -eq 'Warning') { '⚠' } else { '×' }
'@
$text = Replace-ExactOnce -Text $text -Old ($oldBadge.TrimEnd()) -New ($newBadge.TrimEnd()) -Label 'styled dialog status glyphs'

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($Path, $text, $utf8Bom)

Write-Host 'Applied Mugen Deej 1.0.0-dev4 one-shot visible restore restart and dialog glyph polish patch.'
