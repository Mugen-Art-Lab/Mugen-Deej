param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Replace-RegexExactlyOnce {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Replacement,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $regex = New-Object System.Text.RegularExpressions.Regex(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )
    $matches = $regex.Matches($Text)
    if ($matches.Count -ne 1) {
        throw "Integration patch '$Label' expected exactly one match, found $($matches.Count)."
    }

    return $regex.Replace($Text, $Replacement, 1)
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
        throw "Integration literal patch '$Label' expected exactly one match."
    }

    return $Text.Substring(0, $first) + $NewText + $Text.Substring($first + $OldText.Length)
}

$source = (Resolve-Path -LiteralPath $SourcePath).Path
$text = [System.IO.File]::ReadAllText($source, [System.Text.Encoding]::UTF8)

# Stable main remains 1.0.0. The integrated feature branch is now frozen for
# 2.0.0 RC testing and should identify staged packages as the release candidate.
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText '$script:AppVersion = ''1.0.0''' `
    -NewText '$script:AppVersion = ''2.0.0-rc1''' `
    -Label 'set RC1 product version'

# Stable 1.0.0 did not know virtual Xbox action strings. Preserve both virtual
# buttons and digital stick directions when controller discovery normalizes the
# loaded button-action array; otherwise a reconnect silently turns them into none.
$normalizeVirtualOld = @'
        if (
            -not $valid -and
            $action -match '^(launch64|folder64|url64|command64):(.+)$'
        ) {
            $decoded = Decode-ButtonActionPayload -Payload $Matches[2]
            $valid = -not [string]::IsNullOrWhiteSpace($decoded)
        }

        if (-not $valid) {
            $action = 'none'
        }
'@

$normalizeVirtualNew = @'
        if (
            -not $valid -and
            $action -match '^(launch64|folder64|url64|command64):(.+)$'
        ) {
            $decoded = Decode-ButtonActionPayload -Payload $Matches[2]
            $valid = -not [string]::IsNullOrWhiteSpace($decoded)
        }

        # Preserve virtual gamepad actions during button normalization.
        if (
            -not $valid -and
            $script:VirtualGamepadFeatureAvailable -and
            (Test-MugenVirtualGamepadAction -Action $action)
        ) {
            $valid = $true
        }

        if (-not $valid) {
            $action = 'none'
        }
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $normalizeVirtualOld `
    -NewText $normalizeVirtualNew `
    -Label 'preserve virtual actions during normalization'

# Load the integration module from the packaged app directory. The stable
# source file itself stays untouched on this experimental branch; CI produces
# a patched development runtime and validates every anchor before packaging.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern '(?m)^\$script:ButtonSettingsButton = \$null\r?$' `
    -Replacement @'
$script:ButtonSettingsButton = $null
$script:VirtualGamepadFeatureAvailable = $false
$virtualGamepadModulePath = Join-Path $script:BaseDir 'virtual-gamepad\MugenDeej.VirtualGamepad.ps1'
if (Test-Path -LiteralPath $virtualGamepadModulePath -PathType Leaf) {
    . $virtualGamepadModulePath
    $script:VirtualGamepadFeatureAvailable = $true
}
'@ `
    -Label 'load integration module'

# Virtual mappings are stateful and must not fall through to the existing
# press-only action dispatcher.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern @'
(?ms)(    if \(\r?\n        \[string\]::IsNullOrWhiteSpace\(\$action\) -or\r?\n        \$action -eq 'none'\r?\n    \) \{\r?\n        return\r?\n    \}\r?\n)
'@ `
    -Replacement @'
$1
    if (
        $script:VirtualGamepadFeatureAvailable -and
        (Test-MugenVirtualGamepadAction -Action $action)
    ) {
        return
    }
'@ `
    -Label 'skip virtual mappings in press-only dispatcher'

# Feed every full button state frame into the virtual controller service. This
# is intentionally before edge detection so press and release both propagate.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern '(?m)^(    \$script:LatestButtons = \$valuesArray\r?)$' `
    -Replacement @'
