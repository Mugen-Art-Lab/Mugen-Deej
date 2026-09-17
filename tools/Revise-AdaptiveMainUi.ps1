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
        throw "Adaptive main UI revision '$Label' expected exactly one regex block match, found $($matches.Count)."
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
        throw "Adaptive main UI revision '$Label' expected exactly one literal match."
    }

    return $Text.Substring(0, $first) + $NewText + $Text.Substring($first + $OldText.Length)
}

$resolved = (Resolve-Path -LiteralPath $Path).Path
$text = [System.IO.File]::ReadAllText($resolved, [System.Text.Encoding]::UTF8)

# ---------------------------------------------------------------------------
# Main-window layout
# ---------------------------------------------------------------------------
# Adaptive added enough first-class input types that stacking a second status
# card underneath the physical-button card made the main window unnecessarily
# tall. Keep all physical input state in one card. For the common 2-toggle /
# 1-encoder fixture the typed controls share one compact row under the wrapped
# button grid; larger controllers automatically fall back to stacked rows.

$combinedLayout = @'
function Update-AdaptiveInputFeatureUi {
    $metrics = Get-AdaptiveInputStatusLayoutMetrics
    $hasButtons = ($script:IsConnected -and $script:DetectedButtonCount -gt 0)
    $hasAnyInput = ($hasButtons -or [bool]$metrics.HasControls)

    # The old dedicated Adaptive card remains as a compatibility host for theme
    # state, but it is no longer part of the visible layout. Reparent its typed
    # controls into the main physical-input card instead.
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
    $adaptiveMetrics = Get-AdaptiveInputStatusLayoutMetrics
    $hasAnyInput = ($HasButtons -or [bool]$adaptiveMetrics.HasControls)

    $cursorY = 29

    if ($null -ne $script:ButtonStateGroup -and -not $script:ButtonStateGroup.IsDisposed) {
        $script:ButtonStateGroup.Location = [System.Drawing.Point]::new(24, 356)
    }

    if ($null -ne $script:ButtonStateFlow -and -not $script:ButtonStateFlow.IsDisposed) {
        if ($HasButtons) {
            $script:ButtonStateFlow.Location = [System.Drawing.Point]::new(13, $cursorY)
            $script:ButtonStateFlow.Size = [System.Drawing.Size]::new(606, [int]$buttonMetrics.FlowHeight)
            $script:ButtonStateFlow.WrapContents = [bool]$buttonMetrics.Compact
            $script:ButtonStateFlow.AutoScroll = $false
            $cursorY += [int]$buttonMetrics.FlowHeight + 4
        }
    }

    if ($adaptiveMetrics.HasControls) {
        $shareTypedRow = (
            $adaptiveMetrics.ToggleCount -gt 0 -and
            $adaptiveMetrics.EncoderCount -gt 0 -and
            $adaptiveMetrics.ToggleRows -eq 1 -and
            $adaptiveMetrics.EncoderRows -eq 1 -and
            $adaptiveMetrics.ToggleCount -le 3 -and
            $adaptiveMetrics.EncoderCount -le 2
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

            $cursorY += [Math]::Max(
                [int]$adaptiveMetrics.ToggleHeight,
                [int]$adaptiveMetrics.EncoderHeight
            )
        }
        else {
            if ($adaptiveMetrics.ToggleCount -gt 0) {
                $script:ToggleStateLabel.Location = [System.Drawing.Point]::new(13, ($cursorY + 2))
                $script:ToggleStateLabel.Size = [System.Drawing.Size]::new(82, 24)
                $script:ToggleStateFlow.Location = [System.Drawing.Point]::new(100, $cursorY)
                $script:ToggleStateFlow.Size = [System.Drawing.Size]::new(519, [int]$adaptiveMetrics.ToggleHeight)
                $cursorY += [int]$adaptiveMetrics.ToggleHeight
            }

            if ($adaptiveMetrics.EncoderCount -gt 0) {
                if ($adaptiveMetrics.ToggleCount -gt 0) {
                    $cursorY += [int]$adaptiveMetrics.SectionGap
                }
                $script:EncoderStateLabel.Location = [System.Drawing.Point]::new(13, ($cursorY + 3))
                $script:EncoderStateLabel.Size = [System.Drawing.Size]::new(82, 24)
                $script:EncoderStateFlow.Location = [System.Drawing.Point]::new(100, $cursorY)
                $script:EncoderStateFlow.Size = [System.Drawing.Size]::new(519, [int]$adaptiveMetrics.EncoderHeight)
                $cursorY += [int]$adaptiveMetrics.EncoderHeight
            }
        }
    }

    $inputGroupHeight = if ($hasAnyInput) {
        [Math]::Max(72, ($cursorY + 8))
    }
    else { 0 }

    if ($null -ne $script:ButtonStateGroup -and -not $script:ButtonStateGroup.IsDisposed -and $hasAnyInput) {
        $script:ButtonStateGroup.Size = [System.Drawing.Size]::new(632, $inputGroupHeight)
    }

    # The former separate Adaptive card stays hidden and consumes no vertical
    # space. Connection/diagnostics also no longer expands the main form.
    if ($null -ne $script:AdaptiveStateGroup -and -not $script:AdaptiveStateGroup.IsDisposed) {
        $script:AdaptiveStateGroup.Visible = $false
    }
    $advancedPanel.Visible = $false

    $inputOffset = if ($hasAnyInput) { $inputGroupHeight + 12 } else { 0 }

    $settingsButton.Location = [System.Drawing.Point]::new(24, (360 + $inputOffset))
    if ($null -ne $script:ButtonSettingsButton) {
        $script:ButtonSettingsButton.Location = [System.Drawing.Point]::new(272, (360 + $inputOffset))
    }
    if ($null -ne $script:SettingsHintControl) {
        $script:SettingsHintControl.Location = [System.Drawing.Point]::new(272, (358 + $inputOffset))
    }

    $startupGroup.Location = [System.Drawing.Point]::new(24, (414 + $inputOffset))
    $advancedToggle.Location = [System.Drawing.Point]::new(24, (516 + $inputOffset))
    if ($null -ne $script:BackupMenuButton -and -not $script:BackupMenuButton.IsDisposed) {
        $script:BackupMenuButton.Location = [System.Drawing.Point]::new(292, (516 + $inputOffset))
    }

    $collapsedHeight = 592 + $inputOffset
    $windowHeight = 631 + $inputOffset

    $form.MinimumSize = [System.Drawing.Size]::new(696, $windowHeight)
    $form.MaximumSize = [System.Drawing.Size]::new(696, $windowHeight)
    $form.ClientSize = [System.Drawing.Size]::new(680, $collapsedHeight)
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

    $script:LastButtonUiVisible = $hasButtons
    Update-AdaptiveInputFeatureUi
    Set-MainButtonLayout -HasButtons $hasButtons

    if ($hasButtons) {
        Update-MainButtonIndicators
    }
}

