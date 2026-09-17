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
        throw "Large-button editor patch '$Label' expected exactly one literal match."
    }

    return $Text.Substring(0, $first) + $NewText + $Text.Substring($first + $OldText.Length)
}

$resolved = (Resolve-Path -LiteralPath $Path).Path
$text = [System.IO.File]::ReadAllText($resolved, [System.Text.Encoding]::UTF8)

# The v17 adaptive UI still instantiated one full action ComboBox per physical
# button and then hid all but the selected row. On a 30+ button controller that
# made the dialog look compact but kept the expensive old construction cost.
# Large mode below uses only lightweight selector tiles, one shared editor, and
# one fixed-height scrollable assignment list. Small controllers keep the old
# row-per-button editor unchanged.

$largeEditor = @'
function Get-LargeButtonActionDisplay {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'none') {
        return (Get-ButtonFeatureText -Key 'None')
    }

    if (
        $script:VirtualGamepadFeatureAvailable -and
        (Test-MugenVirtualGamepadAction -Action $Action)
    ) {
        return (Get-MugenVirtualGamepadActionDisplay -Action $Action)
    }

    if ($Action -match '^mute:(\d+)$') {
        $sliderIndex = [int]$Matches[1]
        $sliderName = if ($sliderIndex -lt @($script:Config.sliders).Count) {
            [string]$script:Config.sliders[$sliderIndex].name
        }
        else {
            [string]($sliderIndex + 1)
        }
        if ([string]::IsNullOrWhiteSpace($sliderName)) {
            $sliderName = [string]($sliderIndex + 1)
        }
        return (
            (Get-ButtonFeatureText -Key 'MuteControl') +
            ' ' + ($sliderIndex + 1) + ' — ' + $sliderName
        )
    }

    $fixedDisplay = @{
        'media:playpause' = (Get-ButtonFeatureText -Key 'PlayPause')
        'media:previous' = (Get-ButtonFeatureText -Key 'PreviousTrack')
        'media:next' = (Get-ButtonFeatureText -Key 'NextTrack')
        'media:stop' = (Get-ButtonFeatureText -Key 'StopPlayback')
        'system:volumeup' = (Get-ButtonFeatureText -Key 'VolumeUp')
        'system:volumedown' = (Get-ButtonFeatureText -Key 'VolumeDown')
        'system:volumemute' = (Get-ButtonFeatureText -Key 'VolumeMute')
    }
    if ($fixedDisplay.ContainsKey($Action)) {
        return [string]$fixedDisplay[$Action]
    }

    if ($Action -match '^hotkey:') { return (Get-HotkeyActionDisplay -Action $Action) }
    if ($Action -match '^launch64:') { return (Get-LaunchActionDisplay -Action $Action) }
    if ($Action -match '^folder64:') { return (Get-FolderActionDisplay -Action $Action) }
    if ($Action -match '^command64:') { return (Get-CommandActionDisplay -Action $Action) }
    if ($Action -match '^url64:') { return (Get-UrlActionDisplay -Action $Action) }

    return $Action
}