$1

    if ($script:VirtualGamepadFeatureAvailable) {
        Update-MugenVirtualGamepadButtonStates -Values $valuesArray
    }
'@ `
    -Label 'route stateful button frames'


# Synchronous Add-Content on every button edge is useful for ordinary desktop
# actions, but during gameplay it can stall the same WinForms thread that drains
# serial input. The virtual gamepad already received the full state frame above,
# so keep per-edge disk logging out of the active XInput hot path.
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
        $state = if ($newValue -eq 0) { 'pressed' } else { 'released' }
        Write-Log ('Button {0} {1} (raw={2})' -f ($i + 1), $state, $newValue) 'INFO'
        if ($newValue -eq 0) {
'@ `
    -NewText @'
        $state = if ($newValue -eq 0) { 'pressed' } else { 'released' }
        $xinputHotPath = (
            $script:VirtualGamepadFeatureAvailable -and
            $script:VirtualGamepadActive
        )
        if (-not $xinputHotPath) {
            Write-Log ('Button {0} {1} (raw={2})' -f ($i + 1), $state, $newValue) 'INFO'
        }
        if ($newValue -eq 0) {
'@ `
    -Label 'remove synchronous edge logging from active XInput hot path'


# The stable app only needs a 20 ms UI loop for audio/control-surface work. While
# XInput is active, shorten the same safe UI-thread serial drain cadence so a
# freshly arrived button packet spends less time waiting for the next WM_TIMER.
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 20
$timer.Add_Tick({
    if ($script:IsSuspended -or $script:Closing -or $script:ExitRequested) { return }
'@ `
    -NewText @'
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 20
$timer.Add_Tick({
    $desiredInputInterval = if (
        $script:VirtualGamepadFeatureAvailable -and
        $script:VirtualGamepadActive
    ) { 5 } else { 20 }
    if ($timer.Interval -ne $desiredInputInterval) {
        $timer.Interval = $desiredInputInterval
    }

    if ($script:IsSuspended -or $script:Closing -or $script:ExitRequested) { return }
'@ `
    -Label 'lower active XInput serial polling latency'


# Keep the physical and virtual status rows in the same language immediately.
# The old handler refreshed driver/PnP state synchronously BEFORE the status
# text. On machines where Win32_PnPEntity is slow, the entire form could look
# half-translated for seconds. Update visible text first; only refresh the
# hidden diagnostics driver card when it is actually visible.
$languageStatusPattern = @'
(?ms)^(    Apply-MainLocalization\r?\n)    Update-DriverStatus\r?\n(    if \(\$script:IsConnected\) \{\r?\n        Set-Status \(Get-ControllerConnectedStatusText -PortName \$script:ConnectedPort\) 'ok'\r?\n    \}\r?\n    else \{\r?\n        Set-Status \(T -Key 'StatusNotConnected'\) 'idle'\r?\n    \}\r?\n)(    Write-Log "Interface language changed to \$newLanguage"\r?$)
'@
$languageStatusReplacement = @'
$1$2    if ($script:VirtualGamepadFeatureAvailable) {
        Refresh-MugenVirtualGamepadLocalizedStatus
    }
    if ($advancedPanel.Visible) {
        Update-DriverStatus
    }
$3
'@
$text = Replace-RegexExactlyOnce -Text $text -Pattern $languageStatusPattern -Replacement $languageStatusReplacement -Label 'refresh visible localization before optional driver query'

# A physical-controller disconnect tears down the virtual device as well.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern '(?m)^(    \$script:Serial = \$null\r?)$' `
    -Replacement @'
    if ($script:VirtualGamepadFeatureAvailable) {
        Stop-MugenVirtualGamepad -Reason $(if ([string]::IsNullOrWhiteSpace($Reason)) { 'controller port closed' } else { $Reason })
    }

$1
'@ `
    -Label 'teardown virtual controller with COM port'

# Small visual Xbox-button picker. The main action combo only gets one
# "choose gamepad button" entry instead of ten Xbox items mixed into every
# other action type.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern '(?m)^function Show-ButtonSettings \{\r?$' `
    -Replacement @'
function Get-MugenVirtualGamepadActionDisplay {
    param([string]$Action)

    foreach ($definition in @(Get-MugenVirtualGamepadActionDefinitions)) {
        if ([string]$definition.Action -eq [string]$Action) {
            return [string]$definition.Display
        }
    }

    return $(if ($script:Language -eq 'ru') { 'Геймпад' } else { 'Gamepad' })
}

function Show-MugenVirtualGamepadButtonPicker {
    param(
        [string]$ExistingAction,
        [System.Windows.Forms.IWin32Window]$Owner
    )

    $picker = New-Object System.Windows.Forms.Form
    $picker.Text = $(if ($script:Language -eq 'ru') { 'Управление виртуального геймпада' } else { 'Virtual gamepad control' })
    $picker.StartPosition = 'CenterParent'
    $picker.ClientSize = [System.Drawing.Size]::new(760, 625)
    $picker.MinimumSize = [System.Drawing.Size]::new(776, 664)
    $picker.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $picker.FormBorderStyle = 'FixedDialog'
    $picker.MaximizeBox = $false
    $picker.MinimizeBox = $false
    $picker.Tag = $null
    Set-FormAppIcon -Form $picker

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = $(if ($script:Language -eq 'ru') { 'Выберите элемент геймпада Xbox' } else { 'Choose an Xbox gamepad control' })
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(24, 18)
    $picker.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = $(if ($script:Language -eq 'ru') { 'Выберите, что будет делать выбранная кнопка на виртуальном геймпаде Xbox. LT/RT нажимаются полностью.' } else { 'Choose what the selected button should do on the virtual Xbox gamepad. LT/RT are full-press.' })
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = [System.Drawing.Point]::new(27, 53)
    $hint.Size = [System.Drawing.Size]::new(706, 42)
    $picker.Controls.Add($hint)

    # Spatial Xbox-style control map: shoulders at the top, left stick / D-pad
    # on the left, ABXY / right stick on the right, View/Menu in the middle.
    $choices = @(
        @('LT',          'virtual:xbox:lt',         38, 108, 132, 36),
        @('LB',          'virtual:xbox:lb',         38, 150, 132, 36),
        @('RT',          'virtual:xbox:rt',        590, 108, 132, 36),
        @('RB',          'virtual:xbox:rb',        590, 150, 132, 36),

        @('View',        'virtual:xbox:back',      278, 150,  96, 38),
        @('Menu',        'virtual:xbox:start',     386, 150,  96, 38),

        @('↑',           'virtual:xbox:lsy:up',    154, 236,  52, 36),
        @('←',           'virtual:xbox:lsx:left',   96, 278,  52, 36),
        @('L3',          'virtual:xbox:l3',        154, 278,  52, 36),
        @('→',           'virtual:xbox:lsx:right', 212, 278,  52, 36),
        @('↓',           'virtual:xbox:lsy:down',  154, 320,  52, 36),

        @('Y',           'virtual:xbox:y',         604, 236,  52, 36),
        @('X',           'virtual:xbox:x',         546, 278,  52, 36),
        @('B',           'virtual:xbox:b',         662, 278,  52, 36),
        @('A',           'virtual:xbox:a',         604, 320,  52, 36),

        @('↑',           'virtual:xbox:dpad:up',   154, 416,  52, 36),
        @('←',           'virtual:xbox:dpad:left',  96, 458,  52, 36),
        @('→',           'virtual:xbox:dpad:right',212, 458,  52, 36),
        @('↓',           'virtual:xbox:dpad:down', 154, 500,  52, 36),

        @('↑',           'virtual:xbox:rsy:up',    604, 416,  52, 36),
        @('←',           'virtual:xbox:rsx:left',  546, 458,  52, 36),
        @('R3',          'virtual:xbox:r3',        604, 458,  52, 36),
        @('→',           'virtual:xbox:rsx:right', 662, 458,  52, 36),
        @('↓',           'virtual:xbox:rsy:down',  604, 500,  52, 36)
    )

    $leftStickLabel = New-Object System.Windows.Forms.Label
    $leftStickLabel.Text = $(if ($script:Language -eq 'ru') { 'Левый стик' } else { 'Left stick' })
    $leftStickLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $leftStickLabel.Location = [System.Drawing.Point]::new(96, 205)
    $leftStickLabel.Size = [System.Drawing.Size]::new(168, 24)
    $leftStickLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $picker.Controls.Add($leftStickLabel)

    $faceLabel = New-Object System.Windows.Forms.Label
    $faceLabel.Text = $(if ($script:Language -eq 'ru') { 'Основные кнопки' } else { 'Face buttons' })
    $faceLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $faceLabel.Location = [System.Drawing.Point]::new(546, 205)
    $faceLabel.Size = [System.Drawing.Size]::new(168, 24)
    $faceLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $picker.Controls.Add($faceLabel)

    $dpadLabel = New-Object System.Windows.Forms.Label
    $dpadLabel.Text = $(if ($script:Language -eq 'ru') { 'Крестовина' } else { 'D-pad' })
    $dpadLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $dpadLabel.Location = [System.Drawing.Point]::new(96, 385)
    $dpadLabel.Size = [System.Drawing.Size]::new(168, 24)
    $dpadLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $picker.Controls.Add($dpadLabel)

    $rightStickLabel = New-Object System.Windows.Forms.Label
    $rightStickLabel.Text = $(if ($script:Language -eq 'ru') { 'Правый стик' } else { 'Right stick' })
    $rightStickLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $rightStickLabel.Location = [System.Drawing.Point]::new(546, 385)
    $rightStickLabel.Size = [System.Drawing.Size]::new(168, 24)
    $rightStickLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $picker.Controls.Add($rightStickLabel)

    # A small non-clickable hub makes the D-pad read as a cross rather than a
    # loose set of four arrows.
    $dpadHub = New-Object System.Windows.Forms.Label
    $dpadHub.Text = '✚'
    $dpadHub.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 16)
    $dpadHub.ForeColor = [System.Drawing.Color]::DimGray
    $dpadHub.Location = [System.Drawing.Point]::new(154, 458)
    $dpadHub.Size = [System.Drawing.Size]::new(52, 36)
    $dpadHub.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $picker.Controls.Add($dpadHub)

    foreach ($choice in $choices) {
        $choiceButton = New-Object MugenDeejWindowing.MugenButton
        $choiceButton.Text = [string]$choice[0]
        if ([string]$choice[1] -eq [string]$ExistingAction) {
            $choiceButton.Text = '● ' + [string]$choice[0]
        }
        $choiceButton.Tag = [string]$choice[1]
        $choiceButton.Location = [System.Drawing.Point]::new([int]$choice[2], [int]$choice[3])
        $choiceButton.Size = [System.Drawing.Size]::new([int]$choice[4], [int]$choice[5])
        $choiceButton.Add_Click({
            param($sender, $eventArgs)
            $hostForm = $sender.FindForm()
            $hostForm.Tag = [string]$sender.Tag
            $hostForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $hostForm.Close()
        })
        $picker.Controls.Add($choiceButton)
    }

    # Keep the decorative D-pad hub above the surrounding clickable arrows.
    $dpadHub.BringToFront()

    $axisHint = New-Object System.Windows.Forms.Label
    $axisHint.Text = $(if ($script:Language -eq 'ru') { 'Противоположные направления одной оси взаимно гасятся и оставляют её в центре.' } else { 'Opposite directions on the same axis cancel each other and leave that axis centered.' })
    $axisHint.ForeColor = [System.Drawing.Color]::DimGray
    $axisHint.Location = [System.Drawing.Point]::new(278, 425)
    $axisHint.Size = [System.Drawing.Size]::new(204, 72)
    $axisHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $picker.Controls.Add($axisHint)

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = $(if ($script:Language -eq 'ru') { 'Отмена' } else { 'Cancel' })
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(628, 568)
    $cancel.Size = [System.Drawing.Size]::new(105, 36)
    $picker.Controls.Add($cancel)
    $picker.CancelButton = $cancel

    Apply-ThemeToForm -Form $picker

    $picker.Add_Shown({
        Ensure-FormVisible -Form $picker -CenterIfOffscreen
    })

    $result = $picker.ShowDialog($Owner)
    $selectedAction = $null
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedAction = [string]$picker.Tag
    }

    $picker.Dispose()
    return $selectedAction
}

function Show-ButtonSettings {
'@ `
    -Label 'add virtual gamepad button picker'

# Capture the staged enabled state when the button settings dialog opens.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern '(?m)^(    \$buttonForm = New-Object System\.Windows\.Forms\.Form\r?)$' `
    -Replacement @'
    $virtualProtocolAvailable = (
        $script:VirtualGamepadFeatureAvailable -and
        (Test-MugenVirtualGamepadProtocolAvailable)
    )
    $pendingVirtualEnabled = $false
    if ($virtualProtocolAvailable) {
        $pendingVirtualEnabled = Get-MugenVirtualGamepadEnabled
    }

$1
'@ `
    -Label 'load pending virtual controller setting'

# Give the new controller section enough vertical room in both languages.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern '(?m)^    \$buttonForm\.ClientSize = \[System\.Drawing\.Size\]::new\(720, 500\)\r?\n    \$buttonForm\.MinimumSize = \[System\.Drawing\.Size\]::new\(736, 539\)' `
    -Replacement @'
    $buttonForm.ClientSize = [System.Drawing.Size]::new(720, $(if ($virtualProtocolAvailable) { 590 } else { 500 }))
    $buttonForm.MinimumSize = [System.Drawing.Size]::new(736, $(if ($virtualProtocolAvailable) { 629 } else { 539 }))
'@ `
    -Label 'expand button settings dialog'

# Controller mode gets its own clean section instead of squeezing explanatory
# text into the same 34-pixel row as the combo box.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern '(?ms)^    \$panel = New-Object System\.Windows\.Forms\.Panel\r?\n    \$panel\.Location = \[System\.Drawing\.Point\]::new\(22, 132\)\r?\n    \$panel\.Size = \[System\.Drawing\.Size\]::new\(676, 296\)\r?\n    \$panel\.AutoScroll = \$true\r?\n    \$buttonForm\.Controls\.Add\(\$panel\)' `
    -Replacement @'
    $virtualCombo = $null
    if ($virtualProtocolAvailable) {
        $virtualLabel = New-Object System.Windows.Forms.Label
        $virtualLabel.Text = $(if ($script:Language -eq 'ru') { 'Виртуальный контроллер:' } else { 'Virtual controller:' })
        $virtualLabel.Location = [System.Drawing.Point]::new(25, 139)
        $virtualLabel.Size = [System.Drawing.Size]::new(180, 28)
        $buttonForm.Controls.Add($virtualLabel)

        $virtualCombo = New-Object MugenDeejWindowing.MugenComboBox
        $virtualCombo.DropDownStyle = 'DropDownList'
        $virtualCombo.Location = [System.Drawing.Point]::new(210, 134)
        $virtualCombo.Size = [System.Drawing.Size]::new(310, 30)
        [void]$virtualCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Выключен' } else { 'Off' }))
        [void]$virtualCombo.Items.Add('Xbox 360 / XInput')
        $virtualCombo.SelectedIndex = $(if ($pendingVirtualEnabled) { 1 } else { 0 })
        $buttonForm.Controls.Add($virtualCombo)

        $virtualStatus = New-Object System.Windows.Forms.Label
        $virtualStatus.Text = $(if ($script:Language -eq 'ru') { 'Создаёт XInput-геймпад через повышенный helper. UAC появится при включении.' } else { 'Creates an XInput gamepad through the elevated helper. UAC appears when enabled.' })
        $virtualStatus.ForeColor = [System.Drawing.Color]::DimGray
        $virtualStatus.Location = [System.Drawing.Point]::new(25, 173)
        $virtualStatus.Size = [System.Drawing.Size]::new(660, 34)
        $buttonForm.Controls.Add($virtualStatus)
    }

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = [System.Drawing.Point]::new(22, $(if ($virtualProtocolAvailable) { 214 } else { 132 }))
    $panel.Size = [System.Drawing.Size]::new(676, $(if ($virtualProtocolAvailable) { 310 } else { 296 }))
    $panel.AutoScroll = $true
    $buttonForm.Controls.Add($panel)
'@ `
    -Label 'add virtual controller selector'

# Keep only the current Xbox mapping plus one visual picker entry in each
# destination combo. This avoids a long flat list of ten gamepad buttons.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern '(?m)^(        \$action = \[string\]\$pendingActions\[\$i\]\r?)$' `
    -Replacement @'
        if ($virtualProtocolAvailable) {
            $currentVirtualAction = [string]$pendingActions[$i]
            if (Test-MugenVirtualGamepadAction -Action $currentVirtualAction) {
                [void]$combo.Items.Add((Get-MugenVirtualGamepadActionDisplay -Action $currentVirtualAction))
                [void]$state.ActionMap.Add($currentVirtualAction)
            }

            [void]$combo.Items.Add($(if ($script:Language -eq 'ru') { 'Выбрать управление геймпада…' } else { 'Choose gamepad control…' }))
            [void]$state.ActionMap.Add('virtual:xbox:configure')
        }

$1
'@ `
    -Label 'add visual gamepad picker entry'

# Treat the virtual picker like the existing hotkey/program/folder editors.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern "(?m)^(                    'hotkey:configure',\r?)$" `
    -Replacement @'
                    'virtual:xbox:configure',
$1
'@ `
    -Label 'route virtual picker through configure path'

$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern '(?m)^(            switch \(\$selectedAction\) \{\r?)$' `
    -Replacement @'
$1
                'virtual:xbox:configure' {
                    $configuredAction = Show-MugenVirtualGamepadButtonPicker `
                        -ExistingAction $previousAction `
                        -Owner $buttonForm
                }
'@ `
    -Label 'open virtual button picker'

$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern "(?m)^(                        \`$mappedAction -match '\^hotkey:' -or\r?)$" `
    -Replacement @'
                        (Test-MugenVirtualGamepadAction -Action $mappedAction) -or
$1
'@ `
    -Label 'find existing virtual mapping'

$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern "(?m)^                \`$display = if \(\r?\n                    \`$configuredAction -match '\^hotkey:'\r?\n                \) \{\r?$" `
    -Replacement @'
                $display = if (
                    Test-MugenVirtualGamepadAction -Action $configuredAction
                ) {
                    Get-MugenVirtualGamepadActionDisplay -Action $configuredAction
                }
                elseif (
                    $configuredAction -match '^hotkey:'
                ) {
'@ `
    -Label 'display configured virtual mapping'

# Move the footer buttons with the taller content area.
$text = $text.Replace(
    '$cancel.Location = [System.Drawing.Point]::new(472, 447)',
    '$cancel.Location = [System.Drawing.Point]::new(472, $(if ($virtualProtocolAvailable) { 537 } else { 447 }))'
)
$text = $text.Replace(
    '$save.Location = [System.Drawing.Point]::new(588, 447)',
    '$save.Location = [System.Drawing.Point]::new(588, $(if ($virtualProtocolAvailable) { 537 } else { 447 }))'
)

# Persist enabled state alongside button actions, then immediately reconcile
# the live virtual controller with the newly saved mapping.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern '(?ms)^    \$save\.Add_Click\(\{\r?\n        \$script:ButtonActions = @\(\$pendingActions\)\r?\n        Save-ButtonActions\r?\n' `
    -Replacement @'
    $save.Add_Click({
        $script:ButtonActions = @($pendingActions)
        Save-ButtonActions

        if ($virtualProtocolAvailable -and $null -ne $virtualCombo) {
            Set-MugenVirtualGamepadEnabled -Enabled ($virtualCombo.SelectedIndex -eq 1)
            [void](Sync-MugenVirtualGamepadState -Values @($script:LatestButtons))
        }

'@ `
    -Label 'save virtual controller setting'

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputPath, $text, $utf8)
Write-Host "Integrated runtime written: $OutputPath"
