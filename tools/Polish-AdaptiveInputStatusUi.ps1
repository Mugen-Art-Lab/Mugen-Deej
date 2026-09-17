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
        throw "Adaptive input polish '$Label' expected exactly one regex block match, found $($matches.Count)."
    }

    $match = $matches[0]
    return $Text.Substring(0, $match.Index) + $Replacement + $Text.Substring($match.Index + $match.Length)
}

$resolved = (Resolve-Path -LiteralPath $Path).Path
$text = [System.IO.File]::ReadAllText($resolved, [System.Text.Encoding]::UTF8)

$replacement = @'
function Enable-AdaptiveIndicatorDoubleBuffer {
    param([Parameter(Mandatory = $true)][System.Windows.Forms.Control]$Control)

    try {
        $flags = (
            [System.Reflection.BindingFlags]::Instance -bor
            [System.Reflection.BindingFlags]::NonPublic
        )
        $property = [System.Windows.Forms.Control].GetProperty('DoubleBuffered', $flags)
        if ($null -ne $property) {
            $property.SetValue($Control, $true, $null)
        }
    }
    catch {
        # Double-buffering is a visual optimization only. If reflection is
        # unavailable for any reason, state rendering must still keep working.
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
            $surfaceBack = if ($null -ne $script:AdaptiveStateGroup) {
                $script:AdaptiveStateGroup.BackColor
            }
            else {
                $script:ThemePalettes[(Get-EffectiveTheme)].SurfaceAlt
            }

            $toggleItemHost = New-Object System.Windows.Forms.Panel
            $toggleItemHost.Size = [System.Drawing.Size]::new(112, 28)
            $toggleItemHost.Margin = New-Object System.Windows.Forms.Padding(2, 0, 5, 0)
            $toggleItemHost.BorderStyle = [System.Windows.Forms.BorderStyle]::None
            $toggleItemHost.BackColor = $surfaceBack

            $numberLabel = New-Object System.Windows.Forms.Label
            $numberLabel.Text = [string]($i + 1)
            $numberLabel.Location = [System.Drawing.Point]::new(0, 2)
            $numberLabel.Size = [System.Drawing.Size]::new(20, 24)
            $numberLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $numberLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
            $toggleItemHost.Controls.Add($numberLabel)

            $switchView = New-Object System.Windows.Forms.Panel
            $switchView.Tag = $i
            $switchView.Location = [System.Drawing.Point]::new(22, 1)
            $switchView.Size = [System.Drawing.Size]::new(42, 26)
            $switchView.BackColor = $surfaceBack
            Enable-AdaptiveIndicatorDoubleBuffer -Control $switchView
            $switchView.Add_Paint({
                param($sender, $eventArgs)

                $index = [int]$sender.Tag
                $isOn = (
                    @($script:LatestToggles).Count -gt $index -and
                    [int]$script:LatestToggles[$index] -eq 1
                )
                $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
                $eventArgs.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

                $path = New-Object System.Drawing.Drawing2D.GraphicsPath
                try {
                    $path.AddArc(1, 4, 18, 18, 90, 180)
                    $path.AddArc(22, 4, 18, 18, 270, 180)
                    $path.CloseFigure()

                    $trackColor = if ($isOn) { $palette.Accent } else { $palette.ControlPressed }
                    $trackBrush = New-Object System.Drawing.SolidBrush($trackColor)
                    $borderPen = New-Object System.Drawing.Pen($palette.Border)
                    try {
                        $eventArgs.Graphics.FillPath($trackBrush, $path)
                        $eventArgs.Graphics.DrawPath($borderPen, $path)
                    }
                    finally {
                        $trackBrush.Dispose()
                        $borderPen.Dispose()
                    }

                    $knobX = if ($isOn) { 22 } else { 3 }
                    $knobColor = if ($isOn) { $palette.AccentText } else { $palette.Muted }
                    $knobBrush = New-Object System.Drawing.SolidBrush($knobColor)
                    try {
                        $eventArgs.Graphics.FillEllipse($knobBrush, $knobX, 6, 14, 14)
                    }
                    finally {
                        $knobBrush.Dispose()
                    }
                }
                finally {
                    $path.Dispose()
                }
            })
            $toggleItemHost.Controls.Add($switchView)

            $stateLabel = New-Object System.Windows.Forms.Label
            $stateLabel.Location = [System.Drawing.Point]::new(68, 2)
            $stateLabel.Size = [System.Drawing.Size]::new(42, 24)
            $stateLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
            $stateLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
            $toggleItemHost.Controls.Add($stateLabel)

            $script:ToggleStateFlow.Controls.Add($toggleItemHost)
            $script:MainToggleIndicators += [pscustomobject]@{
                Host = $toggleItemHost
                NumberLabel = $numberLabel
                SwitchView = $switchView
                StateLabel = $stateLabel
                LastOn = $null
                LastTheme = ''
            }
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
            $surfaceBack = if ($null -ne $script:AdaptiveStateGroup) {
                $script:AdaptiveStateGroup.BackColor
            }
            else {
                $script:ThemePalettes[(Get-EffectiveTheme)].SurfaceAlt
            }

            $encoderItemHost = New-Object System.Windows.Forms.Panel
            $encoderItemHost.Size = [System.Drawing.Size]::new(120, 30)
            $encoderItemHost.Margin = New-Object System.Windows.Forms.Padding(2, 0, 8, 0)
            $encoderItemHost.BorderStyle = [System.Windows.Forms.BorderStyle]::None
            $encoderItemHost.BackColor = $surfaceBack

            $numberLabel = New-Object System.Windows.Forms.Label
            $numberLabel.Text = [string]($i + 1)
            $numberLabel.Location = [System.Drawing.Point]::new(0, 3)
            $numberLabel.Size = [System.Drawing.Size]::new(20, 24)
            $numberLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $numberLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
            $encoderItemHost.Controls.Add($numberLabel)

            $knobView = New-Object System.Windows.Forms.Panel
            $knobView.Tag = $i
            $knobView.Location = [System.Drawing.Point]::new(24, 1)
            $knobView.Size = [System.Drawing.Size]::new(28, 28)
            $knobView.BackColor = $surfaceBack
            Enable-AdaptiveIndicatorDoubleBuffer -Control $knobView
            $knobView.Add_Paint({
                param($sender, $eventArgs)

                $index = [int]$sender.Tag
                $position = [int64]0
                $pressed = $false
                if (@($script:LatestEncoders).Count -gt $index) {
                    $currentEncoder = $script:LatestEncoders[$index]
                    if ($null -ne $currentEncoder) {
                        $position = [int64]$currentEncoder.Position
                        $pressed = (
                            [bool]$currentEncoder.HasPush -and
                            [int]$currentEncoder.Push -eq 0
                        )
                    }
                }

                $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
                $eventArgs.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

                # The encoder itself is also its push indicator. Pressing the
                # shaft lights the knob instead of showing a detached "Push"
                # button next to a rotary control.
                $fillColor = if ($pressed) { $palette.Accent } else { $palette.Control }
                $borderColor = if ($pressed) { $palette.Accent } else { $palette.Border }
                $fillBrush = New-Object System.Drawing.SolidBrush($fillColor)
                $borderPen = New-Object System.Drawing.Pen($borderColor, 1)
                try {
                    $eventArgs.Graphics.FillEllipse($fillBrush, 2, 2, 23, 23)
                    $eventArgs.Graphics.DrawEllipse($borderPen, 2, 2, 23, 23)
                }
                finally {
                    $fillBrush.Dispose()
                    $borderPen.Dispose()
                }

                # Endless encoders have no absolute min/max. Rotate the marker
                # by one 15-degree step per detent so movement is visible while
                # the numeric cumulative position remains the source of truth.
                $phase = (($position % 24) + 24) % 24
                $angle = (($phase * 15.0) - 90.0) * [Math]::PI / 180.0
                $centerX = 13.5
                $centerY = 13.5
                $innerRadius = 3.5
                $outerRadius = 9.0
                $x1 = $centerX + ([Math]::Cos($angle) * $innerRadius)
                $y1 = $centerY + ([Math]::Sin($angle) * $innerRadius)
                $x2 = $centerX + ([Math]::Cos($angle) * $outerRadius)
                $y2 = $centerY + ([Math]::Sin($angle) * $outerRadius)

                $markerColor = if ($pressed) { $palette.AccentText } else { $palette.Accent }
                $markerPen = New-Object System.Drawing.Pen($markerColor, 2)
                try {
                    $markerPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
                    $markerPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
                    $eventArgs.Graphics.DrawLine($markerPen, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
                }
                finally {
                    $markerPen.Dispose()
                }
            })
            $encoderItemHost.Controls.Add($knobView)

            $positionLabel = New-Object System.Windows.Forms.Label
            $positionLabel.Location = [System.Drawing.Point]::new(58, 3)
            $positionLabel.Size = [System.Drawing.Size]::new(54, 24)
            $positionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $positionLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
            $encoderItemHost.Controls.Add($positionLabel)

            $script:EncoderStateFlow.Controls.Add($encoderItemHost)
            $script:MainEncoderIndicators += [pscustomobject]@{
                Host = $encoderItemHost
                NumberLabel = $numberLabel
                KnobView = $knobView
                PositionLabel = $positionLabel
                LastPosition = $null
                LastPressed = $null
                LastTheme = ''
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

    $themeKey = [string](Get-EffectiveTheme)
    $palette = $script:ThemePalettes[$themeKey]
    $surfaceBack = if ($null -ne $script:AdaptiveStateGroup -and -not $script:AdaptiveStateGroup.IsDisposed) {
        $script:AdaptiveStateGroup.BackColor
    }
    else {
        $palette.SurfaceAlt
    }

    if ($null -ne $script:AdaptiveStateGroup -and -not $script:AdaptiveStateGroup.IsDisposed) {
        if ($null -ne $script:ToggleStateFlow -and -not $script:ToggleStateFlow.IsDisposed) {
            if ($script:ToggleStateFlow.BackColor.ToArgb() -ne $surfaceBack.ToArgb()) {
                $script:ToggleStateFlow.BackColor = $surfaceBack
            }
        }
        if ($null -ne $script:EncoderStateFlow -and -not $script:EncoderStateFlow.IsDisposed) {
            if ($script:EncoderStateFlow.BackColor.ToArgb() -ne $surfaceBack.ToArgb()) {
                $script:EncoderStateFlow.BackColor = $surfaceBack
            }
        }
    }

    for ($i = 0; $i -lt @($script:MainToggleIndicators).Count; $i++) {
        $view = $script:MainToggleIndicators[$i]
        $on = (
            @($script:LatestToggles).Count -gt $i -and
            [int]$script:LatestToggles[$i] -eq 1
        )

        $surfaceChanged = ($view.Host.BackColor.ToArgb() -ne $surfaceBack.ToArgb())
        if ($surfaceChanged) {
            $view.Host.BackColor = $surfaceBack
            $view.SwitchView.BackColor = $surfaceBack
        }

        if ($view.NumberLabel.ForeColor.ToArgb() -ne $palette.Text.ToArgb()) {
            $view.NumberLabel.ForeColor = $palette.Text
        }

        $stateText = if ($script:Language -eq 'ru') {
            $(if ($on) { 'Вкл' } else { 'Выкл' })
        }
        else {
            $(if ($on) { 'On' } else { 'Off' })
        }
        if ($view.StateLabel.Text -ne $stateText) {
            $view.StateLabel.Text = $stateText
        }

        $stateColor = if ($on) { $palette.Accent } else { $palette.Muted }
        if ($view.StateLabel.ForeColor.ToArgb() -ne $stateColor.ToArgb()) {
            $view.StateLabel.ForeColor = $stateColor
        }

        # Adaptive v3 currently streams every 25 ms. Repainting an unchanged
        # owner-drawn switch on every packet visibly flickers. Repaint only
        # when the state/theme/surface actually changes.
        if (
            $surfaceChanged -or
            $null -eq $view.LastOn -or
            [bool]$view.LastOn -ne $on -or
            [string]$view.LastTheme -ne $themeKey
        ) {
            $view.LastOn = $on
            $view.LastTheme = $themeKey
            $view.SwitchView.Invalidate()
        }
    }

    for ($i = 0; $i -lt @($script:MainEncoderIndicators).Count; $i++) {
        $view = $script:MainEncoderIndicators[$i]
        $encoder = if (@($script:LatestEncoders).Count -gt $i) { $script:LatestEncoders[$i] } else { $null }
        $position = if ($null -ne $encoder) { [int64]$encoder.Position } else { [int64]0 }
        $hasPush = ($null -ne $encoder -and [bool]$encoder.HasPush)
        $pressed = ($hasPush -and [int]$encoder.Push -eq 0)

        $surfaceChanged = ($view.Host.BackColor.ToArgb() -ne $surfaceBack.ToArgb())
        if ($surfaceChanged) {
            $view.Host.BackColor = $surfaceBack
            $view.KnobView.BackColor = $surfaceBack
        }

        if ($view.NumberLabel.ForeColor.ToArgb() -ne $palette.Text.ToArgb()) {
            $view.NumberLabel.ForeColor = $palette.Text
        }

        $positionText = [string]$position
        if ($view.PositionLabel.Text -ne $positionText) {
            $view.PositionLabel.Text = $positionText
        }
        if ($view.PositionLabel.ForeColor.ToArgb() -ne $palette.Text.ToArgb()) {
            $view.PositionLabel.ForeColor = $palette.Text
        }

        # The same packet-rate rule applies to the rotary drawing. Only a
        # detent, push transition, theme change or surface change needs paint.
        # This also prevents screenshots from catching the knob during a
        # needless erase/repaint cycle.
        if (
            $surfaceChanged -or
            $null -eq $view.LastPosition -or
            [int64]$view.LastPosition -ne $position -or
            $null -eq $view.LastPressed -or
            [bool]$view.LastPressed -ne $pressed -or
            [string]$view.LastTheme -ne $themeKey
        ) {
            $view.LastPosition = $position
            $view.LastPressed = $pressed
            $view.LastTheme = $themeKey
            $view.KnobView.Invalidate()
        }
    }
}

function Update-AdaptiveInputFeatureUi {
'@

$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Ensure-MainToggleIndicators \{.*?^function Update-AdaptiveInputFeatureUi \{' `
    -Replacement $replacement `
    -Label 'replace blocky typed-control indicators with flicker-free switch and knob visuals'

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($resolved, $text, $utf8)
Write-Host "Applied flicker-free Adaptive toggle/encoder visual polish to staged runtime: $resolved"
