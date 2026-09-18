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
        throw "Adaptive mappings patch '$Label' expected exactly one regex block match, found $($matches.Count)."
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
        throw "Adaptive mappings patch '$Label' expected exactly one literal match."
    }

    return $Text.Substring(0, $first) + $NewText + $Text.Substring($first + $OldText.Length)
}

$resolved = (Resolve-Path -LiteralPath $Path).Path
$text = [System.IO.File]::ReadAllText($resolved, [System.Text.Encoding]::UTF8)

# ---------------------------------------------------------------------------
# Persistent first-class toggle / encoder action state
# ---------------------------------------------------------------------------

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
$script:ButtonActionConfigPath = Join-Path $script:BaseDir 'button-actions.json'
$script:LegacyButtonActionConfigPath = Join-Path $script:BaseDir 'button-actions.dev.json'
'@ `
    -NewText @'
$script:ButtonActionConfigPath = Join-Path $script:BaseDir 'button-actions.json'
$script:LegacyButtonActionConfigPath = Join-Path $script:BaseDir 'button-actions.dev.json'
$script:AdaptiveActionConfigPath = Join-Path $script:BaseDir 'adaptive-actions.json'
$script:AdaptiveActionsLoaded = $false
$script:AdaptiveToggleActions = @()
$script:AdaptiveEncoderActions = @()
$script:AdaptiveSettingsButton = $null
'@ `
    -Label 'add Adaptive action config state'

$actionHelpers = @'
function Test-AdaptiveMappedAction {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'none') { return $true }
    if ($Action -match '^mute:\d+$') { return $true }
    if ($Action -in @(
        'media:playpause',
        'media:previous',
        'media:next',
        'media:stop',
        'system:volumeup',
        'system:volumedown',
        'system:volumemute'
    )) { return $true }

    if ($Action -match '^hotkey:(\d{1,3}):(\d{1,2})$') {
        $vk = [int]$Matches[1]
        $mask = [int]$Matches[2]
        return ($vk -gt 0 -and $vk -le 255 -and $mask -ge 0 -and $mask -le 15)
    }

    if ($Action -match '^(launch64|folder64|url64|command64):(.+)$') {
        $decoded = Decode-ButtonActionPayload -Payload $Matches[2]
        return (-not [string]::IsNullOrWhiteSpace($decoded))
    }

    return $false
}

function ConvertTo-SafeAdaptiveAction {
    param([string]$Action)
    if (Test-AdaptiveMappedAction -Action $Action) { return [string]$Action }
    return 'none'
}

function Read-AdaptiveActionConfigFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $data) { throw 'Adaptive action configuration is empty.' }
    if ($null -eq $data.PSObject.Properties['version'] -or [int]$data.version -ne 1) {
        throw 'Unsupported or missing Adaptive action configuration version.'
    }
    if ($null -eq $data.PSObject.Properties['toggles'] -or $null -eq $data.PSObject.Properties['encoders']) {
        throw 'Adaptive action configuration is missing control families.'
    }

    $toggles = @()
    foreach ($item in @($data.toggles)) {
        if ($null -eq $item) { throw 'Adaptive toggle action contains a null item.' }
        $on = ConvertTo-SafeAdaptiveAction -Action ([string]$item.on)
        $off = ConvertTo-SafeAdaptiveAction -Action ([string]$item.off)
        $toggles += [pscustomobject][ordered]@{ on = $on; off = $off }
    }

    $encoders = @()
    foreach ($item in @($data.encoders)) {
        if ($null -eq $item) { throw 'Adaptive encoder action contains a null item.' }
        $cw = ConvertTo-SafeAdaptiveAction -Action ([string]$item.cw)
        $ccw = ConvertTo-SafeAdaptiveAction -Action ([string]$item.ccw)
        $push = ConvertTo-SafeAdaptiveAction -Action ([string]$item.push)
        $encoders += [pscustomobject][ordered]@{ cw = $cw; ccw = $ccw; push = $push }
    }

    return [pscustomobject][ordered]@{
        version = 1
        toggles = @($toggles)
        encoders = @($encoders)
    }
}

