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

# Make a compact controller-mode row above the scrolling button list.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern '(?ms)^    \$panel = New-Object System\.Windows\.Forms\.Panel\r?\n    \$panel\.Location = \[System\.Drawing\.Point\]::new\(22, 132\)\r?\n    \$panel\.Size = \[System\.Drawing\.Size\]::new\(676, 296\)\r?\n    \$panel\.AutoScroll = \$true\r?\n    \$buttonForm\.Controls\.Add\(\$panel\)' `
    -Replacement @'
    $virtualLabel = New-Object System.Windows.Forms.Label
    $virtualLabel.Text = $(if ($script:Language -eq 'ru') { 'Виртуальный контроллер:' } else { 'Virtual controller:' })
    $virtualLabel.Location = [System.Drawing.Point]::new(25, 137)
    $virtualLabel.Size = [System.Drawing.Size]::new(180, 28)
    $buttonForm.Controls.Add($virtualLabel)

    $virtualCombo = New-Object MugenDeejWindowing.MugenComboBox
    $virtualCombo.DropDownStyle = 'DropDownList'
    $virtualCombo.Location = [System.Drawing.Point]::new(210, 132)
    $virtualCombo.Size = [System.Drawing.Size]::new(310, 30)
    [void]$virtualCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Выключен' } else { 'Off' }))
    [void]$virtualCombo.Items.Add('Xbox 360 / XInput')
    $virtualCombo.SelectedIndex = $(if ($pendingVirtualEnabled) { 1 } else { 0 })
    $virtualCombo.Enabled = $script:VirtualGamepadFeatureAvailable
    $buttonForm.Controls.Add($virtualCombo)

    $virtualStatus = New-Object System.Windows.Forms.Label
    $virtualStatus.Text = $(if ($script:Language -eq 'ru') { 'При включении Windows запросит UAC для виртуального HID.' } else { 'Enabling it will request UAC for the virtual HID helper.' })
    $virtualStatus.ForeColor = [System.Drawing.Color]::DimGray
    $virtualStatus.Location = [System.Drawing.Point]::new(528, 134)
    $virtualStatus.Size = [System.Drawing.Size]::new(166, 34)
    $buttonForm.Controls.Add($virtualStatus)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = [System.Drawing.Point]::new(22, 174)
    $panel.Size = [System.Drawing.Size]::new(676, 254)
    $panel.AutoScroll = $true
    $buttonForm.Controls.Add($panel)
'@ `
    -Label 'add virtual controller selector'

# Add the Xbox virtual outputs to each physical-button destination list.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern '(?m)^(        \$action = \[string\]\$pendingActions\[\$i\]\r?)$' `
    -Replacement @'
        if ($script:VirtualGamepadFeatureAvailable) {
            foreach ($virtualAction in @(Get-MugenVirtualGamepadActionDefinitions)) {
                [void]$combo.Items.Add([string]$virtualAction.Display)
                [void]$state.ActionMap.Add([string]$virtualAction.Action)
            }
        }

$1
'@ `
    -Label 'add Xbox actions to button mappings'

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

# Make the dialog copy acknowledge the new destination type.
$text = $text.Replace(
    'Назначьте каждой физической кнопке действие: регулятор, медиакоманду, системную громкость, горячую клавишу, запуск программы / файла, папки, URL или команды Windows.',
    'Назначьте каждой физической кнопке действие: регулятор, виртуальный геймпад, медиакоманду, системную громкость, горячую клавишу, запуск программы / файла, папки, URL или команды Windows.'
)
$text = $text.Replace(
    'Assign each physical button an action: control mute, media, system volume, a hotkey, launch a program / file, folder, URL, or Windows command.',
    'Assign each physical button an action: control mute, virtual gamepad, media, system volume, a hotkey, launch a program / file, folder, URL, or Windows command.'
)

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputPath, $text, $utf8)
Write-Host "Integrated runtime written: $OutputPath"
