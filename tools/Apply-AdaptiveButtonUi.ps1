param(
    [Parameter(Mandatory = $true)][string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Replace-LiteralExactlyOnce {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$OldText,
        [Parameter(Mandatory = $true)][string]$NewText,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $first = $Text.IndexOf($OldText, [System.StringComparison]::Ordinal)
    $last = $Text.LastIndexOf($OldText, [System.StringComparison]::Ordinal)
    if ($first -lt 0 -or $first -ne $last) {
        throw "Adaptive button UI patch '$Label' expected exactly one literal match."
    }

    return $Text.Substring(0, $first) + $NewText + $Text.Substring($first + $OldText.Length)
}

function Replace-RegexBlockExactlyOnceLiteral {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Replacement,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $options = (
        [System.Text.RegularExpressions.RegexOptions]::Multiline -bor
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $regex = New-Object System.Text.RegularExpressions.Regex($Pattern, $options)
    $matches = $regex.Matches($Text)
    if ($matches.Count -ne 1) {
        throw "Adaptive button UI patch '$Label' expected exactly one regex block match, found $($matches.Count)."
    }

    $match = $matches[0]
    return $Text.Substring(0, $match.Index) + $Replacement + $Text.Substring($match.Index + $match.Length)
}

$resolved = (Resolve-Path -LiteralPath $Path).Path
$text = [System.IO.File]::ReadAllText($resolved, [System.Text.Encoding]::UTF8)

# ---------------------------------------------------------------------------
# Main-window live button grid
# ---------------------------------------------------------------------------
# Small controllers keep the existing large tiles. Once the controller reports
# more than eleven buttons, use smaller wrapped tiles instead of a horizontal
# scrollbar. The group grows only by the number of rows actually required, so
# the user can still see exactly which physical button fired without turning
# the whole main window into a giant button list.

$mainButtonUiReplacement = @'
function Get-AdaptiveButtonLayoutMetrics {
    param([int]$Count)

    if ($Count -le 11) {
        return [pscustomobject]@{
            Compact = $false
            TileWidth = 46
            TileHeight = 28
            MarginX = 4
            MarginY = 1
            Columns = 11
            Rows = $(if ($Count -gt 0) { 1 } else { 0 })
            FlowHeight = 34
            GroupHeight = 72
        }
    }

    $tileWidth = 30
    $tileHeight = 24
    $marginX = 2
    $marginY = 1
    $stride = $tileWidth + ($marginX * 2)
    $columns = [Math]::Max(1, [Math]::Floor(606 / $stride))
    $rows = [Math]::Max(1, [int][Math]::Ceiling($Count / [double]$columns))
    $flowHeight = ($rows * ($tileHeight + ($marginY * 2))) + 2
    $groupHeight = 38 + $flowHeight

    return [pscustomobject]@{
        Compact = $true
        TileWidth = $tileWidth
        TileHeight = $tileHeight
        MarginX = $marginX
        MarginY = $marginY
        Columns = $columns
        Rows = $rows
        FlowHeight = $flowHeight
        GroupHeight = $groupHeight
    }
}

function Ensure-MainButtonIndicators {
    $count = if ($script:IsConnected) { [int]$script:DetectedButtonCount } else { 0 }

    if ($null -eq $script:ButtonStateFlow -or $script:ButtonStateFlow.IsDisposed) { return }

    $metrics = Get-AdaptiveButtonLayoutMetrics -Count $count
    $script:ButtonStateFlow.WrapContents = [bool]$metrics.Compact
    $script:ButtonStateFlow.AutoScroll = $false

    if (@($script:MainButtonIndicators).Count -eq $count) { return }

    $script:ButtonStateFlow.SuspendLayout()
    try {
        $script:ButtonStateFlow.Controls.Clear()
        $script:MainButtonIndicators = @()

        for ($i = 0; $i -lt $count; $i++) {
            $indicator = New-Object MugenDeejWindowing.MugenButtonTile
            $indicator.Text = [string]($i + 1)
            $indicator.Size = [System.Drawing.Size]::new(
                [int]$metrics.TileWidth,
                [int]$metrics.TileHeight
            )
            $indicator.Margin = New-Object System.Windows.Forms.Padding(
                [int]$metrics.MarginX,
                [int]$metrics.MarginY,
                [int]$metrics.MarginX,
                [int]$metrics.MarginY
            )
            $indicator.TextAlign = 'MiddleCenter'
            $indicator.BorderStyle = 'None'
            $indicator.Font = New-Object System.Drawing.Font(
                'Segoe UI Semibold',
                $(if ($metrics.Compact) { 8.5 } else { 9 })
            )
            $script:ButtonStateFlow.Controls.Add($indicator)
            $script:MainButtonIndicators += $indicator
        }
    }
    finally {
        $script:ButtonStateFlow.ResumeLayout($true)
    }
}

function Update-MainButtonIndicators {
    Ensure-MainButtonIndicators

    # Adaptive high-button main-grid UI: keep the live physical identification
    # surface visible in every controller size instead of replacing it with a
    # count-only summary.
    if (
        $null -ne $script:ButtonStateFlow -and
        -not $script:ButtonStateFlow.IsDisposed -and
        $null -ne $script:ButtonStateGroup -and
        -not $script:ButtonStateGroup.IsDisposed
    ) {
        $script:ButtonStateFlow.BackColor = $script:ButtonStateGroup.BackColor
    }

    for ($i = 0; $i -lt @($script:MainButtonIndicators).Count; $i++) {
        Set-ButtonIndicatorAppearance `
            -Indicator $script:MainButtonIndicators[$i] `
            -ButtonIndex $i
    }
}

function Set-MainButtonLayout {
    param([Parameter(Mandatory = $true)][bool]$HasButtons)

    if (
        $null -eq $form -or
        $null -eq $startupGroup -or
        $null -eq $advancedToggle -or
        $null -eq $advancedPanel -or
        $null -eq $footer
    ) {
        return
    }

    $buttonCount = if ($HasButtons) { [int]$script:DetectedButtonCount } else { 0 }
    $metrics = Get-AdaptiveButtonLayoutMetrics -Count $buttonCount
    $groupHeight = if ($HasButtons) { [int]$metrics.GroupHeight } else { 72 }
    $offset = if ($HasButtons) { $groupHeight + 12 } else { 0 }

    if ($null -ne $script:ButtonStateGroup) {
        $script:ButtonStateGroup.Location = [System.Drawing.Point]::new(24, 356)
        $script:ButtonStateGroup.Size = [System.Drawing.Size]::new(632, $groupHeight)
    }

    if ($null -ne $script:ButtonStateFlow) {
        $script:ButtonStateFlow.Size = [System.Drawing.Size]::new(
            606,
            [Math]::Max(34, ($groupHeight - 38))
        )
        $script:ButtonStateFlow.WrapContents = [bool]$metrics.Compact
        $script:ButtonStateFlow.AutoScroll = $false
    }

    $settingsButton.Location = [System.Drawing.Point]::new(24, (360 + $offset))
    if ($null -ne $script:ButtonSettingsButton) {
        $script:ButtonSettingsButton.Location = [System.Drawing.Point]::new(272, (360 + $offset))
    }
    if ($null -ne $script:SettingsHintControl) {
        $script:SettingsHintControl.Location = [System.Drawing.Point]::new(272, (358 + $offset))
    }

    $startupGroup.Location = [System.Drawing.Point]::new(24, (414 + $offset))
    $advancedToggle.Location = [System.Drawing.Point]::new(24, (516 + $offset))
    if ($null -ne $script:BackupMenuButton -and -not $script:BackupMenuButton.IsDisposed) {
        $script:BackupMenuButton.Location = [System.Drawing.Point]::new(292, (516 + $offset))
    }
    $advancedPanel.Location = [System.Drawing.Point]::new(0, (550 + $offset))

    $collapsedHeight = 592 + $offset
    $expandedHeight = 860 + $offset

    $form.MinimumSize = [System.Drawing.Size]::new(696, (631 + $offset))
    $form.MaximumSize = [System.Drawing.Size]::new(696, (899 + $offset))
    $form.ClientSize = [System.Drawing.Size]::new(
        680,
        $(if ($advancedPanel.Visible) { $expandedHeight } else { $collapsedHeight })
    )
    $footer.Location = [System.Drawing.Point]::new(24, ($form.ClientSize.Height - 28))
}

function Update-ButtonFeatureUi {
    $hasButtons = ($script:IsConnected -and $script:DetectedButtonCount -gt 0)

    if ($null -ne $script:ButtonSettingsButton -and -not $script:ButtonSettingsButton.IsDisposed) {
        $script:ButtonSettingsButton.Text = Get-ButtonFeatureText -Key 'MainButton'
        $script:ButtonSettingsButton.Visible = $hasButtons
        $script:ButtonSettingsButton.Enabled = $hasButtons
    }

    if ($null -ne $script:SettingsHintControl -and -not $script:SettingsHintControl.IsDisposed) {
        $script:SettingsHintControl.Visible = (-not $hasButtons)
    }

    if ($null -ne $script:ButtonStateGroup -and -not $script:ButtonStateGroup.IsDisposed) {
        $script:ButtonStateGroup.Text = Get-ButtonFeatureText -Key 'ButtonStatus'
        $script:ButtonStateGroup.Visible = $hasButtons
    }

    $script:LastButtonUiVisible = $hasButtons
    Set-MainButtonLayout -HasButtons $hasButtons

    if ($hasButtons) {
        Update-MainButtonIndicators
    }
}

function Set-SliderAudioLevelDirect {
'@

$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Ensure-MainButtonIndicators \{.*?^function Set-SliderAudioLevelDirect \{' `
    -Replacement $mainButtonUiReplacement `
    -Label 'replace main live button strip with adaptive grid'

# ---------------------------------------------------------------------------
# Button Settings for large controllers
# ---------------------------------------------------------------------------
# Up to twelve buttons keep the existing one-row-per-button editor. Larger
# controllers switch to a numbered live grid on the left and one editor for the
# selected physical button on the right. Pressing a real button automatically
# selects that number, which is useful while wiring a 30+ control prototype.

$oldSettingsIndicators = @'
    $settingsIndicators = @()
'@
$newSettingsIndicators = @'
    $settingsIndicators = @()
    $compactButtonMode = ($script:DetectedButtonCount -gt 12)
    $settingsRows = New-Object System.Collections.ArrayList
    $compactState = [pscustomobject]@{
        Selected = 0
        LastButtons = @($script:LatestButtons)
    }
    $buttonSelectorFlow = $null
    $compactHeading = $null
    $compactHint = $null

    $selectCompactButton = {
        param([int]$Index)

        if (-not $compactButtonMode) { return }
        if ($Index -lt 0 -or $Index -ge $settingsRows.Count) { return }

        $compactState.Selected = $Index

        for ($rowIndex = 0; $rowIndex -lt $settingsRows.Count; $rowIndex++) {
            $rowView = $settingsRows[$rowIndex]
            $isSelected = ($rowIndex -eq $Index)
            $rowView.Label.Visible = $isSelected
            $rowView.Indicator.Visible = $isSelected
            $rowView.Combo.Visible = $isSelected
        }

        if ($null -ne $compactHeading) {
            $compactHeading.Text = if ($script:Language -eq 'ru') {
                'Выбрана кнопка ' + ($Index + 1)
            }
            else {
                'Selected button ' + ($Index + 1)
            }
        }
    }

    if ($compactButtonMode) {
        $panel.AutoScroll = $false

        $buttonSelectorFlow = New-Object System.Windows.Forms.FlowLayoutPanel
        $buttonSelectorFlow.Location = [System.Drawing.Point]::new(8, 8)
        $buttonSelectorFlow.Size = [System.Drawing.Size]::new(248, 292)
        $buttonSelectorFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
        $buttonSelectorFlow.WrapContents = $true
        $buttonSelectorFlow.AutoScroll = $true
        $buttonSelectorFlow.BackColor = $panel.BackColor
        $panel.Controls.Add($buttonSelectorFlow)

        $compactHeading = New-Object System.Windows.Forms.Label
        $compactHeading.Text = $(if ($script:Language -eq 'ru') { 'Выбрана кнопка 1' } else { 'Selected button 1' })
        $compactHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
        $compactHeading.Location = [System.Drawing.Point]::new(280, 14)
        $compactHeading.Size = [System.Drawing.Size]::new(370, 27)
        $panel.Controls.Add($compactHeading)

        $compactHint = New-Object System.Windows.Forms.Label
        $compactHint.Text = $(if ($script:Language -eq 'ru') { 'Нажмите физическую кнопку — Mugen сам выберет её в сетке.' } else { 'Press a physical button and Mugen will select it in the grid.' })
        $compactHint.ForeColor = [System.Drawing.Color]::DimGray
        $compactHint.Location = [System.Drawing.Point]::new(280, 42)
        $compactHint.Size = [System.Drawing.Size]::new(370, 48)
        $panel.Controls.Add($compactHint)
    }
'@
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldSettingsIndicators `
    -NewText $newSettingsIndicators `
    -Label 'initialize compact button editor'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText '        $y = 8 + ($i * 46)' `
    -NewText '        $y = if ($compactButtonMode) { 104 } else { 8 + ($i * 46) }' `
    -Label 'compact editor row position'

$oldLabelLayout = @'
        $label.Location = [System.Drawing.Point]::new(8, ($y + 4))
        $label.Size = [System.Drawing.Size]::new(92, 28)
'@
$newLabelLayout = @'
        $label.Location = if ($compactButtonMode) {
            [System.Drawing.Point]::new(280, ($y - 34))
        }
        else {
            [System.Drawing.Point]::new(8, ($y + 4))
        }
        $label.Size = [System.Drawing.Size]::new($(if ($compactButtonMode) { 112 } else { 92 }), 28)
'@
$text = Replace-LiteralExactlyOnce -Text $text -OldText $oldLabelLayout -NewText $newLabelLayout -Label 'compact editor label layout'

$oldIndicatorLayout = @'
        $indicator.Location = [System.Drawing.Point]::new(101, ($y + 3))
        $indicator.Size = [System.Drawing.Size]::new(28, 28)
'@
$newIndicatorLayout = @'
        $indicator.Location = if ($compactButtonMode) {
            [System.Drawing.Point]::new(394, ($y - 35))
        }
        else {
            [System.Drawing.Point]::new(101, ($y + 3))
        }
        $indicator.Size = [System.Drawing.Size]::new(28, 28)
'@
$text = Replace-LiteralExactlyOnce -Text $text -OldText $oldIndicatorLayout -NewText $newIndicatorLayout -Label 'compact editor indicator layout'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText '        $settingsIndicators += $indicator' `
    -NewText '        if (-not $compactButtonMode) { $settingsIndicators += $indicator }' `
    -Label 'compact editor live indicator collection'

$oldComboLayout = @'
        $combo.Location = [System.Drawing.Point]::new(136, $y)
        $combo.Size = [System.Drawing.Size]::new(508, 30)
'@
$newComboLayout = @'
        $combo.Location = if ($compactButtonMode) {
            [System.Drawing.Point]::new(280, $y)
        }
        else {
            [System.Drawing.Point]::new(136, $y)
        }
        $combo.Size = [System.Drawing.Size]::new($(if ($compactButtonMode) { 370 } else { 508 }), 30)
'@
$text = Replace-LiteralExactlyOnce -Text $text -OldText $oldComboLayout -NewText $newComboLayout -Label 'compact editor combo layout'

$oldLoopTail = @'
        $panel.Controls.Add($combo)
    }

    $cancel = New-Object MugenDeejWindowing.MugenButton
'@
$newLoopTail = @'
        $panel.Controls.Add($combo)

        if ($compactButtonMode) {
            $label.Visible = ($i -eq 0)
            $indicator.Visible = ($i -eq 0)
            $combo.Visible = ($i -eq 0)

            [void]$settingsRows.Add([pscustomobject]@{
                Label = $label
                Indicator = $indicator
                Combo = $combo
            })

            $selector = New-Object MugenDeejWindowing.MugenButtonTile
            $selector.Text = [string]($i + 1)
            $selector.Tag = $i
            $selector.Size = [System.Drawing.Size]::new(42, 28)
            $selector.Margin = New-Object System.Windows.Forms.Padding(3, 2, 3, 2)
            $selector.TextAlign = 'MiddleCenter'
            $selector.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
            $selector.Add_Click({
                param($sender, $eventArgs)
                & $selectCompactButton -Index ([int]$sender.Tag)
            })

            $buttonSelectorFlow.Controls.Add($selector)
            $settingsIndicators += $selector
        }
    }

    $cancel = New-Object MugenDeejWindowing.MugenButton
'@
$text = Replace-LiteralExactlyOnce -Text $text -OldText $oldLoopTail -NewText $newLoopTail -Label 'add compact selector tiles'

$oldTimer = @'
    $liveButtonTimer.Add_Tick({
        for (
            $i = 0;
            $i -lt $settingsIndicators.Count;
            $i++
        ) {
            Set-ButtonIndicatorAppearance `
                -Indicator $settingsIndicators[$i] `
                -ButtonIndex $i `
                -DotOnly
        }
    })
'@
$newTimer = @'
    $liveButtonTimer.Add_Tick({
        if ($compactButtonMode) {
            $latest = @($script:LatestButtons)
            $compareCount = [Math]::Min($latest.Count, $settingsRows.Count)

            for ($i = 0; $i -lt $compareCount; $i++) {
                $oldValue = if (@($compactState.LastButtons).Count -gt $i) {
                    [int]$compactState.LastButtons[$i]
                }
                else {
                    1
                }

                if ([int]$latest[$i] -eq 0 -and $oldValue -ne 0) {
                    & $selectCompactButton -Index $i
                    break
                }
            }

            $compactState.LastButtons = @($latest)
            $palette = $script:ThemePalettes[(Get-EffectiveTheme)]

            for ($i = 0; $i -lt $settingsIndicators.Count; $i++) {
                Set-ButtonIndicatorAppearance `
                    -Indicator $settingsIndicators[$i] `
                    -ButtonIndex $i

                if ($i -eq [int]$compactState.Selected) {
                    $settingsIndicators[$i].BorderColor = $palette.Accent
                }
            }

            if (
                $compactState.Selected -ge 0 -and
                $compactState.Selected -lt $settingsRows.Count
            ) {
                Set-ButtonIndicatorAppearance `
                    -Indicator $settingsRows[$compactState.Selected].Indicator `
                    -ButtonIndex ([int]$compactState.Selected) `
                    -DotOnly
            }
        }
        else {
            for ($i = 0; $i -lt $settingsIndicators.Count; $i++) {
                Set-ButtonIndicatorAppearance `
                    -Indicator $settingsIndicators[$i] `
                    -ButtonIndex $i `
                    -DotOnly
            }
        }
    })
'@
$text = Replace-LiteralExactlyOnce -Text $text -OldText $oldTimer -NewText $newTimer -Label 'compact editor live selection timer'

$oldInitialIndicators = @'
    for (
        $i = 0;
        $i -lt $settingsIndicators.Count;
        $i++
    ) {
        Set-ButtonIndicatorAppearance `
            -Indicator $settingsIndicators[$i] `
            -ButtonIndex $i `
            -DotOnly
    }
'@
$newInitialIndicators = @'
    if ($compactButtonMode) {
        $buttonSelectorFlow.BackColor = $panel.BackColor
        $palette = $script:ThemePalettes[(Get-EffectiveTheme)]

        for ($i = 0; $i -lt $settingsIndicators.Count; $i++) {
            Set-ButtonIndicatorAppearance `
                -Indicator $settingsIndicators[$i] `
                -ButtonIndex $i

            if ($i -eq [int]$compactState.Selected) {
                $settingsIndicators[$i].BorderColor = $palette.Accent
            }
        }

        if ($settingsRows.Count -gt 0) {
            Set-ButtonIndicatorAppearance `
                -Indicator $settingsRows[0].Indicator `
                -ButtonIndex 0 `
                -DotOnly
        }
    }
    else {
        for ($i = 0; $i -lt $settingsIndicators.Count; $i++) {
            Set-ButtonIndicatorAppearance `
                -Indicator $settingsIndicators[$i] `
                -ButtonIndex $i `
                -DotOnly
        }
    }
'@
$text = Replace-LiteralExactlyOnce -Text $text -OldText $oldInitialIndicators -NewText $newInitialIndicators -Label 'compact editor initial live state'

# UAC is configuration-dependent. Do not promise a prompt that may be disabled.
$text = $text.Replace(
    "    `$virtualStatus.Text = `$(if (`$script:Language -eq 'ru') { 'Создаёт XInput-геймпад через повышенный helper. UAC появится при включении.' } else { 'Creates an XInput gamepad through the elevated helper. UAC appears when enabled.' })",
    "    `$virtualStatus.Text = `$(if (`$script:Language -eq 'ru') { 'Для создания XInput-геймпада могут потребоваться повышенные права Windows.' } else { 'Creating the XInput gamepad may require Windows administrator elevation.' })"
)

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($resolved, $text, $utf8)
Write-Host "Applied adaptive high-button-count UI to staged runtime: $resolved"