function Write-AdaptiveActionConfigFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Toggles,
        [Parameter(Mandatory = $true)][object[]]$Encoders
    )

    $safeToggles = @()
    foreach ($item in @($Toggles)) {
        $safeToggles += [pscustomobject][ordered]@{
            on = ConvertTo-SafeAdaptiveAction -Action ([string]$item.on)
            off = ConvertTo-SafeAdaptiveAction -Action ([string]$item.off)
        }
    }

    $safeEncoders = @()
    foreach ($item in @($Encoders)) {
        $safeEncoders += [pscustomobject][ordered]@{
            cw = ConvertTo-SafeAdaptiveAction -Action ([string]$item.cw)
            ccw = ConvertTo-SafeAdaptiveAction -Action ([string]$item.ccw)
            push = ConvertTo-SafeAdaptiveAction -Action ([string]$item.push)
        }
    }

    $payload = [pscustomobject][ordered]@{
        version = 1
        toggles = @($safeToggles)
        encoders = @($safeEncoders)
    }

    $tempPath = "$Path.tmp-$PID"
    try {
        $json = $payload | ConvertTo-Json -Depth 8
        [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        $verified = Read-AdaptiveActionConfigFile -Path $tempPath
        if (@($verified.toggles).Count -ne @($safeToggles).Count -or @($verified.encoders).Count -ne @($safeEncoders).Count) {
            throw 'Adaptive action configuration failed count verification.'
        }

        if (Test-Path -LiteralPath $Path) {
            try { [System.IO.File]::Replace($tempPath, $Path, $null, $true) }
            catch {
                Copy-Item -LiteralPath $tempPath -Destination $Path -Force
                Remove-Item -LiteralPath $tempPath -Force
            }
        }
        else {
            [System.IO.File]::Move($tempPath, $Path)
        }
        [void](Read-AdaptiveActionConfigFile -Path $Path)
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Initialize-AdaptiveActions {
    if ($script:AdaptiveActionsLoaded) { return }
    $script:AdaptiveActionsLoaded = $true
    $script:AdaptiveToggleActions = @()
    $script:AdaptiveEncoderActions = @()

    if (-not (Test-Path -LiteralPath $script:AdaptiveActionConfigPath -PathType Leaf)) { return }

    try {
        $data = Read-AdaptiveActionConfigFile -Path $script:AdaptiveActionConfigPath
        $script:AdaptiveToggleActions = @($data.toggles)
        $script:AdaptiveEncoderActions = @($data.encoders)
        Write-Log ('Adaptive actions loaded: toggles={0}; encoders={1}' -f @($script:AdaptiveToggleActions).Count, @($script:AdaptiveEncoderActions).Count) 'DEBUG'
    }
    catch {
        Write-Log ('Failed to load Adaptive action config: {0}' -f $_.Exception.Message) 'WARN'
        $script:AdaptiveToggleActions = @()
        $script:AdaptiveEncoderActions = @()
    }
}

function Ensure-AdaptiveActionCapacity {
    param(
        [int]$ToggleCount = 0,
        [int]$EncoderCount = 0
    )

    Initialize-AdaptiveActions

    $toggles = @($script:AdaptiveToggleActions)
    while ($toggles.Count -lt $ToggleCount) {
        $toggles += [pscustomobject][ordered]@{ on = 'none'; off = 'none' }
    }
    $script:AdaptiveToggleActions = @($toggles)

    $encoders = @($script:AdaptiveEncoderActions)
    while ($encoders.Count -lt $EncoderCount) {
        $encoders += [pscustomobject][ordered]@{ cw = 'none'; ccw = 'none'; push = 'none' }
    }
    $script:AdaptiveEncoderActions = @($encoders)
}

function Save-AdaptiveActions {
    Write-AdaptiveActionConfigFile `
        -Path $script:AdaptiveActionConfigPath `
        -Toggles @($script:AdaptiveToggleActions) `
        -Encoders @($script:AdaptiveEncoderActions)

    Write-Log ('Adaptive actions saved: toggles={0}; encoders={1}' -f @($script:AdaptiveToggleActions).Count, @($script:AdaptiveEncoderActions).Count) 'INFO'
}

function Get-AdaptiveToggleMappedAction {
    param([int]$Index, [int]$State)
    Initialize-AdaptiveActions
    if ($Index -lt 0 -or $Index -ge @($script:AdaptiveToggleActions).Count) { return 'none' }
    if ($State -eq 1) { return ConvertTo-SafeAdaptiveAction -Action ([string]$script:AdaptiveToggleActions[$Index].on) }
    return ConvertTo-SafeAdaptiveAction -Action ([string]$script:AdaptiveToggleActions[$Index].off)
}

function Get-AdaptiveEncoderMappedAction {
    param([int]$Index, [ValidateSet('cw','ccw','push')][string]$Kind)
    Initialize-AdaptiveActions
    if ($Index -lt 0 -or $Index -ge @($script:AdaptiveEncoderActions).Count) { return 'none' }
    return ConvertTo-SafeAdaptiveAction -Action ([string]$script:AdaptiveEncoderActions[$Index].$Kind)
}

function Invoke-AdaptiveMappedAction {
    param(
        [string]$Action,
        [string]$Source = 'Adaptive control'
    )

    $Action = ConvertTo-SafeAdaptiveAction -Action $Action
    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'none') { return }

    if ($Action -match '^mute:(\d+)$') {
        $sliderIndex = [int]$Matches[1]
        if ($script:IsConnected -and $sliderIndex -ge 0 -and $sliderIndex -lt [int]$script:DetectedSliderCount) {
            Toggle-SliderSoftMute -SliderIndex $sliderIndex
        }
        return
    }

    if ($Action -match '^hotkey:(\d{1,3}):(\d{1,2})$') {
        try {
            $keyCode = [int]$Matches[1]
            $mask = [int]$Matches[2]
            [MugenDeejWindowing.MugenHotkeys]::Send(
                $keyCode,
                (($mask -band 1) -ne 0),
                (($mask -band 2) -ne 0),
                (($mask -band 4) -ne 0),
                (($mask -band 8) -ne 0)
            )
            Write-Log ('Adaptive action: {0}; hotkey={1}' -f $Source, (Get-HotkeyActionDisplay -Action $Action)) 'INFO'
        }
        catch { Write-Log ('Adaptive hotkey failed: {0}; error={1}' -f $Source, $_.Exception.Message) 'WARN' }
        return
    }

    if ($Action -match '^command64:(.+)$') {
        try { Invoke-RunCommandAction -Command (Decode-ButtonActionPayload -Payload $Matches[1]); Write-Log ('Adaptive action: {0}; run command' -f $Source) 'INFO' }
        catch { Write-Log ('Adaptive command failed: {0}; error={1}' -f $Source, $_.Exception.Message) 'WARN' }
        return
    }

    if ($Action -match '^launch64:(.+)$') {
        $target = Decode-ButtonActionPayload -Payload $Matches[1]
        try {
            if ([string]::IsNullOrWhiteSpace($target) -or -not (Test-Path -LiteralPath $target -PathType Leaf)) { throw ('Target file was not found: ' + $target) }
            Invoke-ShellButtonTarget -Target $target
            Write-Log ('Adaptive action: {0}; launch={1}' -f $Source, [System.IO.Path]::GetFileName($target)) 'INFO'
        }
        catch { Write-Log ('Adaptive launch failed: {0}; error={1}' -f $Source, $_.Exception.Message) 'WARN' }
        return
    }

    if ($Action -match '^folder64:(.+)$') {
        $target = Decode-ButtonActionPayload -Payload $Matches[1]
        try {
            if ([string]::IsNullOrWhiteSpace($target) -or -not (Test-Path -LiteralPath $target -PathType Container)) { throw ('Target folder was not found: ' + $target) }
            Invoke-ShellButtonTarget -Target $target
            Write-Log ('Adaptive action: {0}; folder={1}' -f $Source, $target) 'INFO'
        }
        catch { Write-Log ('Adaptive folder failed: {0}; error={1}' -f $Source, $_.Exception.Message) 'WARN' }
        return
    }

    if ($Action -match '^url64:(.+)$') {
        $target = Decode-ButtonActionPayload -Payload $Matches[1]
        try { Invoke-ShellButtonTarget -Target $target; Write-Log ('Adaptive action: {0}; URL' -f $Source) 'INFO' }
        catch { Write-Log ('Adaptive URL failed: {0}; error={1}' -f $Source, $_.Exception.Message) 'WARN' }
        return
    }

    try {
        switch ($Action) {
            'media:playpause' { [MugenDeejWindowing.MugenMediaKeys]::PlayPause(); break }
            'media:previous' { [MugenDeejWindowing.MugenMediaKeys]::PreviousTrack(); break }
            'media:next' { [MugenDeejWindowing.MugenMediaKeys]::NextTrack(); break }
            'media:stop' { [MugenDeejWindowing.MugenMediaKeys]::Stop(); break }
            'system:volumeup' { [MugenDeejWindowing.MugenMediaKeys]::VolumeUp(); break }
            'system:volumedown' { [MugenDeejWindowing.MugenMediaKeys]::VolumeDown(); break }
            'system:volumemute' { [MugenDeejWindowing.MugenMediaKeys]::VolumeMute(); break }
            default { return }
        }
        Write-Log ('Adaptive action: {0}; action={1}' -f $Source, $Action) 'INFO'
    }
    catch { Write-Log ('Adaptive fixed action failed: {0}; action={1}; error={2}' -f $Source, $Action, $_.Exception.Message) 'WARN' }
}

function Populate-AdaptiveActionCombo {
    param(
        [Parameter(Mandatory = $true)]$Combo,
        [Parameter(Mandatory = $true)]$Map,
        [string]$CurrentAction = 'none'
    )

    $CurrentAction = ConvertTo-SafeAdaptiveAction -Action $CurrentAction
    $Combo.BeginUpdate()
    try {
        $Combo.Items.Clear()
        $Map.Clear()

        [void]$Combo.Items.Add((Get-ButtonFeatureText -Key 'None'))
        [void]$Map.Add('none')

        $sliderCount = [Math]::Min([int]$script:DetectedSliderCount, @($script:Config.sliders).Count)
        for ($sliderIndex = 0; $sliderIndex -lt $sliderCount; $sliderIndex++) {
            $name = [string]$script:Config.sliders[$sliderIndex].name
            if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]($sliderIndex + 1) }
            [void]$Combo.Items.Add((Get-ButtonFeatureText -Key 'MuteControl') + ' ' + ($sliderIndex + 1) + ' — ' + $name)
            [void]$Map.Add(('mute:' + $sliderIndex))
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
            [void]$Combo.Items.Add((Get-ButtonFeatureText -Key $fixedAction[0]))
            [void]$Map.Add([string]$fixedAction[1])
        }

        if ($CurrentAction -match '^(hotkey:|launch64:|folder64:|command64:|url64:)') {
            [void]$Combo.Items.Add((Get-LargeButtonActionDisplay -Action $CurrentAction))
            [void]$Map.Add($CurrentAction)
        }

        [void]$Combo.Items.Add((Get-ButtonFeatureText -Key 'HotkeyConfigure'))
        [void]$Map.Add('hotkey:configure')
        if ($script:Language -eq 'ru') {
            [void]$Combo.Items.Add('Запустить программу / файл…')
            [void]$Combo.Items.Add('Открыть папку…')
            [void]$Combo.Items.Add('Выполнить команду…')
            [void]$Combo.Items.Add('Открыть URL…')
        }
        else {
            [void]$Combo.Items.Add('Launch program / file…')
            [void]$Combo.Items.Add('Open folder…')
            [void]$Combo.Items.Add('Run command…')
            [void]$Combo.Items.Add('Open URL…')
        }
        [void]$Map.Add('launch:configure')
        [void]$Map.Add('folder:configure')
        [void]$Map.Add('command:configure')
        [void]$Map.Add('url:configure')

        $selected = 0
        for ($i = 0; $i -lt $Map.Count; $i++) {
            if ([string]$Map[$i] -eq $CurrentAction) { $selected = $i; break }
        }
        $Combo.SelectedIndex = $selected
    }
    finally { $Combo.EndUpdate() }
}

function Resolve-AdaptiveConfiguredAction {
    param(
        [Parameter(Mandatory = $true)][string]$SelectedAction,
        [string]$PreviousAction = 'none'
    )

    switch ($SelectedAction) {
        'hotkey:configure' { return Show-HotkeyEditor -ExistingAction $PreviousAction }
        'launch:configure' { return Select-LaunchTargetAction -ExistingAction $PreviousAction }
        'folder:configure' { return Select-FolderTargetAction -ExistingAction $PreviousAction }
        'command:configure' { return Show-CommandActionEditor -ExistingAction $PreviousAction }
        'url:configure' { return Show-UrlActionEditor -ExistingAction $PreviousAction }
        default { return $SelectedAction }
    }
}

function Show-AdaptiveControlSettings {
    if (-not $script:IsConnected -or ([int]$script:DetectedToggleCount + [int]$script:DetectedEncoderCount) -le 0) { return }

    Ensure-AdaptiveActionCapacity -ToggleCount ([int]$script:DetectedToggleCount) -EncoderCount ([int]$script:DetectedEncoderCount)

    $pendingToggles = @()
    foreach ($item in @($script:AdaptiveToggleAct