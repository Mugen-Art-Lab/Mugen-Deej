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
        throw "Adaptive input status UI patch '$Label' expected exactly one literal match."
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
        throw "Adaptive input status UI patch '$Label' expected exactly one regex block match, found $($matches.Count)."
    }

    $match = $matches[0]
    return $Text.Substring(0, $match.Index) + $Replacement + $Text.Substring($match.Index + $match.Length)
}

$resolved = (Resolve-Path -LiteralPath $Path).Path
$text = [System.IO.File]::ReadAllText($resolved, [System.Text.Encoding]::UTF8)

# ---------------------------------------------------------------------------
# Main-window live state for first-class Adaptive controls
# ---------------------------------------------------------------------------
# Keep toggles and rotary encoders visibly distinct from momentary buttons.
# Toggle tiles show logical ON/OFF. Each encoder gets a live cumulative-position
# tile plus a separate Push/Кнопка tile that lights only while the encoder's
# physical push switch is held. This avoids awkward phrases such as
# "нажатие отпущено" while preserving the actual ePOSITION:PUSH semantics.

$adaptiveStatusFunctions = @'
function Get-AdaptiveInputUiText {
    param([Parameter(Mandatory = $true)][string]$Key)

    $ru = ($script:Language -eq 'ru')
    switch ($Key) {
        'Group' {
            if ($ru) { return 'Тумблеры и энкодеры' }
            else { return 'Toggles and encoders' }
        }
        'Toggles' {
            if ($ru) { return 'Тумблеры' }
            else { return 'Toggles' }
        }
        'Encoders' {
            if ($ru) { return 'Энкодеры' }
            else { return 'Encoders' }
        }
        'Push' {
            if ($ru) { return 'Кнопка' }
            else { return 'Push' }
        }
        'On' {
            if ($ru) { return 'ВКЛ' }
            else { return 'ON' }
        }
        'Off' {
            if ($ru) { return 'ВЫКЛ' }
            else { return 'OFF' }
        }
        default { return $Key }
    }
}

function Get-AdaptiveInputStatusLayoutMetrics {
    $toggleCount = if ($script:IsConnected) { [int]$script:DetectedToggleCount } else { 0 }
    $encoderCount = if ($script:IsConnected) { [int]$script:DetectedEncoderCount } else { 0 }

    $toggleRows = if ($toggleCount -gt 0) {
        [Math]::Max(1, [int][Math]::Ceiling($toggleCount / 6.0))
    }
    else { 0 }

    $encoderRows = if ($encoderCount -gt 0) {
        [Math]::Max(1, [int][Math]::Ceiling($encoderCount / 2.0))
    }
    else { 0 }

    $toggleHeight = $toggleRows * 30
    $encoderHeight = $encoderRows * 32
    $sectionGap = if ($toggleCount -gt 0 -and $encoderCount -gt 0) { 4 } else { 0 }
    $hasControls = ($toggleCount -gt 0 -or $encoderCount -gt 0)
    $groupHeight = if ($hasControls) {
        42 + $toggleHeight + $encoderHeight + $sectionGap
    }
    else { 0 }

    return [pscustomobject]@{
        HasControls = $hasControls
        ToggleCount = $toggleCount
        EncoderCount = $encoderCount
        ToggleRows = $toggleRows
        EncoderRows = $encoderRows
        ToggleHeight = $toggleHeight
        EncoderHeight = $encoderHeight
        SectionGap = $sectionGap
        GroupHeight = $groupHeight
    }
}