function Show-LargeButtonSettings {
    if (
        -not $script:IsConnected -or
        $script:DetectedButtonCount -le 12
    ) {
        return
    }

    $buildStarted = Get-Date
    Normalize-ButtonActions -Count $script:DetectedButtonCount

    $pendingActions = @($script:ButtonActions | ForEach-Object { [string]$_ })
    $pendingVirtualEnabled = $false
    if ($script:VirtualGamepadFeatureAvailable) {
        $pendingVirtualEnabled = Get-MugenVirtualGamepadEnabled
    }

    $buttonForm = New-Object System.Windows.Forms.Form
    $buttonForm.Text = Get-ButtonFeatureText -Key 'Title'
    $buttonForm.StartPosition = 'CenterParent'
    $buttonForm.ClientSize = [System.Drawing.Size]::new(760, 620)
    $buttonForm.MinimumSize = [System.Drawing.Size]::new(776, 659)
    $buttonForm.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $buttonForm.FormBorderStyle = 'FixedDialog'
    $buttonForm.MaximizeBox = $false
    $buttonForm.MinimizeBox = $false
    Set-FormAppIcon -Form $buttonForm

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-ButtonFeatureText -Key 'Heading'
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $buttonForm.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = if ($script:Language -eq 'ru') {
        'Выберите кнопку в сетке или нажмите её на контроллере. Справа редактируется только выбранная кнопка; список ниже показывает сохранённую раскладку целиком.'
    }
    else {
        'Choose a button in the grid or press it on the controller. Only the selected button is edited on the right; the list below shows the whole pending layout.'
    }
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = [System.Drawing.Point]::new(25, 56)
    $hint.Size = [System.Drawing.Size]::new(710, 43)
    $buttonForm.Controls.Add($hint)

    $saveNotice = New-Object System.Windows.Forms.Label
    $saveNotice.Text = if ($script:Language -eq 'ru') {
        'Важно: изменения начнут работать только после нажатия «Сохранить».'
    }
    else {
        'Important: changes take effect only after you click Save.'
    }
    $saveNotice.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $saveNotice.ForeColor = [System.Drawing.Color]::FromArgb(230, 170, 70)
    $saveNotice.Location = [System.Drawing.Point]::new(25, 101)
    $saveNotice.Size = [System.Drawing.Size]::new(710, 27)
    $buttonForm.Controls.Add($saveNotice)

    $virtualLabel = New-Object System.Windows.Forms.Label
    $virtualLabel.Text = if ($script:Language -eq 'ru') { 'Виртуальный контроллер:' } else { 'Virtual controller:' }
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
    $virtualStatus.Text = if ($script:Language -eq 'ru') {
        'Для создания XInput-геймпада могут потребоваться повышенные права Windows.'
    }
    else {
        'Creating the XInput gamepad may require Windows administrator elevation.'
    }
    $virtualStatus.ForeColor = [System.Drawing.Color]::DimGray
    $virtualStatus.Location = [System.Drawing.Point]::new(25, 173)
    $virtualStatus.Size = [System.Drawing.Size]::new(710, 28)
    $buttonForm.Controls.Add($virtualStatus)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = [System.Drawing.Point]::new(22, 208)
    $panel.Size = [System.Drawing.Size]::new(716, 344)
    $panel.AutoScroll = $false
    $buttonForm.Controls.Add($panel)

    $selectorFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $selectorFlow.Location = [System.Drawing.Point]::new(8, 8)
    $selectorFlow.Size = [System.Drawing.Size]::new(254, 326)
    $selectorFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $selectorFlow.WrapContents = $true
    $selectorFlow.AutoScroll = $true
    $panel.Controls.Add($selectorFlow)

    $selectedHeading = New-Object System.Windows.Forms.Label
    $selectedHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $selectedHeading.Location = [System.Drawing.Point]::new(282, 10)
    $selectedHeading.Size = [System.Drawing.Size]::new(420, 27)
    $panel.Controls.Add($selectedHeading)

    $selectedHint = New-Object System.Windows.Forms.Label
    $selectedHint.Text = if ($script:Language -eq 'ru') {
        'Нажмите физическую кнопку — Mugen сам выберет её в сетке.'
    }
    else {
        'Press a physical button and Mugen will select it in the grid.'
    }
    $selectedHint.ForeColor = [System.Drawing.Color]::DimGray
    $selectedHint.Location = [System.Drawing.Point]::new(282, 39)
    $selectedHint.Size = [System.Drawing.Size]::new(420, 37)
    $panel.Controls.Add($selectedHint)

    $actionCombo = New-Object MugenDeejWindowing.MugenComboBox
    $actionCombo.DropDownStyle = 'DropDownList'
    $actionCombo.Location = [System.Drawing.Point]::new(282, 82)
    $actionCombo.Size = [System.Drawing.Size]::new(420, 30)
    $panel.Controls.Add($actionCombo)

    $assignmentsLabel = New-Object System.Windows.Forms.Label
    $assignmentsLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $assignmentsLabel.Location = [System.Drawing.Point]::new(282, 127)
    $assignmentsLabel.Size = [System.Drawing.Size]::new(235, 25)
    $panel.Controls.Add($assignmentsLabel)

    $filterCombo = New-Object MugenDeejWindowing.MugenComboBox
    $filterCombo.DropDownStyle = 'DropDownList'
    $filterCombo.Location = [System.Drawing.Point]::new(524, 123)
    $filterCombo.Size = [System.Drawing.Size]::new(178, 29)
    [void]$filterCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Назначенные' } else { 'Assigned' }))
    [void]$filterCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Все кнопки' } else { 'All buttons' }))
    $filterCombo.SelectedIndex = 0
    $panel.Controls.Add($filterCombo)

    $assignmentList = New-Object System.Windows.Forms.ListView
    $assignmentList.Location = [System.Drawing.Point]::new(282, 158)
    $assignmentList.Size = [System.Drawing.Size]::new(420, 176)
    $assignmentList.View = [System.Windows.Forms.View]::Details
    $assignmentList.FullRowSelect = $true
    $assignmentList.HideSelection = $false
    $assignmentList.MultiSelect = $false
    [void]$assignmentList.Columns.Add($(if ($script:Language -eq 'ru') { 'Кнопка' } else { 'Button' }), 72)
    [void]$assignmentList.Columns.Add($(if ($script:Language -eq 'ru') { 'Действие' } else { 'Action' }), 320)
    $panel.Controls.Add($assignmentList)

    $selectors = @()
    for ($i = 0; $i -lt $script:DetectedButtonCount; $i++) {
        $selector = New-Object MugenDeejWindowing.MugenButtonTile
        $selector.Text = [string]($i + 1)
        $selector.Tag = $i
        $selector.Size = [System.Drawing.Size]::new(42, 28)
        $selector.Margin = New-Object System.Windows.Forms.Padding(3, 2, 3, 2)
        $selector.TextAlign = 'MiddleCenter'
        $selector.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
        $selectorFlow.Controls.Add($selector)
        $selectors += $selector
    }

    $state = [pscustomobject]@{
        Selected = 0
        LastButtons = @($script:LatestButtons)
        ActionMap = New-Object System.Collections.ArrayList
        SuppressCombo = $false
    }

    $sliderCount = [Math]::Min(
        [int]$script:DetectedSliderCount,
        [int]$script:Config.sliders.Count
    )

    $refreshAssignmentList = {
        $assignmentList.BeginUpdate()
        try {
            $assignmentList.Items.Clear()
            $assignedCount = 0
            for ($i = 0; $i -lt $pendingActions.Count; $i++) {
                $action = [string]$pendingActions[$i]
                $assigned = (-not [string]::IsNullOrWhiteSpace($action) -and $action -ne 'none')
                if ($assigned) { $assignedCount++ }
                if ($filterCombo.SelectedIndex -eq 0 -and -not $assigned) { continue }

                $item = New-Object System.Windows.Forms.ListViewItem([string]($i + 1))
                [void]$item.SubItems.Add((Get-LargeButtonActionDisplay -Action $action))
                $item.Tag = $i
                [void]$assignmentList.Items.Add($item)
            }
            $assignmentsLabel.Text = if ($script:Language -eq 'ru') {
                'Назначения: {0} из {1}' -f $assignedCount, $pendingActions.Count
            }
            else {
                'Assignments: {0} of {1}' -f $assignedCount, $pendingActions.Count
            }
        }
        finally {
            $assignmentList.EndUpdate()
        }
    }

    $populateActionCombo = {
        $index = [int]$state.Selected
        if ($index -lt 0 -or $index -ge $pendingActions.Count) { return }

        $state.SuppressCombo = $true
        try {
            $actionCombo.BeginUpdate()
            try {
                $actionCombo.Items.Clear()
                $state.ActionMap.Clear()

                [void]$actionCombo.Items.Add((Get-ButtonFeatureText -Key 'None'))
                [void]$state.ActionMap.Add('none')

                for ($sliderIndex = 0; $sliderIndex -lt $sliderCount; $sliderIndex++) {
                    $name = [string]$script:Config.sliders[$sliderIndex].name
                    if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]($sliderIndex + 1) }
                    [void]$actionCombo.Items.Add(
                        (Get-ButtonFeatureText -Key 'MuteControl') + ' ' +
                        ($sliderIndex + 1) + ' — ' + $name
                    )
                    [void]$state.ActionMap.Add(('mute:' + $sliderIndex))
                }

                foreach ($fixedAction in @(
                    @('PlayPause', 'media:playpause'),
                    @('PreviousTrack', 'media:previous'),
                    @('NextTrack', 'media:next'),
                    @('StopPlayback', 'media:stop'),
                    @('VolumeUp', 'system:volumeup'),
                    @('VolumeDown', 'system:volumedown'),
                    @('VolumeMute', 'system:volumemute')
                )) {
                    [void]$actionCombo.Items.Add((Get-ButtonFeatureText -Key $fixedAction[0]))
                    [void]$state.ActionMap.Add([string]$fixedAction[1])
                }

                $currentAction = [string]$pendingActions[$index]

                if ($script:VirtualGamepadFeatureAvailable) {
                    if (Test-MugenVirtualGamepadAction -Action $currentAction) {
                        [void]$actionCombo.Items.Add((Get-MugenVirtualGamepadActionDisplay -Action $currentAction))
                        [void]$state.ActionMap.Add($currentAction)
                    }
                    [void]$actionCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Выбрать кнопку геймпада…' } else { 'Choose gamepad button…' }))
                    [void]$state.ActionMap.Add('virtual:xbox:configure')
                }

                if (
                    $currentAction -match '^hotkey:' -or
                    $currentAction -match '^launch64:' -or
                    $currentAction -match '^folder64:' -or
                    $currentAction -match '^command64:' -or
                    $currentAction -match '^url64:'
                ) {
                    [void]$actionCombo.Items.Add((Get-LargeButtonActionDisplay -Action $currentAction))
                    [void]$state.ActionMap.Add($currentAction)
                }

                [void]$actionCombo.Items.Add((Get-ButtonFeatureText -Key 'HotkeyConfigure'))
                [void]$state.ActionMap.Add('hotkey:configure')
                if ($script:Language -eq 'ru') {
                    [void]$actionCombo.Items.Add('Запустить программу / файл…')
                    [void]$actionCombo.Items.Add('Открыть папку…')
                    [void]$actionCombo.Items.Add('Выполнить команду…')
                    [void]$actionCombo.Items.Add('Открыть URL…')
                }
                else {
                    [void]$actionCombo.Items.Add('Launch program / file…')
                    [void]$actionCombo.Items.Add('Open folder…')
                    [void]$actionCombo.Items.Add('Run command…')
                    [void]$actionCombo.Items.Add('Open URL…')
                }
                [void]$state.ActionMap.Add('launch:configure')
                [void]$state.ActionMap.Add('folder:configure')
                [void]$state.ActionMap.Add('command:configure')
                [void]$state.ActionMap.Add('url:configure')

                $selectedIndex = 0
                for ($mapIndex = 0; $mapIndex -lt $state.ActionMap.Count; $mapIndex++) {
                    if ([string]$state.ActionMap[$mapIndex] -eq $currentAction) {
                        $selectedIndex = $mapIndex
                        break
                    }
                }
                $actionCombo.SelectedIndex = $selectedIndex
            }
            finally {
                $actionCombo.EndUpdate()
            }
        }
        finally {
            $state.SuppressCombo = $false
        }
    }

    $refreshSelectorStyles = {
        $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
        for ($i = 0; $i -lt $selectors.Count; $i++) {
            Set-ButtonIndicatorAppearance -Indicator $selectors[$i] -ButtonIndex $i
            $assigned = (
                $i -lt $pendingActions.Count -and
                -not [string]::IsNullOrWhiteSpace([string]$pendingActions[$i]) -and
                [string]$pendingActions[$i] -ne 'none'
            )
            $pressed = (
                @($script:LatestButtons).Count -gt $i -and
                [int]$script:LatestButtons[$i] -eq 0
            )
            if ($assigned -and -not $pressed) {
                $selectors[$i].ForeColor = $palette.Accent
            }
            if ($i -eq [int]$state.Selected) {
                $selectors[$i].BorderColor = $palette.Accent
            }
        }
    }

    $selectButton = {
        param([int]$Index)
        if ($Index -lt 0 -or $Index -ge $pendingActions.Count) { return }
        $state.Selected = $Index
        $selectedHeading.Text = if ($script:Language -eq 'ru') {
            'Выбрана кнопка ' + ($Index + 1)
        }
        else {
            'Selected button ' + ($Index + 1)
        }
        & $populateActionCombo
        & $refreshSelectorStyles

        foreach ($item in $assignmentList.Items) {
            if ([int]$item.Tag -eq $Index) {
                $item.Selected = $true
                $item.EnsureVisible()
                break
            }
        }
    }

    foreach ($selector in $selectors) {
        $selector.Add_Click({
            param($sender, $eventArgs)
            & $selectButton -Index ([int]$sender.Tag)
        })
    }

    $filterCombo.Add_SelectedIndexChanged({ & $refreshAssignmentList })
    $assignmentList.Add_SelectedIndexChanged({
        if ($assignmentList.SelectedItems.Count -eq 0) { return }
        & $selectButton -Index ([int]$assignmentList.SelectedItems[0].Tag)
    })

    $actionCombo.Add_SelectedIndexChanged({
        if ($state.SuppressCombo) { return }
        $selectedIndex = [int]$actionCombo.SelectedIndex
        if ($selectedIndex -lt 0 -or $selectedIndex -ge $state.ActionMap.Count) { return }

        $selectedAction = [string]$state.ActionMap[$selectedIndex]
        $index = [int]$state.Selected
        $configureActions = @(
            'virtual:xbox:configure',
            'hotkey:configure',
            'launch:configure',
            'folder:configure',
            'command:configure',
            'url:configure'
        )

        if ($selectedAction -notin $configureActions) {
            $pendingActions[$index] = $selectedAction
            & $refreshAssignmentList
            & $refreshSelectorStyles
            return
        }

        $previousAction = [string]$pendingActions[$index]
        $configuredAction = $null
        switch ($selectedAction) {
            'virtual:xbox:configure' {
                $configuredAction = Show-MugenVirtualGamepadButtonPicker -ExistingAction $previousAction -Owner $buttonForm
            }
            'hotkey:configure' { $configuredAction = Show-HotkeyEditor -ExistingAction $previousAction }
            'launch:configure' { $configuredAction = Select-LaunchTargetAction -ExistingAction $previousAction }
            'folder:configure' { $configuredAction = Select-FolderTargetAction -ExistingAction $previousAction }
            'command:configure' { $configuredAction = Show-CommandActionEditor -ExistingAction $previousAction }
            'url:configure' { $configuredAction = Show-UrlActionEditor -ExistingAction $previousAction }
        }

        if (-not [string]::IsNullOrWhiteSpace($configuredAction)) {
            $pendingActions[$index] = [string]$configuredAction
        }
        & $populateActionCombo
        & $refreshAssignmentList
        & $refreshSelectorStyles
    })

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(512, 570)
    $cancel.Size = [System.Drawing.Size]::new(105, 36)
    $buttonForm.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(628, 570)
    $save.Size = [System.Drawing.Size]::new(105, 36)
    $buttonForm.Controls.Add($save)

    $save.Add_Click({
        $script:ButtonActions = @($pendingActions)
        Save-ButtonActions
        if ($script:VirtualGamepadFeatureAvailable) {
            Set-MugenVirtualGamepadEnabled -Enabled ($virtualCombo.SelectedIndex -eq 1)
            [void](Sync-MugenVirtualGamepadState -Values @($script:LatestButtons))
        }
        $buttonForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $buttonForm.Close()
    })

    $liveButtonTimer = New-Object System.Windows.Forms.Timer
    $liveButtonTimer.Interval = 25
    $liveButtonTimer.Add_Tick({
        $latest = @($script:LatestButtons)
        $compareCount = [Math]::Min($latest.Count, $pendingActions.Count)
        for ($i = 0; $i -lt $compareCount; $i++) {
            $oldValue = if (@($state.LastButtons).Count -gt $i) { [int]$state.LastButtons[$i] } else { 1 }
            if ([int]$latest[$i] -eq 0 -and $oldValue -ne 0) {
                & $selectButton -Index $i
                break
            }
        }
        $state.LastButtons = @($latest)
        & $refreshSelectorStyles
    })

    Apply-ThemeToForm -Form $buttonForm
    $saveNotice.ForeColor = [System.Drawing.Color]::FromArgb(230, 170, 70)
    $selectorFlow.BackColor = $panel.BackColor
    & $refreshAssignmentList
    & $selectButton -Index 0

    $elapsedMs = [int](((Get-Date) - $buildStarted).TotalMilliseconds)
    Write-Log ('Large button settings UI prepared; buttons={0}; controlsCreated={1}; elapsedMs={2}' -f $script:DetectedButtonCount, $buttonForm.Controls.Count, $elapsedMs) 'INFO'

    $buttonForm.Add_Shown({
        Ensure-FormVisible -Form $buttonForm -CenterIfOffscreen
        $liveButtonTimer.Start()
    })
    $buttonForm.Add_FormClosed({
        $liveButtonTimer.Stop()
        $liveButtonTimer.Dispose()
    })
    $buttonForm.AcceptButton = $save
    $buttonForm.CancelButton = $cancel
    [void]$buttonForm.ShowDialog($form)
    $buttonForm.Dispose()
}

'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText 'function Show-ButtonSettings {' `
    -NewText ($largeEditor + "function Show-ButtonSettings {") `
    -Label 'insert optimized large button editor'

$dispatchOld = @'
function Show-ButtonSettings {
    if (
        -not $script:IsConnected -or
        $script:DetectedButtonCount -le 0
'@
$dispatchNew = @'
function Show-ButtonSettings {
    if ($script:IsConnected -and $script:DetectedButtonCount -gt 12) {
        Show-LargeButtonSettings
        return
    }

    if (
        -not $script:IsConnected -or
        $script:DetectedButtonCount -le 0
'@
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $dispatchOld `
    -NewText $dispatchNew `
    -Label 'dispatch large controllers to optimized editor'

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($resolved, $text, $utf8)
Write-Host "Applied optimized large-button settings editor to staged runtime: $resolved"
