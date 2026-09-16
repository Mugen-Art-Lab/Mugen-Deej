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

$source = (Resolve-Path -LiteralPath $SourcePath).Path
$text = [System.IO.File]::ReadAllText($source, [System.Text.Encoding]::UTF8)

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
    $picker.Text = $(if ($script:Language -eq 'ru') { 'Кнопка виртуального геймпада' } else { 'Virtual gamepad button' })
    $picker.StartPosition = 'CenterParent'
    $picker.ClientSize = [System.Drawing.Size]::new(520, 370)
    $picker.MinimumSize = [System.Drawing.Size]::new(536, 409)
    $picker.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $picker.FormBorderStyle = 'FixedDialog'
    $picker.MaximizeBox = $false
    $picker.MinimizeBox = $false
    $picker.Tag = $null
    Set-FormAppIcon -Form $picker

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = $(if ($script:Language -eq 'ru') { 'Выберите кнопку Xbox' } else { 'Choose an Xbox button' })
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(24, 18)
    $picker.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = $(if ($script:Language -eq 'ru') { 'Физическая кнопка Mugen будет удерживать эту кнопку виртуального XInput-геймпада.' } else { 'The physical Mugen button will hold this button on the virtual XInput gamepad.' })
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = [System.Drawing.Point]::new(27, 53)
    $hint.Size = [System.Drawing.Size]::new(465, 38)
    $picker.Controls.Add($hint)

    $choices = @(
        @('LB',          'virtual:xbox:lb',     28, 101, 218, 42),
        @('RB',          'virtual:xbox:rb',    274, 101, 218, 42),
        @('Back / View', 'virtual:xbox:back',   28, 151, 218, 42),
        @('Start / Menu','virtual:xbox:start', 274, 151, 218, 42),
        @('L3',          'virtual:xbox:l3',     28, 201, 218, 42),
        @('R3',          'virtual:xbox:r3',    274, 201, 218, 42),
        @('A',           'virtual:xbox:a',      28, 258, 105, 44),
        @('B',           'virtual:xbox:b',     148, 258, 105, 44),
        @('X',           'virtual:xbox:x',     268, 258, 105, 44),
        @('Y',           'virtual:xbox:y',     388, 258, 105, 44)
    )

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

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = $(if ($script:Language -eq 'ru') { 'Отмена' } else { 'Cancel' })
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(387, 320)
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
    $pendingVirtualEnabled = $false
    if ($script:VirtualGamepadFeatureAvailable) {
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
    $buttonForm.ClientSize = [System.Drawing.Size]::new(720, 590)
    $buttonForm.MinimumSize = [System.Drawing.Size]::new(736, 629)
'@ `
    -Label 'expand button settings dialog'

# Controller mode gets its own clean section instead of squeezing explanatory
# text into the same 34-pixel row as the combo box.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern '(?ms)^    \$panel = New-Object System\.Windows\.Forms\.Panel\r?\n    \$panel\.Location = \[System\.Drawing\.Point\]::new\(22, 132\)\r?\n    \$panel\.Size = \[System\.Drawing\.Size\]::new\(676, 296\)\r?\n    \$panel\.AutoScroll = \$true\r?\n    \$buttonForm\.Controls\.Add\(\$panel\)' `
    -Replacement @'
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
    $virtualCombo.Enabled = $script:VirtualGamepadFeatureAvailable
    $buttonForm.Controls.Add($virtualCombo)

    $virtualStatus = New-Object System.Windows.Forms.Label
    $virtualStatus.Text = $(if ($script:Language -eq 'ru') { 'Создаёт XInput-геймпад через повышенный helper. UAC появится при включении.' } else { 'Creates an XInput gamepad through the elevated helper. UAC appears when enabled.' })
    $virtualStatus.ForeColor = [System.Drawing.Color]::DimGray
    $virtualStatus.Location = [System.Drawing.Point]::new(25, 173)
    $virtualStatus.Size = [System.Drawing.Size]::new(660, 34)
    $buttonForm.Controls.Add($virtualStatus)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = [System.Drawing.Point]::new(22, 214)
    $panel.Size = [System.Drawing.Size]::new(676, 310)
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
        if ($script:VirtualGamepadFeatureAvailable) {
            $currentVirtualAction = [string]$pendingActions[$i]
            if (Test-MugenVirtualGamepadAction -Action $currentVirtualAction) {
                [void]$combo.Items.Add((Get-MugenVirtualGamepadActionDisplay -Action $currentVirtualAction))
                [void]$state.ActionMap.Add($currentVirtualAction)
            }

            [void]$combo.Items.Add($(if ($script:Language -eq 'ru') { 'Выбрать кнопку геймпада…' } else { 'Choose gamepad button…' }))
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
    '$cancel.Location = [System.Drawing.Point]::new(472, 537)'
)
$text = $text.Replace(
    '$save.Location = [System.Drawing.Point]::new(588, 447)',
    '$save.Location = [System.Drawing.Point]::new(588, 537)'
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

        if ($script:VirtualGamepadFeatureAvailable) {
            Set-MugenVirtualGamepadEnabled -Enabled ($virtualCombo.SelectedIndex -eq 1)
            [void](Sync-MugenVirtualGamepadState -Values @($script:LatestButtons))
        }

'@ `
    -Label 'save virtual controller setting'

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputPath, $text, $utf8)
Write-Host "Integrated runtime written: $OutputPath"