function Ensure-MainToggleIndicators {
    $count = if ($script:IsConnected) { [int]$script:DetectedToggleCount } else { 0 }
    if ($null -eq $script:ToggleStateFlow -or $script:ToggleStateFlow.IsDisposed) { return }
    if (@($script:MainToggleIndicators).Count -eq $count) { return }

    $script:ToggleStateFlow.SuspendLayout()
    try {
        $script:ToggleStateFlow.Controls.Clear()
        $script:MainToggleIndicators = @()

        for ($i = 0; $i -lt $count; $i++) {
            $tile = New-Object MugenDeejWindowing.MugenButtonTile
            $tile.Size = [System.Drawing.Size]::new(78, 26)
            $tile.Margin = New-Object System.Windows.Forms.Padding(2, 1, 2, 1)
            $tile.TextAlign = 'MiddleCenter'
            $tile.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
            $script:ToggleStateFlow.Controls.Add($tile)
            $script:MainToggleIndicators += $tile
        }
    }
    finally {
        $script:ToggleStateFlow.ResumeLayout($true)
    }
}

function Ensure-MainEncoderIndicators {
    $count = if ($script:IsConnected) { [int]$script:DetectedEncoderCount } else { 0 }
    if ($null -eq $script:EncoderStateFlow -or $script:EncoderStateFlow.IsDisposed) { return }
    if (@($script:MainEncoderIndicators).Count -eq $count) { return }

    $script:EncoderStateFlow.SuspendLayout()
    try {
        $script:EncoderStateFlow.Controls.Clear()
        $script:MainEncoderIndicators = @()

        for ($i = 0; $i -lt $count; $i++) {
            $host = New-Object System.Windows.Forms.Panel
            $host.Size = [System.Drawing.Size]::new(246, 28)
            $host.Margin = New-Object System.Windows.Forms.Padding(2, 1, 2, 1)
            $host.BorderStyle = [System.Windows.Forms.BorderStyle]::None

            $positionTile = New-Object MugenDeejWindowing.MugenButtonTile
            $positionTile.Location = [System.Drawing.Point]::new(0, 1)
            $positionTile.Size = [System.Drawing.Size]::new(154, 26)
            $positionTile.TextAlign = 'MiddleCenter'
            $positionTile.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
            $host.Controls.Add($positionTile)

            $pushTile = New-Object MugenDeejWindowing.MugenButtonTile
            $pushTile.Location = [System.Drawing.Point]::new(160, 1)
            $pushTile.Size = [System.Drawing.Size]::new(84, 26)
            $pushTile.TextAlign = 'MiddleCenter'
            $pushTile.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
            $host.Controls.Add($pushTile)

            $script:EncoderStateFlow.Controls.Add($host)
            $script:MainEncoderIndicators += [pscustomobject]@{
                Host = $host
                PositionTile = $positionTile
                PushTile = $pushTile
            }
        }
    }
    finally {
        $script:EncoderStateFlow.ResumeLayout($true)
    }
}

