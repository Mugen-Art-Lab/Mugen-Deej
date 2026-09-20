param(
    [Parameter(Mandatory = $true)][string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

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
        throw "Adaptive topology hardening '$Label' expected exactly one regex block match, found $($matches.Count)."
    }

    $match = $matches[0]
    return $Text.Substring(0, $match.Index) + $Replacement + $Text.Substring($match.Index + $match.Length)
}

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
        throw "Adaptive topology hardening '$Label' expected exactly one literal match."
    }

    return $Text.Substring(0, $first) + $NewText + $Text.Substring($first + $OldText.Length)
}

$resolved = (Resolve-Path -LiteralPath $Path).Path
$text = [System.IO.File]::ReadAllText($resolved, [System.Text.Encoding]::UTF8)

# Adaptive topology hardening: zero-slider v3 is valid and the live UI is
# capability-driven instead of assuming the 5/29/2/1 regression fixture.
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
$script:LastCapabilityMismatchLog = [DateTime]::MinValue
'@ `
    -NewText @'
$script:LastCapabilityMismatchLog = [DateTime]::MinValue
$script:PacketRateWindowStartedAt = [DateTime]::MinValue
$script:PacketRateWindowCount = 0
$script:PacketRateHz = 0.0
$script:AdaptiveOverflowButton = $null
$script:SliderOverflowButton = $null
'@ `
    -Label 'add topology and packet-rate state'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
        if ($adaptiveSliders.Count -lt 1) { return $null }
'@ `
    -NewText @'
        # Adaptive v3 is explicitly versioned; unlike Legacy/Extended it does
        # not require an analog family. A valid v3 controller may consist only
        # of buttons, toggles, or encoders.
        if (
            ($adaptiveSliders.Count + $adaptiveButtons.Count + $adaptiveToggles.Count + $adaptiveEncoders.Count) -lt 1
        ) { return $null }
'@ `
    -Label 'allow Adaptive packets without sliders'

$packetMatch = @'
function Test-ControllerPacketMatchesCapabilities {
    param([Parameter(Mandatory = $true)]$Packet)

    if ($script:ControllerProtocol -eq 'unknown') {
        return $true
    }

    return (
        [string]$Packet.Protocol -eq $script:ControllerProtocol -and
        @($Packet.Sliders).Count -eq $script:DetectedSliderCount -and
        @($Packet.Buttons).Count -eq $script:DetectedButtonCount -and
        @(Get-ControllerPacketArray -Packet $Packet -Name 'Toggles').Count -eq $script:DetectedToggleCount -and
        @(Get-ControllerPacketArray -Packet $Packet -Name 'Encoders').Count -eq $script:DetectedEncoderCount
    )
}

