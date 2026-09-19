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
    # Application profiles belong to the PC-side button mapping layer, not to
    # a firmware generation. Legacy simply has zero buttons; Extended and
    # Adaptive can both use the same Global/per-application editor.
    $profileUiEnabled = (
        $script:IsConnected -and
        [int]$script:DetectedButtonCount -gt 0
    )
    if (-not $profileUiEnabled) { return }

    $buildStarted = Get-Date
    Normalize-ButtonActions -Count $script:DetectedButtonCount
    Initialize-AdaptiveActions
    Initialize-AdaptiveProfiles

    $pendingActions = New-Object System.Collections.ArrayList
    foreach ($action in @($script:ButtonActions)) {
        [void]$pendingActions.Add([string]$action)
    }

    $workingProfiles = New-Object System.Collections.ArrayList
    foreach ($profile in @($script:AdaptiveProfiles)) {
        $buttons = @()
        if ($null -ne $profile.PSObject.Properties['buttons']) {
            $buttons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
        }
        [void]$workingProfiles.Add([pscustomobject][ordered]@{
            name = [string]$profile.name
            process = [string]$profile.process
            buttons = @($buttons)
            toggles = @(Copy-AdaptiveProfileToggles -Items @($profile.toggles))
            encoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
        })
    }

    $profileDrafts = @{}
    $profileState = [pscustomobject]@{
        Process = ''
        Suppress = $false
        Map = New-Object System.Collections.ArrayList
    }

    $pendingVirtualEnabled = $false
    if ($script:VirtualGamepadFeatureAvailable) {
        $pendingVirtualEnabled = Get-MugenVirtualGamepadEnabled
    }

    $buttonForm = New-Object System.Windows.Forms.Form
    $buttonForm.Text = Get-ButtonFeatureText -Key 'Title'
    $buttonForm.StartPosition = 'CenterParent'
    $dialogClientHeight = if ($profileUiEnabled) { 704 } else { 620 }
    $dialogOuterHeight = if ($profileUiEnabled) { 743 } else { 659 }
    $buttonForm.ClientSize = [System.Drawing.Size]::new(760, $dialogClientHeight)
    $buttonForm.MinimumSize = [System.Drawing.Size]::new(776, $dialogOuterHeight)
    $buttonForm.MaximumSize = [System.Drawing.Size]::new(776, $dialogOuterHeight)
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

    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = if ($script:Language -eq 'ru') { 'Профиль действий:' } else { 'Action profile:' }
    $profileLabel.Location = [System.Drawing.Point]::new(25, 139)
    $profileLabel.Size = [System.Drawing.Size]::new(145, 30)
    $profileLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $profileLabel.Visible = $profileUiEnabled
    $buttonForm.Controls.Add($profileLabel)

    $profileCombo = New-Object MugenDeejWindowing.MugenComboBox
    $profileCombo.DropDownStyle = 'DropDownList'
    $profileCombo.Location = [System.Drawing.Point]::new(170, 134)
    $profileCombo.Size = [System.Drawing.Size]::new(350, 30)
    $profileCombo.Visible = $profileUiEnabled
    $buttonForm.Controls.Add($profileCombo)

    $addProfileButton = New-Object MugenDeejWindowing.MugenButton
    $addProfileButton.Text = if ($script:Language -eq 'ru') { 'Добавить…' } else { 'Add…' }
    $addProfileButton.Location = [System.Drawing.Point]::new(532, 133)
    $addProfileButton.Size = [System.Drawing.Size]::new(203, 32)
    $addProfileButton.Visible = $profileUiEnabled
    $buttonForm.Controls.Add($addProfileButton)

    $profileHint = New-Object System.Windows.Forms.Label
    $profileHint.Text = if ($script:Language -eq 'ru') {
        'Общий профиль работает везде; профиль приложения включается автоматически, когда это приложение активно.'
    }
    else {
        'Global works everywhere; an application profile is selected automatically while that app is active.'
    }
    $profileHint.ForeColor = [System.Drawing.Color]::DimGray
    $profileHint.Location = [System.Drawing.Point]::new(25, 170)
    $profileHint.Size = [System.Drawing.Size]::new(710, 42)
    $profileHint.Visible = $profileUiEnabled
    $buttonForm.Controls.Add($profileHint)

    $virtualRowY = if ($profileUiEnabled) { 221 } else { 139 }
    $virtualComboY = if ($profileUiEnabled) { 216 } else { 134 }
    $virtualStatusY = if ($profileUiEnabled) { 255 } else { 173 }
    $panelY = if ($profileUiEnabled) { 290 } else { 208 }
    $actionButtonY = if ($profileUiEnabled) { 650 } else { 570 }

    $virtualLabel = New-Object System.Windows.Forms.Label
    $virtualLabel.Text = if ($script:Language -eq 'ru') { 'Виртуальный контроллер:' } else { 'Virtual controller:' }
    $virtualLabel.Location = [System.Drawing.Point]::new(25, $virtualRowY)
    $virtualLabel.Size = [System.Drawing.Size]::new(180, 28)
    $buttonForm.Controls.Add($virtualLabel)

    $virtualCombo = New-Object MugenDeejWindowing.MugenComboBox
    $virtualCombo.DropDownStyle = 'DropDownList'
    $virtualCombo.Location = [System.Drawing.Point]::new(210, $virtualComboY)
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
    $virtualStatus.Location = [System.Drawing.Point]::new(25, $virtualStatusY)
    $virtualStatus.Size = [System.Drawing.Size]::new(710, 28)
    $buttonForm.Controls.Add($virtualStatus)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = [System.Drawing.Point]::new(22, $panelY)
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

    $getProfileDraftKey = {
        param([string]$ProcessName)
        $normalized = Normalize-TargetName -Value $ProcessName
        if ([string]::IsNullOrWhiteSpace($normalized)) { return '__global__' }
        return $normalized.ToLowerInvariant()
    }

    $findWorkingProfile = {
        param([string]$ProcessName)
        $normalized = Normalize-TargetName -Value $ProcessName
        if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }
        foreach ($profile in @($workingProfiles)) {
            if ((Normalize-TargetName -Value ([string]$profile.process)) -ieq $normalized) { return $profile }
        }
        return $null
    }

    $captureCurrentProfileDraft = {
        if (-not $profileUiEnabled) { return }
        $key = & $getProfileDraftKey ([string]$profileState.Process)
        $profileDrafts[$key] = [pscustomobject][ordered]@{
            buttons = @(Copy-AdaptiveProfileButtons -Items @($pendingActions))
        }
    }

    $loadProfileDraft = {
        param([string]$ProcessName)
        if (-not $profileUiEnabled) { return }

        $normalized = Normalize-TargetName -Value $ProcessName
        $key = & $getProfileDraftKey $normalized
        $draft = $null

        if ($profileDrafts.ContainsKey($key)) {
            $draft = $profileDrafts[$key]
        }
        elseif ([string]::IsNullOrWhiteSpace($normalized)) {
            $draft = [pscustomobject][ordered]@{
                buttons = @(Copy-AdaptiveProfileButtons -Items @($script:ButtonActions))
            }
            $profileDrafts[$key] = $draft
        }
        else {
            $profile = & $findWorkingProfile $normalized
            if ($null -eq $profile) { return }

            $buttons = @()
            if ($null -ne $profile.PSObject.Properties['buttons']) {
                $buttons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
            }

            # Profiles created by #89 predate button mappings. They inherit the
            # current Global draft until this dialog explicitly saves buttons.
            if ($buttons.Count -eq 0) {
                if (-not $profileDrafts.ContainsKey('__global__')) {
                    $profileDrafts['__global__'] = [pscustomobject][ordered]@{
                        buttons = @(Copy-AdaptiveProfileButtons -Items @($script:ButtonActions))
                    }
                }
                $buttons = @(Copy-AdaptiveProfileButtons -Items @($profileDrafts['__global__'].buttons))
            }

            $draft = [pscustomobject][ordered]@{ buttons = @($buttons) }
            $profileDrafts[$key] = $draft
        }

        $pendingActions.Clear()
        foreach ($action in @($draft.buttons)) {
            [void]$pendingActions.Add((ConvertTo-SafeProfileButtonAction -Action ([string]$action)))
        }
        while ($pendingActions.Count -lt [int]$script:DetectedButtonCount) {
            [void]$pendingActions.Add('none')
        }

        $profileState.Process = $normalized
        if ([int]$state.Selected -ge $pendingActions.Count) { $state.Selected = 0 }
    }

    $populateProfileCombo = {
        param([string]$SelectProcess = '')
        if (-not $profileUiEnabled) { return }

        $selectedNormalized = Normalize-TargetName -Value $SelectProcess
        $profileState.Suppress = $true
        try {
            $profileCombo.BeginUpdate()
            try {
                $profileCombo.Items.Clear()
                $profileState.Map.Clear()

                [void]$profileCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Общий — для всех остальных приложений' } else { 'Global — all other applications' }))
                [void]$profileState.Map.Add('')

                foreach ($profile in @($workingProfiles | Sort-Object name)) {
                    $processName = Normalize-TargetName -Value ([string]$profile.process)
                    [void]$profileCombo.Items.Add(('{0}  ({1}.exe)' -f [string]$profile.name, $processName))
                    [void]$profileState.Map.Add($processName)
                }

                $selectedIndex = 0
                for ($i = 0; $i -lt $profileState.Map.Count; $i++) {
                    if ([string]$profileState.Map[$i] -ieq $selectedNormalized) {
                        $selectedIndex = $i
                        break
                    }
                }
                $profileCombo.SelectedIndex = $selectedIndex
            }
            finally {
                $profileCombo.EndUpdate()
            }
        }
        finally {
            $profileState.Suppress = $false
        }
    }

    $showAddProfileDialog = {
        if (-not $profileUiEnabled) { return '' }

        $existing = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($profile in @($workingProfiles)) {
            $name = Normalize-TargetName -Value ([string]$profile.process)
            if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$existing.Add($name) }
        }

        $runningProcesses = @(
            Get-RunningApplicationProcessNames |
            Where-Object { -not $existing.Contains((Normalize-TargetName -Value ([string]$_))) } |
            Sort-Object { Get-FriendlyProcessName -ProcessName $_ }
        )

        if ($runningProcesses.Count -eq 0) {
            [void](Show-MugenDeejStyledDialog -Message ($(if ($script:Language -eq 'ru') {
                'Не нашлось запущенного приложения без профиля. Запустите нужную программу и попробуйте снова.'
            } else {
                'No running application without a profile was found. Start the app you want and try again.'
            })) -Buttons 'OK' -Kind 'Info')
            return ''
        }

        $picker = New-Object System.Windows.Forms.Form
        $picker.Text = if ($script:Language -eq 'ru') { 'Добавить профиль приложения — Mugen Deej' } else { 'Add application profile — Mugen Deej' }
        $picker.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
        $picker.ClientSize = [System.Drawing.Size]::new(560, 220)
        $picker.MinimumSize = [System.Drawing.Size]::new(576, 259)
        $picker.MaximumSize = [System.Drawing.Size]::new(576, 259)
        $picker.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $picker.MaximizeBox = $false
        $picker.MinimizeBox = $false
        $picker.ShowInTaskbar = $false
        $picker.Font = $buttonForm.Font
        Set-FormAppIcon -Form $picker

        $pickerHeading = New-Object System.Windows.Forms.Label
        $pickerHeading.Text = if ($script:Language -eq 'ru') { 'Какому приложению нужен свой профиль?' } else { 'Which application needs its own profile?' }
        $pickerHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
        $pickerHeading.AutoSize = $true
        $pickerHeading.Location = [System.Drawing.Point]::new(20, 18)
        $picker.Controls.Add($pickerHeading)

        $pickerHint = New-Object System.Windows.Forms.Label
        $pickerHint.Text = if ($script:Language -eq 'ru') {
            'Новый профиль начнёт с копии текущих назначений Общего профиля.'
        }
        else {
            'The new profile starts as a copy of the current Global mappings.'
        }
        $pickerHint.ForeColor = [System.Drawing.Color]::DimGray
        $pickerHint.Location = [System.Drawing.Point]::new(22, 52)
        $pickerHint.Size = [System.Drawing.Size]::new(516, 30)
        $picker.Controls.Add($pickerHint)

        $pickerCombo = New-Object MugenDeejWindowing.MugenComboBox
        $pickerCombo.DropDownStyle = 'DropDownList'
        $pickerCombo.Location = [System.Drawing.Point]::new(22, 92)
        $pickerCombo.Size = [System.Drawing.Size]::new(516, 30)
        foreach ($processName in $runningProcesses) {
            [void]$pickerCombo.Items.Add(('{0}  ({1}.exe)' -f (Get-FriendlyProcessName -ProcessName $processName), $processName))
        }
        $pickerCombo.SelectedIndex = 0
        $picker.Controls.Add($pickerCombo)

        $pickerCancel = New-Object MugenDeejWindowing.MugenButton
        $pickerCancel.Text = Get-ButtonFeatureText -Key 'Cancel'
        $pickerCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $pickerCancel.Location = [System.Drawing.Point]::new(330, 164)
        $pickerCancel.Size = [System.Drawing.Size]::new(100, 36)
        $picker.Controls.Add($pickerCancel)

        $pickerAdd = New-Object MugenDeejWindowing.MugenButton
        $pickerAdd.Text = if ($script:Language -eq 'ru') { 'Добавить' } else { 'Add' }
        $pickerAdd.Tag = 'MugenPrimary'
        $pickerAdd.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $pickerAdd.Location = [System.Drawing.Point]::new(438, 164)
        $pickerAdd.Size = [System.Drawing.Size]::new(100, 36)
        $picker.Controls.Add($pickerAdd)

        Apply-ThemeToForm -Form $picker -ThemeName (Get-EffectiveTheme)
        $picker.Add_Shown({ Ensure-FormVisible -Form $picker -CenterIfOffscreen })
        $picker.AcceptButton = $pickerAdd
        $picker.CancelButton = $pickerCancel

        $result = $picker.ShowDialog($buttonForm)
        $chosen = if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            [string]$runningProcesses[[int]$pickerCombo.SelectedIndex]
        }
        else {
            ''
        }
        $picker.Dispose()
        return (Normalize-TargetName -Value $chosen)
    }

    if ($profileUiEnabled) {
        & $captureCurrentProfileDraft
        & $populateProfileCombo ''
        & $loadProfileDraft ''
    }

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
                    [void]$actionCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Выбрать управление геймпада…' } else { 'Choose gamepad control…' }))
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

    if ($profileUiEnabled) {
        $profileCombo.Add_SelectedIndexChanged({
            if ($profileState.Suppress) { return }
            $index = [int]$profileCombo.SelectedIndex
            if ($index -lt 0 -or $index -ge $profileState.Map.Count) { return }

            & $captureCurrentProfileDraft
            & $loadProfileDraft ([string]$profileState.Map[$index])
            & $refreshAssignmentList
            & $selectButton -Index ([int]$state.Selected)
        })

        $addProfileButton.Add_Click({
            & $captureCurrentProfileDraft
            $processName = [string](& $showAddProfileDialog)
            if ([string]::IsNullOrWhiteSpace($processName)) { return }

            $existingProfile = & $findWorkingProfile $processName
            if ($null -eq $existingProfile) {
                if (-not $profileDrafts.ContainsKey('__global__')) {
                    $profileDrafts['__global__'] = [pscustomobject][ordered]@{
                        buttons = @(Copy-AdaptiveProfileButtons -Items @($script:ButtonActions))
                    }
                }
                $globalButtons = @(Copy-AdaptiveProfileButtons -Items @($profileDrafts['__global__'].buttons))

                $profile = [pscustomobject][ordered]@{
                    name = (Get-FriendlyProcessName -ProcessName $processName)
                    process = $processName
                    buttons = @($globalButtons)
                    toggles = @(Copy-AdaptiveProfileToggles -Items @($script:AdaptiveToggleActions))
                    encoders = @(Copy-AdaptiveProfileEncoders -Items @($script:AdaptiveEncoderActions))
                }
                [void]$workingProfiles.Add($profile)

                $key = & $getProfileDraftKey $processName
                $profileDrafts[$key] = [pscustomobject][ordered]@{
                    buttons = @(Copy-AdaptiveProfileButtons -Items @($globalButtons))
                }
            }

            & $populateProfileCombo $processName
            & $loadProfileDraft $processName
            & $refreshAssignmentList
            & $selectButton -Index ([int]$state.Selected)
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
    $cancel.Location = [System.Drawing.Point]::new(512, $actionButtonY)
    $cancel.Size = [System.Drawing.Size]::new(105, 36)
    $buttonForm.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(628, $actionButtonY)
    $save.Size = [System.Drawing.Size]::new(105, 36)
    $buttonForm.Controls.Add($save)

    $save.Add_Click({
        if ($profileUiEnabled) {
            & $captureCurrentProfileDraft

            $globalDraft = $profileDrafts['__global__']
            $script:ButtonActions = @(Copy-AdaptiveProfileButtons -Items @($globalDraft.buttons))
            Save-ButtonActions

            foreach ($profile in @($workingProfiles)) {
                $key = & $getProfileDraftKey ([string]$profile.process)
                if ($profileDrafts.ContainsKey($key)) {
                    $profile.buttons = @(Copy-AdaptiveProfileButtons -Items @($profileDrafts[$key].buttons))
                }
            }

            $script:AdaptiveProfiles = @($workingProfiles)
            $script:AdaptiveProfilesLoaded = $true
            Save-AdaptiveProfiles
            Write-Log ('Button application-profile settings saved: profiles={0}; selected={1}' -f @($script:AdaptiveProfiles).Count, $(if ([string]::IsNullOrWhiteSpace([string]$profileState.Process)) { 'Global' } else { [string]$profileState.Process + '.exe' })) 'INFO'
        }
        else {
            $script:ButtonActions = @($pendingActions)
            Save-ButtonActions
        }

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