function Update-AdaptiveInputIndicators {
    Ensure-MainToggleIndicators
    Ensure-MainEncoderIndicators

    $palette = $script:ThemePalettes[(Get-EffectiveTheme)]

    if ($null -ne $script:AdaptiveStateGroup -and -not $script:AdaptiveStateGroup.IsDisposed) {
        if ($null -ne $script:ToggleStateFlow -and -not $script:ToggleStateFlow.IsDisposed) {
            $script:ToggleStateFlow.BackColor = $script:AdaptiveStateGroup.BackColor
        }
        if ($null -ne $script:EncoderStateFlow -and -not $script:EncoderStateFlow.IsDisposed) {
            $script:EncoderStateFlow.BackColor = $script:AdaptiveStateGroup.BackColor
        }
    }

    for ($i = 0; $i -lt @($script:MainToggleIndicators).Count; $i++) {
        $tile = $script:MainToggleIndicators[$i]
        $on = (
            @($script:LatestToggles).Count -gt $i -and
            [int]$script:LatestToggles[$i] -eq 1
        )
        $tile.Text = ('{0} · {1}' -f ($i + 1), (Get-AdaptiveInputUiText -Key $(if ($on) { 'On' } else { 'Off' })))
        $tile.BorderColor = $palette.Border
        $tile.BackColor = if ($on) { $palette.Accent } else { $palette.Control }
        $tile.ForeColor = if ($on) { $palette.AccentText } else { $palette.Text }
    }

    for ($i = 0; $i -lt @($script:MainEncoderIndicators).Count; $i++) {
        $view = $script:MainEncoderIndicators[$i]
        $encoder = if (@($script:LatestEncoders).Count -gt $i) { $script:LatestEncoders[$i] } else { $null }
        $position = if ($null -ne $encoder) { [int64]$encoder.Position } else { [int64]0 }
        $hasPush = ($null -ne $encoder -and [bool]$encoder.HasPush)
        $pressed = ($hasPush -and [int]$encoder.Push -eq 0)

        $view.Host.BackColor = if ($null -ne $script:AdaptiveStateGroup) {
            $script:AdaptiveStateGroup.BackColor
        }
        else {
            $palette.SurfaceAlt
        }

        $view.PositionTile.Text = ('{0}   ↺ {1} ↻' -f ($i + 1), $position)
        $view.PositionTile.BorderColor = $palette.Border
        $view.PositionTile.BackColor = $palette.Control
        $view.PositionTile.ForeColor = $palette.Text

        $view.PushTile.Text = Get-AdaptiveInputUiText -Key 'Push'
        $view.PushTile.Visible = $hasPush
        $view.PushTile.BorderColor = $palette.Border
        $view.PushTile.BackColor = if ($pressed) { $palette.Accent } else { $palette.Control }
        $view.PushTile.ForeColor = if ($pressed) { $palette.AccentText } else { $palette.Text }

        if ($hasPush) {
            $view.PositionTile.Size = [System.Drawing.Size]::new(154, 26)
        }
        else {
            $view.PositionTile.Size = [System.Drawing.Size]::new(244, 26)
        }
    }
}