'@
$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Test-ControllerPacketMatchesCapabilities \{.*?^function Close-ControllerPort \{' `
    -Replacement ($packetMatch + 'function Close-ControllerPort {') `
    -Label 'keep zero-slider Adaptive shape validation strict'

$connectedStatus = @'
function Get-ControllerConnectedStatusText {
    param([Parameter(Mandatory = $true)][string]$PortName)

    $sliderCount = [int]$script:DetectedSliderCount
    $buttonCount = [int]$script:DetectedButtonCount
    $toggleCount = [int]$script:DetectedToggleCount
    $encoderCount = [int]$script:DetectedEncoderCount

    # Legacy/Extended always contain at least one slider. Only use the old
    # configured expectation before capability discovery, never to fabricate
    # sliders for an Adaptive controller that intentionally reports zero.
    if ($sliderCount -le 0 -and $script:ControllerProtocol -eq 'unknown') {
        $sliderCount = [int]$script:Config.connection.expectedSliders
    }

    # Main-card text is deliberately compact. The green status dot already
    # communicates "connected", so repeating the full sentence wastes the
    # width needed by self-described 5/28/2/1 (and larger) topologies.
    if ($script:Language -eq 'ru') {
        $parts = New-Object 'System.Collections.Generic.List[string]'
        if ($sliderCount -gt 0) { $parts.Add(('{0} рег.' -f $sliderCount)) }
        if ($buttonCount -gt 0) { $parts.Add(('{0} кнопок' -f $buttonCount)) }
        if ($toggleCount -gt 0) { $parts.Add(('{0} тумбл.' -f $toggleCount)) }
        if ($encoderCount -gt 0) { $parts.Add(('{0} энкодер.' -f $encoderCount)) }
        if ($parts.Count -eq 0) { $parts.Add('нет органов управления') }
        return ('{0} · {1}' -f $PortName, ($parts -join ' · '))
    }

    $parts = New-Object 'System.Collections.Generic.List[string]'
    if ($sliderCount -gt 0) { $parts.Add(('{0} controls' -f $sliderCount)) }
    if ($buttonCount -gt 0) { $parts.Add(('{0} buttons' -f $buttonCount)) }
    if ($toggleCount -gt 0) { $parts.Add(('{0} toggles' -f $toggleCount)) }
    if ($encoderCount -gt 0) { $parts.Add(('{0} encoder' -f $encoderCount)) }
    if ($parts.Count -eq 0) { $parts.Add('no controls') }
    return ('{0} · {1}' -f $PortName, ($parts -join ' · '))
}
'@

$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Get-ControllerConnectedStatusText \{.*?^function Set-DetectedControllerCapabilities \{' `
    -Replacement ($connectedStatus + 'function Set-DetectedControllerCapabilities {') `
    -Label 'make connected status capability-driven'

$helpers = @'
function Ensure-SliderConfigCapacity {
    param([int]$Count)

    if ($Count -le 0) { return }
    $items = @($script:Config.sliders)
    while ($items.Count -lt $Count) {
        $index = $items.Count
        $items += [pscustomobject]@{
            name = (T -Key 'KnobN' -Args @($index + 1))
            defaultName = $true
            targets = @()
            inputDeviceId = ''
            inputDeviceName = ''
        }
    }
    $script:Config.sliders = @($items)
}

function Register-ControllerPacketTiming {
    $now = Get-Date
    $script:LastSerialPacketAt = $now

    if ($script:PacketRateWindowStartedAt -eq [DateTime]::MinValue) {
        $script:PacketRateWindowStartedAt = $now
        $script:PacketRateWindowCount = 1
        return
    }

    $script:PacketRateWindowCount++
    $elapsed = ($now - $script:PacketRateWindowStartedAt).TotalSeconds
    if ($elapsed -ge 1.0) {
        $script:PacketRateHz = [double]$script:PacketRateWindowCount / $elapsed
        $script:PacketRateWindowStartedAt = $now
        $script:PacketRateWindowCount = 0
    }
}

function Get-ControllerProtocolDisplayText {
    switch ([string]$script:ControllerProtocol) {
        'legacy' { return 'Legacy' }
        'extended' { return 'Extended' }
        'adaptive' { return 'Adaptive v3' }
        default { return '—' }
    }
}

function Format-ControllerStateTokenRows {
    param(
        [string[]]$Tokens,
        [int]$PerRow = 8
    )

    if ($null -eq $Tokens -or $Tokens.Count -eq 0) { return @('  —') }
    $rows = @()
    for ($start = 0; $start -lt $Tokens.Count; $start += $PerRow) {
        $end = [Math]::Min($Tokens.Count - 1, $start + $PerRow - 1)
        $slice = @()
        for ($i = $start; $i -le $end; $i++) { $slice += [string]$Tokens[$i] }
        $rows += ('  ' + ($slice -join '    '))
    }
    return @($rows)
}

function Get-FullControllerStateText {
    $ru = ($script:Language -eq 'ru')
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add($(if ($ru) { 'Полное состояние контроллера' } else { 'Full controller state' }))
    $lines.Add(('{0}: {1}    COM: {2}' -f $(if ($ru) { 'Протокол' } else { 'Protocol' }), (Get-ControllerProtocolDisplayText), $(if ([string]::IsNullOrWhiteSpace($script:ConnectedPort)) { '—' } else { $script:ConnectedPort })))
    $lines.Add('')

    $sliderTokens = @()
    for ($i = 0; $i -lt [int]$script:DetectedSliderCount; $i++) {
        $value = if (@($script:LatestLevels).Count -gt $i) {
            ('{0}%' -f [int][Math]::Round([double]$script:LatestLevels[$i] * 100.0))
        }
        else { '—' }
        $sliderTokens += ('{0}:{1}' -f ($i + 1), $value)
    }
    $lines.Add($(if ($ru) { 'Регуляторы' } else { 'Controls' }))
    foreach ($row in @(Format-ControllerStateTokenRows -Tokens $sliderTokens -PerRow 8)) { $lines.Add($row) }
    $lines.Add('')

    $buttonTokens = @()
    for ($i = 0; $i -lt [int]$script:DetectedButtonCount; $i++) {
        $pressed = (@($script:LatestButtons).Count -gt $i -and [int]$script:LatestButtons[$i] -eq 0)
        $buttonTokens += ('{0}:{1}' -f ($i + 1), $(if ($pressed) { '●' } else { '○' }))
    }
    $lines.Add($(if ($ru) { 'Кнопки' } else { 'Buttons' }))
    foreach ($row in @(Format-ControllerStateTokenRows -Tokens $buttonTokens -PerRow 10)) { $lines.Add($row) }
    $lines.Add('')

    $toggleTokens = @()
    for ($i = 0; $i -lt [int]$script:DetectedToggleCount; $i++) {
        $on = (@($script:LatestToggles).Count -gt $i -and [int]$script:LatestToggles[$i] -eq 1)
        $toggleTokens += ('{0}:{1}' -f ($i + 1), $(if ($on) { $(if ($ru) { 'Вкл' } else { 'On' }) } else { $(if ($ru) { 'Выкл' } else { 'Off' }) }))
    }
    $lines.Add($(if ($ru) { 'Тумблеры' } else { 'Toggles' }))
    foreach ($row in @(Format-ControllerStateTokenRows -Tokens $toggleTokens -PerRow 8)) { $lines.Add($row) }
    $lines.Add('')

    $encoderTokens = @()
    for ($i = 0; $i -lt [int]$script:DetectedEncoderCount; $i++) {
        $encoder = if (@($script:LatestEncoders).Count -gt $i) { $script:LatestEncoders[$i] } else { $null }
        $position = if ($null -ne $encoder) { [int64]$encoder.Position } else { 0 }
        $push = ''
        if ($null -ne $encoder -and [bool]$encoder.HasPush) {
            $push = if ([int]$encoder.Push -eq 0) { $(if ($ru) { ' наж.' } else { ' down' }) } else { '' }
        }
        $encoderTokens += ('{0}:{1}{2}' -f ($i + 1), $position, $push)
    }
    $lines.Add($(if ($ru) { 'Энкодеры' } else { 'Encoders' }))
    foreach ($row in @(Format-ControllerStateTokenRows -Tokens $encoderTokens -PerRow 6)) { $lines.Add($row) }

    return ($lines -join "`r`n")
}

function Show-FullControllerStateWindow {
    if (-not $script:IsConnected) { return }

    $stateForm = New-Object System.Windows.Forms.Form
    $stateForm.Text = if ($script:Language -eq 'ru') { 'Состояние контроллера' } else { 'Controller state' }
    $stateForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $stateForm.ClientSize = [System.Drawing.Size]::new(700, 560)
    $stateForm.MinimumSize = [System.Drawing.Size]::new(716, 599)
    $stateForm.Font = $form.Font
    $stateForm.ShowInTaskbar = $false
    Set-FormAppIcon -Form $stateForm

    $stateBox = New-Object System.Windows.Forms.TextBox
    $stateBox.Multiline = $true
    $stateBox.ReadOnly = $true
    $stateBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $stateBox.WordWrap = $false
    $stateBox.Font = New-Object System.Drawing.Font('Consolas', 10)
    $stateBox.Location = [System.Drawing.Point]::new(18, 18)
    $stateBox.Size = [System.Drawing.Size]::new(664, 524)
    $stateBox.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Top -bor
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Left -bor
        [System.Windows.Forms.AnchorStyles]::Right
    )
    $stateForm.Controls.Add($stateBox)

    $refreshState = { $stateBox.Text = Get-FullControllerStateText }
    $stateTimer = New-Object System.Windows.Forms.Timer
    $stateTimer.Interval = 100
    $stateTimer.Add_Tick({ & $refreshState })

    try {
        & $refreshState
        Apply-ThemeToForm -Form $stateForm -ThemeName (Get-EffectiveTheme)
        $stateTimer.Start()
        [void]$stateForm.ShowDialog($form)
    }
    finally {
        $stateTimer.Stop()
        $stateTimer.Dispose()
        if (-not $stateForm.IsDisposed) { $stateForm.Dispose() }
    }
}

function Get-MainInputOverflowCount {
    $buttonMetrics = Get-AdaptiveButtonLayoutMetrics -Count ([int]$script:DetectedButtonCount)
    $typedMetrics = Get-AdaptiveInputStatusLayoutMetrics
    return (
        [int]$buttonMetrics.OverflowCount +
        [int]$typedMetrics.ToggleOverflowCount +
        [int]$typedMetrics.EncoderOverflowCount
    )
}

function Update-SliderCapabilityUi {
    $count = if ($script:IsConnected) {
        [int]$script:DetectedSliderCount
    }
    else {
        [int]$script:Config.connection.expectedSliders
    }

    $visibleCount = [Math]::Min($count, @($script:KnobProgressBars).Count)
    $hasSliders = ($count -gt 0)
    $knobGroup.Visible = $hasSliders
    $settingsButton.Visible = $hasSliders
    $settingsButton.Enabled = $hasSliders

    for ($i = 0; $i -lt @($script:KnobProgressBars).Count; $i++) {
        $visible = ($i -lt $visibleCount)
        $script:KnobNameLabels[$i].Visible = $visible
        $script:KnobProgressBars[$i].Visible = $visible
        $script:KnobPercentLabels[$i].Visible = $visible
    }

    if ($null -eq $script:SliderOverflowButton -or $script:SliderOverflowButton.IsDisposed) {
        $script:SliderOverflowButton = New-Object MugenDeejWindowing.MugenButton
        $script:SliderOverflowButton.Tag = 'MugenSection'
        $script:SliderOverflowButton.Size = [System.Drawing.Size]::new(180, 28)
        $script:SliderOverflowButton.Add_Click({ Show-FullControllerStateWindow })
        $knobGroup.Controls.Add($script:SliderOverflowButton)
    }

    $hidden = [Math]::Max(0, $count - $visibleCount)
    $script:SliderOverflowButton.Visible = ($hidden -gt 0)
    if ($hidden -gt 0) {
        $script:SliderOverflowButton.Text = if ($script:Language -eq 'ru') {
            ('Показать все… (+{0})' -f $hidden)
        }
        else {
            ('Show all… (+{0})' -f $hidden)
        }
        $script:SliderOverflowButton.Location = [System.Drawing.Point]::new(16, (34 + ($visibleCount * 29)))
    }

    if ($hasSliders) {
        $height = 42 + ($visibleCount * 29)
        if ($hidden -gt 0) { $height += 34 }
        $knobGroup.Size = [System.Drawing.Size]::new(632, [Math]::Max(76, $height))
    }

    return $hasSliders
}

'@
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText 'function Get-AdaptiveButtonLayoutMetrics {' `
    -NewText ($helpers + 'function Get-AdaptiveButtonLayoutMetrics {') `
    -Label 'inject topology helpers and full-state viewer'

$buttonMetrics = @'
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
            VisibleCount = [Math]::Max(0, $Count)
            OverflowCount = 0
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
    $actualRows = [Math]::Max(1, [int][Math]::Ceiling($Count / [double]$columns))
    $rows = [Math]::Min(2, $actualRows)
    $visibleCount = [Math]::Min($Count, ($columns * $rows))
    $overflowCount = [Math]::Max(0, $Count - $visibleCount)
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
        VisibleCount = $visibleCount
        OverflowCount = $overflowCount
        FlowHeight = $flowHeight
        GroupHeight = $groupHeight
    }
}

'@
$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Get-AdaptiveButtonLayoutMetrics \{.*?^function Ensure-MainButtonIndicators \{' `
    -Replacement ($buttonMetrics + 'function Ensure-MainButtonIndicators {') `
    -Label 'bound main button summary'

$buttonIndicators = @'
function Ensure-MainButtonIndicators {
    $actualCount = if ($script:IsConnected) { [int]$script:DetectedButtonCount } else { 0 }

    if ($null -eq $script:ButtonStateFlow -or $script:ButtonStateFlow.IsDisposed) { return }

    $metrics = Get-AdaptiveButtonLayoutMetrics -Count $actualCount
    $count = [int]$metrics.VisibleCount
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

'@
$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Ensure-MainButtonIndicators \{.*?^function Update-MainButtonIndicators \{' `
    -Replacement ($buttonIndicators + 'function Update-MainButtonIndicators {') `
    -Label 'render only compact button summary'

$typedMetrics = @'
function Get-AdaptiveInputStatusLayoutMetrics {
    $toggleCount = if ($script:IsConnected) { [int]$script:DetectedToggleCount } else { 0 }
    $encoderCount = if ($script:IsConnected) { [int]$script:DetectedEncoderCount } else { 0 }

    $visibleToggleCount = [Math]::Min($toggleCount, 6)
    $visibleEncoderCount = [Math]::Min($encoderCount, 3)
    $toggleRows = if ($visibleToggleCount -gt 0) { 1 } else { 0 }
    $encoderRows = if ($visibleEncoderCount -gt 0) { 1 } else { 0 }

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
        VisibleToggleCount = $visibleToggleCount
        VisibleEncoderCount = $visibleEncoderCount
        ToggleOverflowCount = [Math]::Max(0, $toggleCount - $visibleToggleCount)
        EncoderOverflowCount = [Math]::Max(0, $encoderCount - $visibleEncoderCount)
        ToggleRows = $toggleRows
        EncoderRows = $encoderRows
        ToggleHeight = $toggleHeight
        EncoderHeight = $encoderHeight
        SectionGap = $sectionGap
        GroupHeight = $groupHeight
    }
}

'@
$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Get-AdaptiveInputStatusLayoutMetrics \{.*?^function Enable-AdaptiveIndicatorDoubleBuffer \{' `
    -Replacement ($typedMetrics + 'function Enable-AdaptiveIndicatorDoubleBuffer {') `
    -Label 'bound typed-control summary'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
function Ensure-MainToggleIndicators {
    $count = if ($script:IsConnected) { [int]$script:DetectedToggleCount } else { 0 }
'@ `
    -NewText @'
function Ensure-MainToggleIndicators {
    $metrics = Get-AdaptiveInputStatusLayoutMetrics
    $count = [int]$metrics.VisibleToggleCount
'@ `
    -Label 'limit main toggle indicators'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
function Ensure-MainEncoderIndicators {
    $count = if ($script:IsConnected) { [int]$script:DetectedEncoderCount } else { 0 }
'@ `
    -NewText @'
function Ensure-MainEncoderIndicators {
    $metrics = Get-AdaptiveInputStatusLayoutMetrics
    $count = [int]$metrics.VisibleEncoderCount
'@ `
    -Label 'limit main encoder indicators'

$featureUi = @'
function Update-AdaptiveInputFeatureUi {
    $metrics = Get-AdaptiveInputStatusLayoutMetrics
    $hasButtons = ($script:IsConnected -and $script:DetectedButtonCount -gt 0)
    $hasAnyInput = ($hasButtons -or [bool]$metrics.HasControls)

    if ($null -ne $script:AdaptiveStateGroup -and -not $script:AdaptiveStateGroup.IsDisposed) {
        $script:AdaptiveStateGroup.Visible = $false
    }

    if ($null -ne $script:ButtonStateGroup -and -not $script:ButtonStateGroup.IsDisposed) {
        $script:ButtonStateGroup.Visible = $hasAnyInput
        if ($hasButtons -and $metrics.HasControls) {
            $script:ButtonStateGroup.Text = if ($script:Language -eq 'ru') {
                'Состояние кнопок и переключателей'
            }
            else {
                'Buttons and controls'
            }
        }
        elseif ($hasButtons) {
            $script:ButtonStateGroup.Text = Get-ButtonFeatureText -Key 'ButtonStatus'
        }
        else {
            $script:ButtonStateGroup.Text = Get-AdaptiveInputUiText -Key 'Group'
        }

        foreach ($control in @(
            $script:ToggleStateLabel,
            $script:ToggleStateFlow,
            $script:EncoderStateLabel,
            $script:EncoderStateFlow
        )) {
            if ($null -ne $control -and -not $control.IsDisposed -and $control.Parent -ne $script:ButtonStateGroup) {
                $script:ButtonStateGroup.Controls.Add($control)
            }
        }

        if ($null -eq $script:AdaptiveOverflowButton -or $script:AdaptiveOverflowButton.IsDisposed) {
            $script:AdaptiveOverflowButton = New-Object MugenDeejWindowing.MugenButton
            $script:AdaptiveOverflowButton.Tag = 'MugenSection'
            $script:AdaptiveOverflowButton.Size = [System.Drawing.Size]::new(180, 28)
            $script:AdaptiveOverflowButton.Add_Click({ Show-FullControllerStateWindow })
            $script:ButtonStateGroup.Controls.Add($script:AdaptiveOverflowButton)
        }
    }

    if ($null -ne $script:ButtonStateFlow -and -not $script:ButtonStateFlow.IsDisposed) {
        $script:ButtonStateFlow.Visible = $hasButtons
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

    $overflow = if ($script:IsConnected) { Get-MainInputOverflowCount } else { 0 }
    if ($null -ne $script:AdaptiveOverflowButton -and -not $script:AdaptiveOverflowButton.IsDisposed) {
        $script:AdaptiveOverflowButton.Visible = ($overflow -gt 0)
        if ($overflow -gt 0) {
            $script:AdaptiveOverflowButton.Text = if ($script:Language -eq 'ru') {
                ('Показать все… (+{0})' -f $overflow)
            }
            else {
                ('Show all… (+{0})' -f $overflow)
            }
        }
    }
}

'@
$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Update-AdaptiveInputFeatureUi \{.*?^function Set-MainButtonLayout \{' `
    -Replacement ($featureUi + 'function Set-MainButtonLayout {') `
    -Label 'add overflow affordance'

$mainLayout = @'
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

    $hasSliders = [bool](Update-SliderCapabilityUi)
    $buttonCount = if ($HasButtons) { [int]$script:DetectedButtonCount } else { 0 }
    $buttonMetrics = Get-AdaptiveButtonLayoutMetrics -Count $buttonCount
    $adaptiveMetrics = Get-AdaptiveInputStatusLayoutMetrics
    $hasAnyInput = ($HasButtons -or [bool]$adaptiveMetrics.HasControls)

    $mainY = 160
    if ($hasSliders) {
        $knobGroup.Location = [System.Drawing.Point]::new(24, $mainY)
        $mainY += $knobGroup.Height + 12
    }

    $cursorY = 29
    if ($null -ne $script:ButtonStateGroup -and -not $script:ButtonStateGroup.IsDisposed) {
        $script:ButtonStateGroup.Location = [System.Drawing.Point]::new(24, $mainY)
    }

    if ($null -ne $script:ButtonStateFlow -and -not $script:ButtonStateFlow.IsDisposed -and $HasButtons) {
        $script:ButtonStateFlow.Location = [System.Drawing.Point]::new(13, $cursorY)
        $script:ButtonStateFlow.Size = [System.Drawing.Size]::new(606, [int]$buttonMetrics.FlowHeight)
        $script:ButtonStateFlow.WrapContents = [bool]$buttonMetrics.Compact
        $script:ButtonStateFlow.AutoScroll = $false
        $cursorY += [int]$buttonMetrics.FlowHeight + 4
    }

    if ($adaptiveMetrics.HasControls) {
        $shareTypedRow = (
            $adaptiveMetrics.VisibleToggleCount -gt 0 -and
            $adaptiveMetrics.VisibleEncoderCount -gt 0 -and
            $adaptiveMetrics.VisibleToggleCount -le 3 -and
            $adaptiveMetrics.VisibleEncoderCount -le 2
        )

        if ($shareTypedRow) {
            $typedY = $cursorY
            $script:ToggleStateLabel.Location = [System.Drawing.Point]::new(13, ($typedY + 3))
            $script:ToggleStateLabel.Size = [System.Drawing.Size]::new(72, 24)
            $script:ToggleStateFlow.Location = [System.Drawing.Point]::new(88, $typedY)
            $script:ToggleStateFlow.Size = [System.Drawing.Size]::new(252, [int]$adaptiveMetrics.ToggleHeight)

            $script:EncoderStateLabel.Location = [System.Drawing.Point]::new(350, ($typedY + 3))
            $script:EncoderStateLabel.Size = [System.Drawing.Size]::new(76, 24)
            $script:EncoderStateFlow.Location = [System.Drawing.Point]::new(428, $typedY)
            $script:EncoderStateFlow.Size = [System.Drawing.Size]::new(191, [int]$adaptiveMetrics.EncoderHeight)
            $cursorY += [Math]::Max([int]$adaptiveMetrics.ToggleHeight, [int]$adaptiveMetrics.EncoderHeight)
        }
        else {
            if ($adaptiveMetrics.VisibleToggleCount -gt 0) {
                $script:ToggleStateLabel.Location = [System.Drawing.Point]::new(13, ($cursorY + 2))
                $script:ToggleStateLabel.Size = [System.Drawing.Size]::new(82, 24)
                $script:ToggleStateFlow.Location = [System.Drawing.Point]::new(100, $cursorY)
                $script:ToggleStateFlow.Size = [System.Drawing.Size]::new(519, [int]$adaptiveMetrics.ToggleHeight)
                $cursorY += [int]$adaptiveMetrics.ToggleHeight
            }

            if ($adaptiveMetrics.VisibleEncoderCount -gt 0) {
                if ($adaptiveMetrics.VisibleToggleCount -gt 0) { $cursorY += [int]$adaptiveMetrics.SectionGap }
                $script:EncoderStateLabel.Location = [System.Drawing.Point]::new(13, ($cursorY + 3))
                $script:EncoderStateLabel.Size = [System.Drawing.Size]::new(82, 24)
                $script:EncoderStateFlow.Location = [System.Drawing.Point]::new(100, $cursorY)
                $script:EncoderStateFlow.Size = [System.Drawing.Size]::new(519, [int]$adaptiveMetrics.EncoderHeight)
                $cursorY += [int]$adaptiveMetrics.EncoderHeight
            }
        }
    }

    $overflow = if ($script:IsConnected) { Get-MainInputOverflowCount } else { 0 }
    if ($overflow -gt 0 -and $null -ne $script:AdaptiveOverflowButton) {
        $script:AdaptiveOverflowButton.Location = [System.Drawing.Point]::new(13, ($cursorY + 3))
        $cursorY += 34
    }

    $inputGroupHeight = if ($hasAnyInput) { [Math]::Max(72, ($cursorY + 8)) } else { 0 }
    if ($null -ne $script:ButtonStateGroup -and -not $script:ButtonStateGroup.IsDisposed -and $hasAnyInput) {
        $script:ButtonStateGroup.Size = [System.Drawing.Size]::new(632, $inputGroupHeight)
        $mainY += $inputGroupHeight + 12
    }

    if ($null -ne $script:AdaptiveStateGroup -and -not $script:AdaptiveStateGroup.IsDisposed) {
        $script:AdaptiveStateGroup.Visible = $false
    }
    $advancedPanel.Visible = $false

    $hasButtonSettings = ($null -ne $script:ButtonSettingsButton -and $script:ButtonSettingsButton.Visible)
    $hasSettingsRow = ($hasSliders -or $hasButtonSettings)
    if ($hasSettingsRow) {
        if ($hasSliders) {
            $settingsButton.Location = [System.Drawing.Point]::new(24, $mainY)
        }
        if ($hasButtonSettings) {
            $script:ButtonSettingsButton.Location = [System.Drawing.Point]::new($(if ($hasSliders) { 272 } else { 24 }), $mainY)
        }
        if ($null -ne $script:SettingsHintControl) {
            $script:SettingsHintControl.Visible = ($hasSliders -and -not $hasButtonSettings)
            $script:SettingsHintControl.Location = [System.Drawing.Point]::new(272, ($mainY - 2))
        }
        $mainY += 54
    }
    elseif ($null -ne $script:SettingsHintControl) {
        $script:SettingsHintControl.Visible = $false
    }

    $startupGroup.Location = [System.Drawing.Point]::new(24, $mainY)
    $mainY += 102
    $advancedToggle.Location = [System.Drawing.Point]::new(24, $mainY)
    if ($null -ne $script:BackupMenuButton -and -not $script:BackupMenuButton.IsDisposed) {
        $script:BackupMenuButton.Location = [System.Drawing.Point]::new(292, $mainY)
    }
    $mainY += 52

    $collapsedHeight = $mainY + 24
    $windowHeight = $collapsedHeight + 39
    $form.MinimumSize = [System.Drawing.Size]::new(696, $windowHeight)
    $form.MaximumSize = [System.Drawing.Size]::new(696, $windowHeight)
    $form.ClientSize = [System.Drawing.Size]::new(680, $collapsedHeight)
    $footer.Location = [System.Drawing.Point]::new(24, ($form.ClientSize.Height - 28))
}

'@
$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Set-MainButtonLayout \{.*?^function Update-ButtonFeatureUi \{' `
    -Replacement ($mainLayout + 'function Update-ButtonFeatureUi {') `
    -Label 'make main layout capability-driven and bounded'

$buttonUi = @'
function Update-ButtonFeatureUi {
    $hasButtons = ($script:IsConnected -and $script:DetectedButtonCount -gt 0)

    if ($null -ne $script:ButtonSettingsButton -and -not $script:ButtonSettingsButton.IsDisposed) {
        $script:ButtonSettingsButton.Text = Get-ButtonFeatureText -Key 'MainButton'
        $script:ButtonSettingsButton.Visible = $hasButtons
        $script:ButtonSettingsButton.Enabled = $hasButtons
    }

    $script:LastButtonUiVisible = $hasButtons
    Update-AdaptiveInputFeatureUi
    Set-MainButtonLayout -HasButtons $hasButtons

    if ($hasButtons) { Update-MainButtonIndicators }
}

'@
$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Update-ButtonFeatureUi \{.*?^function Set-SliderAudioLevelDirect \{' `
    -Replacement ($buttonUi + 'function Set-SliderAudioLevelDirect {') `
    -Label 'remove fixed settings-hint assumptions'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
    $script:DetectedSliderCount = $sliderCount
    $script:DetectedButtonCount = $buttonCount
    $script:DetectedToggleCount = $toggleCount
    $script:DetectedEncoderCount = $encoderCount
'@ `
    -NewText @'
    $script:DetectedSliderCount = $sliderCount
    $script:DetectedButtonCount = $buttonCount
    $script:DetectedToggleCount = $toggleCount
    $script:DetectedEncoderCount = $encoderCount
    Ensure-SliderConfigCapacity -Count $sliderCount
    $script:PacketRateWindowStartedAt = [DateTime]::MinValue
    $script:PacketRateWindowCount = 0
    $script:PacketRateHz = 0.0
'@ `
    -Label 'reset diagnostics and expand slider config on capability discovery'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
                    Update-ButtonStates -Values @($parsed.Buttons)
                    Update-AdaptiveControlStates -Packet $parsed
                    $latestParsed = $parsed
'@ `
    -NewText @'
                    Update-ButtonStates -Values @($parsed.Buttons)
                    Update-AdaptiveControlStates -Packet $parsed
                    Register-ControllerPacketTiming
                    $latestParsed = $parsed
'@ `
    -Label 'measure accepted controller packet rate'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
    $count = [int]$script:Config.connection.expectedSliders
'@ `
    -NewText @'
    $count = if ($script:IsConnected) { [int]$script:DetectedSliderCount } else { [int]$script:Config.connection.expectedSliders }
    Ensure-SliderConfigCapacity -Count $count
'@ `
    -Label 'use detected slider count in slider settings'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
    $advancedToggle.Location = New-Object System.Drawing.Point(25, 540)
'@ `
    -NewText @'
    $advancedY = 150 + ($count * 76) + 10
    $advancedToggle.Location = New-Object System.Drawing.Point(25, $advancedY)
'@ `
    -Label 'position slider advanced section after dynamic rows'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
    $advancedPanel.Location = New-Object System.Drawing.Point(25, 578)
'@ `
    -NewText @'
    $advancedPanel.Location = New-Object System.Drawing.Point(25, ($advancedY + 38))
'@ `
    -Label 'position dynamic slider advanced panel'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
    $cancelButton.Location = New-Object System.Drawing.Point(870, 677)
'@ `
    -NewText @'
    $actionY = $advancedY + 137
    $cancelButton.Location = New-Object System.Drawing.Point(870, $actionY)
'@ `
    -Label 'position dynamic slider cancel button'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
    $saveButton.Location = New-Object System.Drawing.Point(982, 677)
'@ `
    -NewText @'
    $saveButton.Location = New-Object System.Drawing.Point(982, $actionY)
    if ($actionY -gt 650) {
        $settingsForm.AutoScroll = $true
        $settingsForm.AutoScrollMinSize = [System.Drawing.Size]::new(1090, ($actionY + 70))
    }
'@ `
    -Label 'enable scrolling for many slider rows'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
        $script:Config.sliders = @($newSliders)
'@ `
    -NewText @'
        # Keep settings for controls that are absent from the currently
        # connected topology. Universal backups/configs must not be truncated
        # merely because a smaller controller is attached while editing.
        for ($i = $count; $i -lt @($script:Config.sliders).Count; $i++) {
            $newSliders += $script:Config.sliders[$i]
        }
        $script:Config.sliders = @($newSliders)
'@ `
    -Label 'preserve dormant slider mappings'

$diagnostics = @'
function Get-ControllerDiagnosticsSnapshot {
    $connected = [bool]$script:IsConnected
    $baud = '—'
    if ($connected -and $null -ne $script:Serial) {
        try { $baud = [string][int]$script:Serial.BaudRate } catch { }
    }

    $age = '—'
    if ($connected -and $script:LastSerialPacketAt -ne [DateTime]::MinValue) {
        $ageMs = [Math]::Max(0, [int][Math]::Round(((Get-Date) - $script:LastSerialPacketAt).TotalMilliseconds))
        $age = ('{0} ms' -f $ageMs)
    }

    $rate = if ($connected -and [double]$script:PacketRateHz -gt 0.0) {
        ('~{0:N1} Hz' -f [double]$script:PacketRateHz)
    }
    else { '—' }

    $mode = if ([string]$script:Config.connection.mode -eq 'manual') {
        $(if ($script:Language -eq 'ru') { 'Ручной' } else { 'Manual' })
    }
    else {
        $(if ($script:Language -eq 'ru') { 'Автоматический' } else { 'Automatic' })
    }

    return [pscustomobject]@{
        Port = $(if ($connected -and -not [string]::IsNullOrWhiteSpace($script:ConnectedPort)) { $script:ConnectedPort } else { '—' })
        Protocol = $(if ($connected) { Get-ControllerProtocolDisplayText } else { '—' })
        Baud = $baud
        Mode = $mode
        Sliders = $(if ($connected) { [string][int]$script:DetectedSliderCount } else { '—' })
        Buttons = $(if ($connected) { [string][int]$script:DetectedButtonCount } else { '—' })
        Toggles = $(if ($connected) { [string][int]$script:DetectedToggleCount } else { '—' })
        Encoders = $(if ($connected) { [string][int]$script:DetectedEncoderCount } else { '—' })
        PacketAge = $age
        PacketRate = $rate
    }
}

function Show-ConnectionDiagnosticsWindow {
    if ($null -eq $form -or $form.IsDisposed) { return }

    Refresh-PortList
    Update-ConnectionControls
    Update-DriverStatus

    $dialog = New-Object System.Windows.Forms.Form
    $title = [string](T -Key 'DiagnosticsClosed')
    $dialog.Text = ($title -replace '\s*[▼▲]\s*$', '')
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.ClientSize = [System.Drawing.Size]::new(680, 478)
    $dialog.MinimumSize = [System.Drawing.Size]::new(696, 517)
    $dialog.MaximumSize = [System.Drawing.Size]::new(696, 517)
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.Font = $form.Font
    Set-FormAppIcon -Form $dialog

    $infoGroup = New-Object MugenDeejWindowing.MugenGroupBox
    $infoGroup.Text = if ($script:Language -eq 'ru') { 'Сведения о контроллере' } else { 'Controller information' }
    $infoGroup.Location = [System.Drawing.Point]::new(24, 10)
    $infoGroup.Size = [System.Drawing.Size]::new(632, 164)
    $dialog.Controls.Add($infoGroup)

    $labels = @{}
    $rows = @(
        @('Port', $(if ($script:Language -eq 'ru') { 'Порт' } else { 'Port' }), 18, 31),
        @('Protocol', $(if ($script:Language -eq 'ru') { 'Протокол' } else { 'Protocol' }), 18, 58),
        @('Baud', $(if ($script:Language -eq 'ru') { 'Скорость' } else { 'Baud rate' }), 18, 85),
        @('Mode', $(if ($script:Language -eq 'ru') { 'Подключение' } else { 'Connection mode' }), 18, 112),
        @('Sliders', $(if ($script:Language -eq 'ru') { 'Регуляторы' } else { 'Controls' }), 322, 31),
        @('Buttons', $(if ($script:Language -eq 'ru') { 'Кнопки' } else { 'Buttons' }), 322, 58),
        @('Toggles', $(if ($script:Language -eq 'ru') { 'Тумблеры' } else { 'Toggles' }), 322, 85),
        @('Encoders', $(if ($script:Language -eq 'ru') { 'Энкодеры' } else { 'Encoders' }), 322, 112)
    )

    foreach ($row in $rows) {
        $key = [string]$row[0]
        $caption = New-Object System.Windows.Forms.Label
        $caption.Text = [string]$row[1]
        $caption.Location = [System.Drawing.Point]::new([int]$row[2], [int]$row[3])
        $caption.Size = [System.Drawing.Size]::new(118, 22)
        $caption.ForeColor = [System.Drawing.Color]::DimGray
        $infoGroup.Controls.Add($caption)

        $value = New-Object System.Windows.Forms.Label
        $value.Location = [System.Drawing.Point]::new(([int]$row[2] + 122), [int]$row[3])
        $value.Size = [System.Drawing.Size]::new(165, 22)
        $value.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
        $infoGroup.Controls.Add($value)
        $labels[$key] = $value
    }

    $freshCaption = New-Object System.Windows.Forms.Label
    $freshCaption.Text = if ($script:Language -eq 'ru') { 'Последний пакет / частота' } else { 'Latest packet / update rate' }
    $freshCaption.Location = [System.Drawing.Point]::new(18, 136)
    $freshCaption.Size = [System.Drawing.Size]::new(185, 22)
    $infoGroup.Controls.Add($freshCaption)

    $freshValue = New-Object System.Windows.Forms.Label
    $freshValue.Location = [System.Drawing.Point]::new(205, 136)
    $freshValue.Size = [System.Drawing.Size]::new(405, 22)
    $freshValue.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $freshValue.ForeColor = [System.Drawing.Color]::DimGray
    $infoGroup.Controls.Add($freshValue)

    $connectionGroup.Location = [System.Drawing.Point]::new(24, 182)
    $driverGroup.Location = [System.Drawing.Point]::new(24, 340)
    $dialog.Controls.Add($connectionGroup)
    $dialog.Controls.Add($driverGroup)

    $refreshInfo = {
        $snapshot = Get-ControllerDiagnosticsSnapshot
        foreach ($key in @('Port','Protocol','Baud','Mode','Sliders','Buttons','Toggles','Encoders')) {
            $labels[$key].Text = [string]$snapshot.$key
        }
        $freshValue.Text = if ($script:Language -eq 'ru') {
            ('Пакет: {0} · {1}' -f $snapshot.PacketAge, $snapshot.PacketRate)
        }
        else {
            ('Packet: {0} · {1}' -f $snapshot.PacketAge, $snapshot.PacketRate)
        }
    }

    $diagTimer = New-Object System.Windows.Forms.Timer
    $diagTimer.Interval = 250
    $diagTimer.Add_Tick({ & $refreshInfo })

    try {
        & $refreshInfo
        Apply-ThemeToForm -Form $dialog -ThemeName (Get-EffectiveTheme)
        $diagTimer.Start()
        [void]$dialog.ShowDialog($form)
    }
    finally {
        $diagTimer.Stop()
        $diagTimer.Dispose()
        if (-not $connectionGroup.IsDisposed) {
            $advancedPanel.Controls.Add($connectionGroup)
            $connectionGroup.Location = [System.Drawing.Point]::new(24, 0)
        }
        if (-not $driverGroup.IsDisposed) {
            $advancedPanel.Controls.Add($driverGroup)
            $driverGroup.Location = [System.Drawing.Point]::new(24, 158)
        }
        if (-not $dialog.IsDisposed) { $dialog.Dispose() }
    }
}

'@
$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Show-ConnectionDiagnosticsWindow \{.*?^function Set-AdvancedExpanded \{' `
    -Replacement ($diagnostics + 'function Set-AdvancedExpanded {') `
    -Label 'expand diagnostics dialog with live controller topology'

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($resolved, $text, $utf8)

Write-Host 'Adaptive topology hardening applied: zero-slider parsing, bounded summaries, live diagnostics and dormant slider preservation.'