function Set-SliderAudioLevelDirect {
'@

$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Update-AdaptiveInputFeatureUi \{.*?^function Set-SliderAudioLevelDirect \{' `
    -Replacement $combinedLayout `
    -Label 'combine physical input state into one compact card'

# ---------------------------------------------------------------------------
# Diagnostics dialog
# ---------------------------------------------------------------------------
# The old accordion made the main window grow beyond a 1080p working area once
# Adaptive controls were present. Reuse the existing connection/driver controls
# in a fixed dialog instead of duplicating their behavior or event handlers.

$diagnosticsFunctions = @'
function Show-ConnectionDiagnosticsWindow {
    if ($null -eq $form -or $form.IsDisposed) { return }

    Refresh-PortList
    Update-ConnectionControls
    Update-DriverStatus

    $dialog = New-Object System.Windows.Forms.Form
    $title = [string](T -Key 'DiagnosticsClosed')
    $dialog.Text = ($title -replace '\s*[▼▲]\s*$', '')
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.ClientSize = [System.Drawing.Size]::new(680, 296)
    $dialog.MinimumSize = [System.Drawing.Size]::new(696, 335)
    $dialog.MaximumSize = [System.Drawing.Size]::new(696, 335)
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.Font = $form.Font
    Set-FormAppIcon -Form $dialog

    $connectionGroup.Location = [System.Drawing.Point]::new(24, 10)
    $driverGroup.Location = [System.Drawing.Point]::new(24, 168)

    # Adding a WinForms control to another Controls collection reparents it.
    # Keep one canonical set of controls so diagnostics actions/config state do
    # not diverge from the rest of the application.
    $dialog.Controls.Add($connectionGroup)
    $dialog.Controls.Add($driverGroup)

    try {
        Apply-ThemeToForm -Form $dialog -ThemeName (Get-EffectiveTheme)
        [void]$dialog.ShowDialog($form)
    }
    finally {
        if (-not $connectionGroup.IsDisposed) {
            $advancedPanel.Controls.Add($connectionGroup)
            $connectionGroup.Location = [System.Drawing.Point]::new(24, 0)
        }
        if (-not $driverGroup.IsDisposed) {
            $advancedPanel.Controls.Add($driverGroup)
            $driverGroup.Location = [System.Drawing.Point]::new(24, 158)
        }
        if (-not $dialog.IsDisposed) {
            $dialog.Dispose()
        }
    }
}

function Set-AdvancedExpanded {
    param(
        [bool]$Expanded,
        [bool]$Persist = $true
    )

    # Compatibility shim for old config/localization call sites. Diagnostics is
    # now a separate dialog, so the main window never enters an expanded state.
    $advancedPanel.Visible = $false
    $label = [string](T -Key 'DiagnosticsClosed')
    $advancedToggle.Text = ($label -replace '\s*[▼▲]\s*$', '')

    $hasButtons = ($script:IsConnected -and $script:DetectedButtonCount -gt 0)
    Set-MainButtonLayout -HasButtons $hasButtons

    $script:Config.app.advancedExpanded = $false
    if ($Persist) {
        Save-Config -Config $script:Config
    }
}

if ([string]$script:Config.connection.mode -eq 'manual') {
'@

$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern "(?ms)^function Set-AdvancedExpanded \{.*?^if \(\[string\]\`$script:Config\.connection\.mode -eq 'manual'\) \{" `
    -Replacement $diagnosticsFunctions `
    -Label 'move connection diagnostics into a fixed dialog'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText '$advancedToggle.Add_Click({ Set-AdvancedExpanded -Expanded (-not $advancedPanel.Visible) })' `
    -NewText '$advancedToggle.Add_Click({ Show-ConnectionDiagnosticsWindow })' `
    -Label 'open diagnostics dialog from main button'

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($resolved, $text, $utf8)
Write-Host "Applied compact Adaptive main UI revision and diagnostics dialog: $resolved"