function Update-AdaptiveInputFeatureUi {
    $metrics = Get-AdaptiveInputStatusLayoutMetrics

    if ($null -ne $script:AdaptiveStateGroup -and -not $script:AdaptiveStateGroup.IsDisposed) {
        $script:AdaptiveStateGroup.Text = Get-AdaptiveInputUiText -Key 'Group'
        $script:AdaptiveStateGroup.Visible = [bool]$metrics.HasControls
    }

    if ($null -ne $script:ToggleStateLabel -and -not $script:ToggleStateLabel.IsDisposed) {
        $script:ToggleStateLabel.Text = Get-AdaptiveInputUiText -Key 'Toggles'
        $script:ToggleStateLabel.Visible = ($metrics.ToggleCount -gt 0)
    }
    if ($null -ne $script:ToggleStateFlow -and -not $script:ToggleStateFlow.IsDisposed) {
        $script:ToggleStateFlow.Visible = ($metrics.ToggleCount -gt 0)
    }

    if ($null -ne $script:EncoderStateLabel -and -not $script:EncoderStateLabel.IsDisposed) {
        $script:EncoderStateLabel.Text = Get-AdaptiveInputUiText -Key 'Encoders'
        $script:EncoderStateLabel.Visible = ($metrics.EncoderCount -gt 0)
    }
    if ($null -ne $script:EncoderStateFlow -and -not $script:EncoderStateFlow.IsDisposed) {
        $script:EncoderStateFlow.Visible = ($metrics.EncoderCount -gt 0)
    }

    if ($metrics.HasControls) {
        Update-AdaptiveInputIndicators
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
    $buttonMetrics = Get-AdaptiveButtonLayoutMetrics -Count $buttonCount
    $buttonGroupHeight = if ($HasButtons) { [int]$buttonMetrics.GroupHeight } else { 72 }
    $buttonOffset = if ($HasButtons) { $buttonGroupHeight + 12 } else { 0 }

    $adaptiveMetrics = Get-AdaptiveInputStatusLayoutMetrics
    $adaptiveOffset = if ($adaptiveMetrics.HasControls) { [int]$adaptiveMetrics.GroupHeight + 12 } else { 0 }
    $offset = $buttonOffset + $adaptiveOffset

    if ($null -ne $script:ButtonStateGroup) {
        $script:ButtonStateGroup.Location = [System.Drawing.Point]::new(24, 356)
        $script:ButtonStateGroup.Size = [System.Drawing.Size]::new(632, $buttonGroupHeight)
    }

    if ($null -ne $script:ButtonStateFlow) {
        $script:ButtonStateFlow.Size = [System.Drawing.Size]::new(
            606,
            [Math]::Max(34, ($buttonGroupHeight - 38))
        )
        $script:ButtonStateFlow.WrapContents = [bool]$buttonMetrics.Compact
        $script:ButtonStateFlow.AutoScroll = $false
    }

    if ($null -ne $script:AdaptiveStateGroup -and -not $script:AdaptiveStateGroup.IsDisposed) {
        $adaptiveTop = 356 + $buttonOffset
        $script:AdaptiveStateGroup.Location = [System.Drawing.Point]::new(24, $adaptiveTop)
        if ($adaptiveMetrics.HasControls) {
            $script:AdaptiveStateGroup.Size = [System.Drawing.Size]::new(632, [int]$adaptiveMetrics.GroupHeight)
        }

        $cursorY = 29
        if ($adaptiveMetrics.ToggleCount -gt 0) {
            $script:ToggleStateLabel.Location = [System.Drawing.Point]::new(13, ($cursorY + 2))
            $script:ToggleStateFlow.Location = [System.Drawing.Point]::new(100, $cursorY)
            $script:ToggleStateFlow.Size = [System.Drawing.Size]::new(519, [int]$adaptiveMetrics.ToggleHeight)
            $cursorY += [int]$adaptiveMetrics.ToggleHeight
        }

        if ($adaptiveMetrics.EncoderCount -gt 0) {
            if ($adaptiveMetrics.ToggleCount -gt 0) {
                $cursorY += [int]$adaptiveMetrics.SectionGap
            }
            $script:EncoderStateLabel.Location = [System.Drawing.Point]::new(13, ($cursorY + 3))
            $script:EncoderStateFlow.Location = [System.Drawing.Point]::new(100, $cursorY)
            $script:EncoderStateFlow.Size = [System.Drawing.Size]::new(519, [int]$adaptiveMetrics.EncoderHeight)
        }
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
    Update-AdaptiveInputFeatureUi

    if ($hasButtons) {
        Update-MainButtonIndicators
    }
}

function Set-SliderAudioLevelDirect {
'@

$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Set-MainButtonLayout \{.*?^function Set-SliderAudioLevelDirect \{' `
    -Replacement $adaptiveStatusFunctions `
    -Label 'main adaptive typed-control status functions and layout'

# ---------------------------------------------------------------------------
# Main-window controls
# ---------------------------------------------------------------------------

$oldMainUiAnchor = @'
$script:ButtonStateFlow = $buttonStateFlow

$settingsButton = New-Object MugenDeejWindowing.MugenButton
'@

$newMainUiAnchor = @'
$script:ButtonStateFlow = $buttonStateFlow

$adaptiveStateGroup = New-Object MugenDeejWindowing.MugenGroupBox
$adaptiveStateGroup.Text = Get-AdaptiveInputUiText -Key 'Group'
$adaptiveStateGroup.Location = [System.Drawing.Point]::new(24, 356)
$adaptiveStateGroup.Size = [System.Drawing.Size]::new(632, 108)
$adaptiveStateGroup.Visible = $false
$form.Controls.Add($adaptiveStateGroup)
$script:AdaptiveStateGroup = $adaptiveStateGroup

$toggleStateLabel = New-Object System.Windows.Forms.Label
$toggleStateLabel.Text = Get-AdaptiveInputUiText -Key 'Toggles'
$toggleStateLabel.Location = [System.Drawing.Point]::new(13, 31)
$toggleStateLabel.Size = [System.Drawing.Size]::new(82, 24)
$toggleStateLabel.TextAlign = 'MiddleLeft'
$toggleStateLabel.Visible = $false
$adaptiveStateGroup.Controls.Add($toggleStateLabel)
$script:ToggleStateLabel = $toggleStateLabel

$toggleStateFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$toggleStateFlow.Location = [System.Drawing.Point]::new(100, 29)
$toggleStateFlow.Size = [System.Drawing.Size]::new(519, 30)
$toggleStateFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$toggleStateFlow.WrapContents = $true
$toggleStateFlow.AutoScroll = $false
$toggleStateFlow.BackColor = $adaptiveStateGroup.BackColor
$toggleStateFlow.Visible = $false
$adaptiveStateGroup.Controls.Add($toggleStateFlow)
$script:ToggleStateFlow = $toggleStateFlow

$encoderStateLabel = New-Object System.Windows.Forms.Label
$encoderStateLabel.Text = Get-AdaptiveInputUiText -Key 'Encoders'
$encoderStateLabel.Location = [System.Drawing.Point]::new(13, 65)
$encoderStateLabel.Size = [System.Drawing.Size]::new(82, 24)
$encoderStateLabel.TextAlign = 'MiddleLeft'
$encoderStateLabel.Visible = $false
$adaptiveStateGroup.Controls.Add($encoderStateLabel)
$script:EncoderStateLabel = $encoderStateLabel

$encoderStateFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$encoderStateFlow.Location = [System.Drawing.Point]::new(100, 63)
$encoderStateFlow.Size = [System.Drawing.Size]::new(519, 32)
$encoderStateFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$encoderStateFlow.WrapContents = $true
$encoderStateFlow.AutoScroll = $false
$encoderStateFlow.BackColor = $adaptiveStateGroup.BackColor
$encoderStateFlow.Visible = $false
$adaptiveStateGroup.Controls.Add($encoderStateFlow)
$script:EncoderStateFlow = $encoderStateFlow

$script:MainToggleIndicators = @()
$script:MainEncoderIndicators = @()

$settingsButton = New-Object MugenDeejWindowing.MugenButton
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldMainUiAnchor `
    -NewText $newMainUiAnchor `
    -Label 'create main typed-control status card'

# Refresh typed indicators on the same UI cadence as sliders/buttons.
$oldReadoutTail = @'
    Update-MainButtonIndicators
}

function Set-AdvancedExpanded {
'@
$newReadoutTail = @'
    Update-MainButtonIndicators
    Update-AdaptiveInputIndicators
}

function Set-AdvancedExpanded {
'@
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldReadoutTail `
    -NewText $newReadoutTail `
    -Label 'refresh typed status from main readout'

# Reuse the single dynamic layout function when diagnostics are expanded or
# collapsed. This also fixes the older high-button-count path that still used
# a hard-coded 84-pixel offset here.
$advancedExpandedReplacement = @'
function Set-AdvancedExpanded {
    param(
        [bool]$Expanded,
        [bool]$Persist = $true
    )

    $advancedPanel.Visible = $Expanded
    $advancedToggle.Text = if ($Expanded) {
        T -Key 'DiagnosticsOpen'
    }
    else {
        T -Key 'DiagnosticsClosed'
    }

    $hasButtons = ($script:IsConnected -and $script:DetectedButtonCount -gt 0)
    Set-MainButtonLayout -HasButtons $hasButtons

    if ($Persist) {
        $script:Config.app.advancedExpanded = $Expanded
        Save-Config -Config $script:Config
    }
}

if ([string]$script:Config.connection.mode -eq 'manual') {
'@
$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern "(?ms)^function Set-AdvancedExpanded \{.*?^if \(\[string\]\`$script:Config\.connection\.mode -eq 'manual'\) \{" `
    -Replacement $advancedExpandedReplacement `
    -Label 'dynamic diagnostics layout for typed controls'

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($resolved, $text, $utf8)
Write-Host "Applied Adaptive toggle/encoder live status UI to staged runtime: $resolved"
