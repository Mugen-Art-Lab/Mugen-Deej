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
# Mouse-wheel SendInput transport for Adaptive encoder actions
# ---------------------------------------------------------------------------

$mouseWheelHelper = @'
    public static class MugenMouseWheel
    {
        private const uint INPUT_MOUSE = 0;
        private const uint INPUT_KEYBOARD = 1;
        private const uint KEYEVENTF_KEYUP = 0x0002;
        private const uint MOUSEEVENTF_WHEEL = 0x0800;
        private const uint MOUSEEVENTF_HWHEEL = 0x01000;
        private const int WHEEL_DELTA = 120;

        private const ushort VK_CONTROL = 0x11;
        private const ushort VK_SHIFT = 0x10;
        private const ushort VK_MENU = 0x12;
        private const ushort VK_LWIN = 0x5B;

        [System.Runtime.InteropServices.StructLayout(
            System.Runtime.InteropServices.LayoutKind.Sequential
        )]
        private struct INPUT
        {
            public uint type;
            public InputUnion U;
        }

        [System.Runtime.InteropServices.StructLayout(
            System.Runtime.InteropServices.LayoutKind.Explicit
        )]
        private struct InputUnion
        {
            [System.Runtime.InteropServices.FieldOffset(0)]
            public MOUSEINPUT mi;

            [System.Runtime.InteropServices.FieldOffset(0)]
            public KEYBDINPUT ki;
        }

        [System.Runtime.InteropServices.StructLayout(
            System.Runtime.InteropServices.LayoutKind.Sequential
        )]
        private struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [System.Runtime.InteropServices.StructLayout(
            System.Runtime.InteropServices.LayoutKind.Sequential
        )]
        private struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public UIntPtr time;
            public IntPtr dwExtraInfo;
        }

        [System.Runtime.InteropServices.DllImport(
            "user32.dll",
            SetLastError = true
        )]
        private static extern uint SendInput(
            uint nInputs,
            INPUT[] pInputs,
            int cbSize
        );

        private static INPUT KeyInput(ushort vk, bool keyUp)
        {
            INPUT input = new INPUT();
            input.type = INPUT_KEYBOARD;
            input.U.ki = new KEYBDINPUT
            {
                wVk = vk,
                wScan = 0,
                dwFlags = keyUp ? KEYEVENTF_KEYUP : 0,
                time = UIntPtr.Zero,
                dwExtraInfo = IntPtr.Zero
            };
            return input;
        }

        private static INPUT WheelInput(int delta, bool horizontal)
        {
            INPUT input = new INPUT();
            input.type = INPUT_MOUSE;
            input.U.mi = new MOUSEINPUT
            {
                dx = 0,
                dy = 0,
                mouseData = unchecked((uint)delta),
                dwFlags = horizontal ? MOUSEEVENTF_HWHEEL : MOUSEEVENTF_WHEEL,
                time = 0,
                dwExtraInfo = IntPtr.Zero
            };
            return input;
        }

        public static void Scroll(
            int steps,
            bool horizontal,
            bool ctrl,
            bool shift,
            bool alt,
            bool win
        )
        {
            if (steps == 0)
                return;

            if (steps < -32 || steps > 32)
                throw new ArgumentOutOfRangeException("steps");

            var inputs = new System.Collections.Generic.List<INPUT>();

            if (ctrl) inputs.Add(KeyInput(VK_CONTROL, false));
            if (shift) inputs.Add(KeyInput(VK_SHIFT, false));
            if (alt) inputs.Add(KeyInput(VK_MENU, false));
            if (win) inputs.Add(KeyInput(VK_LWIN, false));

            inputs.Add(WheelInput(steps * WHEEL_DELTA, horizontal));

            if (win) inputs.Add(KeyInput(VK_LWIN, true));
            if (alt) inputs.Add(KeyInput(VK_MENU, true));
            if (shift) inputs.Add(KeyInput(VK_SHIFT, true));
            if (ctrl) inputs.Add(KeyInput(VK_CONTROL, true));

            INPUT[] packet = inputs.ToArray();
            uint sent = SendInput(
                (uint)packet.Length,
                packet,
                System.Runtime.InteropServices.Marshal.SizeOf(typeof(INPUT))
            );

            if (sent != packet.Length)
            {
                int error =
                    System.Runtime.InteropServices.Marshal.GetLastWin32Error();

                throw new System.ComponentModel.Win32Exception(
                    error,
                    "SendInput did not send the complete mouse-wheel action."
                );
            }
        }
    }
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText '    public static class MugenFolderPicker' `
    -NewText ($mouseWheelHelper + '    public static class MugenFolderPicker') `
    -Label 'add mouse-wheel SendInput helper'

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
$script:AdaptiveProfileConfigPath = Join-Path $script:BaseDir 'adaptive-profiles.json'
$script:AdaptiveActionsLoaded = $false
$script:AdaptiveToggleActions = @()
$script:AdaptiveEncoderActions = @()
$script:AdaptiveProfilesLoaded = $false
$script:AdaptiveProfiles = @()
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
        'system:volumemute',
        'mouse:wheelup',
        'mouse:wheeldown',
        'mouse:hwheelleft',
        'mouse:hwheelright',
        'mouse:ctrlwheelup',
        'mouse:ctrlwheeldown',
        'mouse:shiftwheelup',
        'mouse:shiftwheeldown',
        'mouse:altwheelup',
        'mouse:altwheeldown'
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
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Toggles,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Encoders
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

function Test-ProfileButtonAction {
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

    if ($script:VirtualGamepadFeatureAvailable -and (Test-MugenVirtualGamepadAction -Action $Action)) { return $true }

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

function ConvertTo-SafeProfileButtonAction {
    param([string]$Action)
    if (Test-ProfileButtonAction -Action $Action) { return [string]$Action }
    return 'none'
}

function Copy-AdaptiveProfileButtons {
    param([object[]]$Items)
    $copy = @()
    foreach ($item in @($Items)) {
        $copy += ConvertTo-SafeProfileButtonAction -Action ([string]$item)
    }
    return $copy
}

function Get-ProfiledButtonActionContext {
    Initialize-ButtonActions

    $globalActions = @($script:ButtonActions | ForEach-Object { [string]$_ })
    $globalContext = [pscustomobject][ordered]@{
        Key = '__global__'
        Actions = @($globalActions)
    }

    # Button application profiles are protocol-agnostic. Legacy exposes no
    # momentary buttons, while Extended and Adaptive use the same established
    # button-action transport. With no matching profile (or an older profile
    # that has no button payload), Global remains the exact compatibility path.
    $profile = Get-ForegroundAdaptiveProfile
    if ($null -eq $profile) { return $globalContext }

    $profileButtons = @()
    if ($null -ne $profile.PSObject.Properties['buttons']) {
        $profileButtons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
    }

    # #89 profiles did not contain button mappings. Empty/missing means inherit
    # Global until the user explicitly edits/saves button mappings for that app.
    if ($profileButtons.Count -eq 0) { return $globalContext }

    $processName = Normalize-TargetName -Value ([string]$profile.process)
    if ([string]::IsNullOrWhiteSpace($processName)) { return $globalContext }

    return [pscustomobject][ordered]@{
        Key = $processName.ToLowerInvariant()
        Actions = @($profileButtons)
    }
}

function Get-ProfiledButtonAction {
    param([int]$ButtonIndex)

    if ($ButtonIndex -lt 0) { return 'none' }
    $context = Get-ProfiledButtonActionContext
    $actions = @($context.Actions)
    if ($ButtonIndex -ge $actions.Count) { return 'none' }

    return ConvertTo-SafeProfileButtonAction -Action ([string]$actions[$ButtonIndex])
}

function Copy-AdaptiveProfileToggles {
    param([object[]]$Items)
    $copy = @()
    foreach ($item in @($Items)) {
        $copy += [pscustomobject][ordered]@{
            on = ConvertTo-SafeAdaptiveAction -Action ([string]$item.on)
            off = ConvertTo-SafeAdaptiveAction -Action ([string]$item.off)
        }
    }
    return $copy
}

function Copy-AdaptiveProfileEncoders {
    param([object[]]$Items)
    $copy = @()
    foreach ($item in @($Items)) {
        $copy += [pscustomobject][ordered]@{
            cw = ConvertTo-SafeAdaptiveAction -Action ([string]$item.cw)
            ccw = ConvertTo-SafeAdaptiveAction -Action ([string]$item.ccw)
            push = ConvertTo-SafeAdaptiveAction -Action ([string]$item.push)
        }
    }
    return $copy
}

function Initialize-AdaptiveProfiles {
    if ($script:AdaptiveProfilesLoaded) { return }
    $script:AdaptiveProfilesLoaded = $true
    $script:AdaptiveProfiles = @()

    if (-not (Test-Path -LiteralPath $script:AdaptiveProfileConfigPath -PathType Leaf)) { return }

    try {
        $data = Get-Content -LiteralPath $script:AdaptiveProfileConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $data -or $null -eq $data.PSObject.Properties['version'] -or [int]$data.version -ne 1) {
            throw 'Unsupported or missing Adaptive profile configuration version.'
        }

        $profiles = @()
        foreach ($raw in @($data.profiles)) {
            if ($null -eq $raw) { continue }
            $processName = Normalize-TargetName -Value ([string]$raw.process)
            if ([string]::IsNullOrWhiteSpace($processName)) { continue }

            $name = [string]$raw.name
            if ([string]::IsNullOrWhiteSpace($name)) { $name = Get-FriendlyProcessName -ProcessName $processName }

            $buttons = @()
            if ($null -ne $raw.PSObject.Properties['buttons']) {
                $buttons = @(Copy-AdaptiveProfileButtons -Items @($raw.buttons))
            }

            $profiles += [pscustomobject][ordered]@{
                name = $name
                process = $processName
                buttons = @($buttons)
                toggles = @(Copy-AdaptiveProfileToggles -Items @($raw.toggles))
                encoders = @(Copy-AdaptiveProfileEncoders -Items @($raw.encoders))
            }
        }
        $script:AdaptiveProfiles = @($profiles)
        Write-Log ('Adaptive application profiles loaded: {0}' -f $script:AdaptiveProfiles.Count) 'INFO'
    }
    catch {
        $script:AdaptiveProfiles = @()
        Write-Log ('Failed to load Adaptive application profiles: {0}' -f $_.Exception.Message) 'WARN'
    }
}

function Save-AdaptiveProfiles {
    Initialize-AdaptiveProfiles

    $profiles = @()
    foreach ($profile in @($script:AdaptiveProfiles)) {
        $buttons = @()
        if ($null -ne $profile.PSObject.Properties['buttons']) {
            $buttons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
        }

        $profiles += [pscustomobject][ordered]@{
            name = [string]$profile.name
            process = Normalize-TargetName -Value ([string]$profile.process)
            buttons = @($buttons)
            toggles = @(Copy-AdaptiveProfileToggles -Items @($profile.toggles))
            encoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
        }
    }

    $payload = [pscustomobject][ordered]@{ version = 1; profiles = @($profiles) }
    $tempPath = $script:AdaptiveProfileConfigPath + '.tmp-' + $PID

    try {
        $json = $payload | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        $verify = Get-Content -LiteralPath $tempPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $verify -or [int]$verify.version -ne 1) { throw 'Adaptive profile verification failed.' }

        if (Test-Path -LiteralPath $script:AdaptiveProfileConfigPath) {
            try { [System.IO.File]::Replace($tempPath, $script:AdaptiveProfileConfigPath, $null, $true) }
            catch {
                Copy-Item -LiteralPath $tempPath -Destination $script:AdaptiveProfileConfigPath -Force
                Remove-Item -LiteralPath $tempPath -Force
            }
        }
        else {
            [System.IO.File]::Move($tempPath, $script:AdaptiveProfileConfigPath)
        }
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
        throw
    }
}

function Get-AdaptiveProfileForProcess {
    param([AllowEmptyString()][string]$ProcessName)

    Initialize-AdaptiveProfiles
    $normalized = Normalize-TargetName -Value $ProcessName
    if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }

    foreach ($profile in @($script:AdaptiveProfiles)) {
        if ((Normalize-TargetName -Value ([string]$profile.process)) -ieq $normalized) { return $profile }
    }
    return $null
}

function Get-ForegroundAdaptiveProfile {
    Initialize-AdaptiveProfiles

    try {
        $processName = Normalize-TargetName -Value ([MugenDeejWindowing.Foreground]::GetForegroundProcessName())
        if ([string]::IsNullOrWhiteSpace($processName)) { return $null }

        $selfName = Normalize-TargetName -Value ([System.Diagnostics.Process]::GetCurrentProcess().ProcessName)
        if ($processName -ieq $selfName -or $processName -ieq 'powershell' -or $processName -ieq 'pwsh') {
            return $null
        }

        return Get-AdaptiveProfileForProcess -ProcessName $processName
    }
    catch {
        return $null
    }
}

function Save-AdaptiveActions {
    Write-AdaptiveActionConfigFile -Path $script:AdaptiveActionConfigPath -Toggles @($script:AdaptiveToggleActions) -Encoders @($script:AdaptiveEncoderActions)
    Write-Log ('Adaptive actions saved: toggles={0}; encoders={1}' -f @($script:AdaptiveToggleActions).Count, @($script:AdaptiveEncoderActions).Count) 'INFO'
}

function Get-AdaptiveToggleMappedAction {
    param([int]$Index, [int]$State)

    Initialize-AdaptiveActions
    $profile = Get-ForegroundAdaptiveProfile
    $source = @(if ($null -ne $profile) { @($profile.toggles) } else { @($script:AdaptiveToggleActions) })

    if ($Index -lt 0 -or $Index -ge $source.Count) { return 'none' }
    if ($State -eq 1) { return ConvertTo-SafeAdaptiveAction -Action ([string]$source[$Index].on) }
    return ConvertTo-SafeAdaptiveAction -Action ([string]$source[$Index].off)
}

function Get-AdaptiveEncoderMappedAction {
    param([int]$Index, [ValidateSet('cw','ccw','push')][string]$Kind)

    Initialize-AdaptiveActions
    $profile = Get-ForegroundAdaptiveProfile
    $source = @(if ($null -ne $profile) { @($profile.encoders) } else { @($script:AdaptiveEncoderActions) })

    if ($Index -lt 0 -or $Index -ge $source.Count) { return 'none' }
    return ConvertTo-SafeAdaptiveAction -Action ([string]$source[$Index].$Kind)
}

function Invoke-AdaptiveMappedAction {
    param(
        [string]$Action,
        [string]$Source = 'Adaptive control'
    )

    if (Test-MugenInputActionsSuspended) {
        Write-Log ('Adaptive mapped action suppressed while a modal Mugen dialog is open: {0}' -f $Source) 'DEBUG'
        return
    }

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
            'mouse:wheelup' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(1, $false, $false, $false, $false, $false); break }
            'mouse:wheeldown' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(-1, $false, $false, $false, $false, $false); break }
            'mouse:hwheelleft' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(-1, $true, $false, $false, $false, $false); break }
            'mouse:hwheelright' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(1, $true, $false, $false, $false, $false); break }
            'mouse:ctrlwheelup' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(1, $false, $true, $false, $false, $false); break }
            'mouse:ctrlwheeldown' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(-1, $false, $true, $false, $false, $false); break }
            'mouse:shiftwheelup' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(1, $false, $false, $true, $false, $false); break }
            'mouse:shiftwheeldown' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(-1, $false, $false, $true, $false, $false); break }
            'mouse:altwheelup' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(1, $false, $false, $false, $true, $false); break }
            'mouse:altwheeldown' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(-1, $false, $false, $false, $true, $false); break }
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

        $mouseActions = if ($script:Language -eq 'ru') {
            @(
                @('Колесо мыши ↑', 'mouse:wheelup'),
                @('Колесо мыши ↓', 'mouse:wheeldown'),
                @('Горизонтальная прокрутка ←', 'mouse:hwheelleft'),
                @('Горизонтальная прокрутка →', 'mouse:hwheelright'),
                @('Ctrl + колесо ↑', 'mouse:ctrlwheelup'),
                @('Ctrl + колесо ↓', 'mouse:ctrlwheeldown'),
                @('Shift + колесо ↑', 'mouse:shiftwheelup'),
                @('Shift + колесо ↓', 'mouse:shiftwheeldown'),
                @('Alt + колесо ↑', 'mouse:altwheelup'),
                @('Alt + колесо ↓', 'mouse:altwheeldown')
            )
        }
        else {
            @(
                @('Mouse wheel ↑', 'mouse:wheelup'),
                @('Mouse wheel ↓', 'mouse:wheeldown'),
                @('Horizontal scroll ←', 'mouse:hwheelleft'),
                @('Horizontal scroll →', 'mouse:hwheelright'),
                @('Ctrl + wheel ↑', 'mouse:ctrlwheelup'),
                @('Ctrl + wheel ↓', 'mouse:ctrlwheeldown'),
                @('Shift + wheel ↑', 'mouse:shiftwheelup'),
                @('Shift + wheel ↓', 'mouse:shiftwheeldown'),
                @('Alt + wheel ↑', 'mouse:altwheelup'),
                @('Alt + wheel ↓', 'mouse:altwheeldown')
            )
        }
        foreach ($mouseAction in $mouseActions) {
            [void]$Combo.Items.Add([string]$mouseAction[0])
            [void]$Map.Add([string]$mouseAction[1])
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

function Get-AdaptiveActionDisplay {
    param([string]$Action)

    $Action = ConvertTo-SafeAdaptiveAction -Action $Action
    $ru = ($script:Language -eq 'ru')

    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'none') {
        return (Get-ButtonFeatureText -Key 'None')
    }

    if ($Action -match '^mute:(\d+)$') {
        $sliderIndex = [int]$Matches[1]
        $name = ''
        if ($sliderIndex -ge 0 -and $sliderIndex -lt @($script:Config.sliders).Count) {
            $name = [string]$script:Config.sliders[$sliderIndex].name
        }
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = [string]($sliderIndex + 1)
        }
        return ((Get-ButtonFeatureText -Key 'MuteControl') + ' ' + ($sliderIndex + 1) + ' — ' + $name)
    }

    switch ($Action) {
        'media:playpause' { return (Get-ButtonFeatureText -Key 'PlayPause') }
        'media:previous' { return (Get-ButtonFeatureText -Key 'PreviousTrack') }
        'media:next' { return (Get-ButtonFeatureText -Key 'NextTrack') }
        'media:stop' { return (Get-ButtonFeatureText -Key 'StopPlayback') }
        'system:volumeup' { return (Get-ButtonFeatureText -Key 'VolumeUp') }
        'system:volumedown' { return (Get-ButtonFeatureText -Key 'VolumeDown') }
        'system:volumemute' { return (Get-ButtonFeatureText -Key 'VolumeMute') }
        'mouse:wheelup' { return $(if ($ru) { 'Колесо мыши ↑' } else { 'Mouse wheel ↑' }) }
        'mouse:wheeldown' { return $(if ($ru) { 'Колесо мыши ↓' } else { 'Mouse wheel ↓' }) }
        'mouse:hwheelleft' { return $(if ($ru) { 'Горизонтальная прокрутка ←' } else { 'Horizontal scroll ←' }) }
        'mouse:hwheelright' { return $(if ($ru) { 'Горизонтальная прокрутка →' } else { 'Horizontal scroll →' }) }
        'mouse:ctrlwheelup' { return ('Ctrl + ' + $(if ($ru) { 'колесо ↑' } else { 'wheel ↑' })) }
        'mouse:ctrlwheeldown' { return ('Ctrl + ' + $(if ($ru) { 'колесо ↓' } else { 'wheel ↓' })) }
        'mouse:shiftwheelup' { return ('Shift + ' + $(if ($ru) { 'колесо ↑' } else { 'wheel ↑' })) }
        'mouse:shiftwheeldown' { return ('Shift + ' + $(if ($ru) { 'колесо ↓' } else { 'wheel ↓' })) }
        'mouse:altwheelup' { return ('Alt + ' + $(if ($ru) { 'колесо ↑' } else { 'wheel ↑' })) }
        'mouse:altwheeldown' { return ('Alt + ' + $(if ($ru) { 'колесо ↓' } else { 'wheel ↓' })) }
    }

    if ($Action -match '^hotkey:') { return (Get-HotkeyActionDisplay -Action $Action) }
    if ($Action -match '^launch64:') { return (Get-LaunchActionDisplay -Action $Action) }
    if ($Action -match '^folder64:') { return (Get-FolderActionDisplay -Action $Action) }
    if ($Action -match '^command64:') { return (Get-CommandActionDisplay -Action $Action) }
    if ($Action -match '^url64:') { return (Get-UrlActionDisplay -Action $Action) }

    return $Action
}

function Show-AdaptiveControlSettings {
    if (-not $script:IsConnected -or ([int]$script:DetectedToggleCount + [int]$script:DetectedEncoderCount) -le 0) { return }

    Ensure-AdaptiveActionCapacity -ToggleCount ([int]$script:DetectedToggleCount) -EncoderCount ([int]$script:DetectedEncoderCount)

    Initialize-AdaptiveProfiles
    Initialize-ButtonActions

    $pendingToggles = New-Object System.Collections.ArrayList
    foreach ($item in @($script:AdaptiveToggleActions)) {
        [void]$pendingToggles.Add([pscustomobject][ordered]@{ on = [string]$item.on; off = [string]$item.off })
    }
    $pendingEncoders = New-Object System.Collections.ArrayList
    foreach ($item in @($script:AdaptiveEncoderActions)) {
        [void]$pendingEncoders.Add([pscustomobject][ordered]@{ cw = [string]$item.cw; ccw = [string]$item.ccw; push = [string]$item.push })
    }

    $workingProfiles = New-Object System.Collections.ArrayList
    foreach ($profile in @($script:AdaptiveProfiles)) {
        $profileButtons = @()
        if ($null -ne $profile.PSObject.Properties['buttons']) {
            $profileButtons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
        }

        [void]$workingProfiles.Add([pscustomobject][ordered]@{
            name = [string]$profile.name
            process = [string]$profile.process
            buttons = @($profileButtons)
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

    $settingsForm = New-Object System.Windows.Forms.Form
    $settingsForm.Text = if ($script:Language -eq 'ru') { 'Настройка тумблеров и энкодеров — Mugen Deej' } else { 'Toggle and encoder settings — Mugen Deej' }
    $settingsForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $settingsForm.ClientSize = [System.Drawing.Size]::new(820, 796)
    $settingsForm.MinimumSize = [System.Drawing.Size]::new(836, 835)
    $settingsForm.MaximumSize = [System.Drawing.Size]::new(836, 835)
    $settingsForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $settingsForm.MaximizeBox = $false
    $settingsForm.MinimizeBox = $false
    $settingsForm.Font = $form.Font
    Set-FormAppIcon -Form $settingsForm

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = if ($script:Language -eq 'ru') { 'Настройка тумблеров и энкодеров' } else { 'Toggle and encoder settings' }
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $settingsForm.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = if ($script:Language -eq 'ru') {
        'Выберите орган управления слева или используйте его на контроллере.' + "`r`n" +
        'Тумблер — ВКЛ/ВЫКЛ; модификатор — слой; энкодер — влево/вправо и нажатие.'
    }
    else {
        'Choose a control on the left or use it on the controller.' + "`r`n" +
        'Toggle — ON/OFF; modifier — layer; encoder — left/right and push.'
    }
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = [System.Drawing.Point]::new(25, 56)
    $hint.Size = [System.Drawing.Size]::new(770, 44)
    $settingsForm.Controls.Add($hint)

    $saveNotice = New-Object System.Windows.Forms.Label
    $saveNotice.Text = if ($script:Language -eq 'ru') { 'Изменения начнут работать только после нажатия «Сохранить».' } else { 'Changes take effect only after you click Save.' }
    $saveNotice.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $saveNotice.ForeColor = [System.Drawing.Color]::FromArgb(230, 170, 70)
    $saveNotice.Location = [System.Drawing.Point]::new(25, 102)
    $saveNotice.Size = [System.Drawing.Size]::new(770, 26)
    $settingsForm.Controls.Add($saveNotice)

    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = if ($script:Language -eq 'ru') { 'Профиль действий:' } else { 'Action profile:' }
    $profileLabel.Location = [System.Drawing.Point]::new(25, 143)
    $profileLabel.Size = [System.Drawing.Size]::new(145, 30)
    $profileLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $settingsForm.Controls.Add($profileLabel)

    $profileCombo = New-Object MugenDeejWindowing.MugenComboBox
    $profileCombo.DropDownStyle = 'DropDownList'
    $profileCombo.Location = [System.Drawing.Point]::new(170, 140)
    $profileCombo.Size = [System.Drawing.Size]::new(410, 30)
    $settingsForm.Controls.Add($profileCombo)

    $addProfileButton = New-Object MugenDeejWindowing.MugenButton
    $addProfileButton.Text = if ($script:Language -eq 'ru') { 'Добавить…' } else { 'Add…' }
    $addProfileButton.Location = [System.Drawing.Point]::new(592, 139)
    $addProfileButton.Size = [System.Drawing.Size]::new(206, 32)
    $settingsForm.Controls.Add($addProfileButton)

    $profileHint = New-Object System.Windows.Forms.Label
    $profileHint.Text = if ($script:Language -eq 'ru') {
        'Общий профиль работает везде; профиль приложения включается автоматически, когда это приложение активно.'
    }
    else {
        'Global works everywhere; an application profile is selected automatically while that app is active.'
    }
    $profileHint.ForeColor = [System.Drawing.Color]::DimGray
    $profileHint.Location = [System.Drawing.Point]::new(25, 173)
    $profileHint.Size = [System.Drawing.Size]::new(770, 28)
    $settingsForm.Controls.Add($profileHint)

    $selectorGroup = New-Object MugenDeejWindowing.MugenGroupBox
    $selectorGroup.Text = if ($script:Language -eq 'ru') { 'Органы управления' } else { 'Physical controls' }
    $selectorGroup.Location = [System.Drawing.Point]::new(22, 202)
    $selectorGroup.Size = [System.Drawing.Size]::new(248, 516)
    $settingsForm.Controls.Add($selectorGroup)

    $selectorFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $selectorFlow.Location = [System.Drawing.Point]::new(12, 30)
    $selectorFlow.Size = [System.Drawing.Size]::new(224, 472)
    $selectorFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $selectorFlow.WrapContents = $true
    $selectorFlow.AutoScroll = $true
    $selectorGroup.Controls.Add($selectorFlow)

    $editorGroup = New-Object MugenDeejWindowing.MugenGroupBox
    $editorGroup.Text = if ($script:Language -eq 'ru') { 'Выбранный орган управления' } else { 'Selected control' }
    $editorGroup.Location = [System.Drawing.Point]::new(282, 202)
    $editorGroup.Size = [System.Drawing.Size]::new(516, 516)
    $settingsForm.Controls.Add($editorGroup)

    $selectedHeading = New-Object System.Windows.Forms.Label
    $selectedHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    $selectedHeading.Location = [System.Drawing.Point]::new(18, 32)
    $selectedHeading.Size = [System.Drawing.Size]::new(480, 30)
    $editorGroup.Controls.Add($selectedHeading)

    $liveState = New-Object System.Windows.Forms.Label
    $liveState.ForeColor = [System.Drawing.Color]::DimGray
    $liveState.Location = [System.Drawing.Point]::new(18, 63)
    $liveState.Size = [System.Drawing.Size]::new(480, 28)
    $editorGroup.Controls.Add($liveState)

    $row1Label = New-Object System.Windows.Forms.Label
    $row1Label.Location = [System.Drawing.Point]::new(18, 112)
    $row1Label.Size = [System.Drawing.Size]::new(150, 26)
    $editorGroup.Controls.Add($row1Label)
    $row1Combo = New-Object MugenDeejWindowing.MugenComboBox
    $row1Combo.DropDownStyle = 'DropDownList'
    $row1Combo.Location = [System.Drawing.Point]::new(174, 108)
    $row1Combo.Size = [System.Drawing.Size]::new(320, 30)
    $editorGroup.Controls.Add($row1Combo)

    $row2Label = New-Object System.Windows.Forms.Label
    $row2Label.Location = [System.Drawing.Point]::new(18, 164)
    $row2Label.Size = [System.Drawing.Size]::new(150, 26)
    $editorGroup.Controls.Add($row2Label)
    $row2Combo = New-Object MugenDeejWindowing.MugenComboBox
    $row2Combo.DropDownStyle = 'DropDownList'
    $row2Combo.Location = [System.Drawing.Point]::new(174, 160)
    $row2Combo.Size = [System.Drawing.Size]::new(320, 30)
    $editorGroup.Controls.Add($row2Combo)

    $row3Label = New-Object System.Windows.Forms.Label
    $row3Label.Location = [System.Drawing.Point]::new(18, 216)
    $row3Label.Size = [System.Drawing.Size]::new(150, 26)
    $editorGroup.Controls.Add($row3Label)
    $row3Combo = New-Object MugenDeejWindowing.MugenComboBox
    $row3Combo.DropDownStyle = 'DropDownList'
    $row3Combo.Location = [System.Drawing.Point]::new(174, 212)
    $row3Combo.Size = [System.Drawing.Size]::new(320, 30)
    $editorGroup.Controls.Add($row3Combo)

    $editorHint = New-Object System.Windows.Forms.Label
    $editorHint.Text = if ($script:Language -eq 'ru') {
        'Каждый шаг поворота энкодера выполняет назначенное действие один раз. Точка • означает, что энкодер можно ещё и нажать.'
    }
    else {
        'Each encoder step runs the assigned action once. A • means the encoder can also be pressed.'
    }
    $editorHint.ForeColor = [System.Drawing.Color]::DimGray
    $editorHint.Location = [System.Drawing.Point]::new(18, 258)
    $editorHint.Size = [System.Drawing.Size]::new(476, 46)
    $editorGroup.Controls.Add($editorHint)

    $assignmentCount = New-Object System.Windows.Forms.Label
    $assignmentCount.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $assignmentCount.Location = [System.Drawing.Point]::new(18, 315)
    $assignmentCount.Size = [System.Drawing.Size]::new(250, 26)
    $editorGroup.Controls.Add($assignmentCount)

    $assignmentFilter = New-Object MugenDeejWindowing.MugenComboBox
    $assignmentFilter.DropDownStyle = 'DropDownList'
    $assignmentFilter.Location = [System.Drawing.Point]::new(322, 310)
    $assignmentFilter.Size = [System.Drawing.Size]::new(172, 30)
    [void]$assignmentFilter.Items.Add($(if ($script:Language -eq 'ru') { 'Назначенные' } else { 'Assigned' }))
    [void]$assignmentFilter.Items.Add($(if ($script:Language -eq 'ru') { 'Все назначения' } else { 'All mappings' }))
    $assignmentFilter.SelectedIndex = 0
    $editorGroup.Controls.Add($assignmentFilter)

    $assignmentList = New-Object System.Windows.Forms.ListView
    $assignmentList.Location = [System.Drawing.Point]::new(18, 348)
    $assignmentList.Size = [System.Drawing.Size]::new(476, 144)
    $assignmentList.View = [System.Windows.Forms.View]::Details
    $assignmentList.FullRowSelect = $true
    $assignmentList.HideSelection = $false
    $assignmentList.MultiSelect = $false
    [void]$assignmentList.Columns.Add($(if ($script:Language -eq 'ru') { 'Элемент' } else { 'Control' }), 78)
    [void]$assignmentList.Columns.Add($(if ($script:Language -eq 'ru') { 'Когда' } else { 'When' }), 120)
    [void]$assignmentList.Columns.Add($(if ($script:Language -eq 'ru') { 'Действие' } else { 'Action' }), 250)
    $editorGroup.Controls.Add($assignmentList)

    $selectors = @()
    for ($i = 0; $i -lt [int]$script:DetectedToggleCount; $i++) {
        $tile = New-Object MugenDeejWindowing.MugenButtonTile
        $tile.Text = ('T' + ($i + 1))
        $tile.Tag = ('t:' + $i)
        $tile.Size = [System.Drawing.Size]::new(54, 30)
        $tile.Margin = New-Object System.Windows.Forms.Padding(4, 3, 4, 3)
        $tile.TextAlign = 'MiddleCenter'
        $selectorFlow.Controls.Add($tile)
        $selectors += $tile
    }
    for ($i = 0; $i -lt [int]$script:DetectedEncoderCount; $i++) {
        $tile = New-Object MugenDeejWindowing.MugenButtonTile
        $hasPush = (@($script:LatestEncoders).Count -gt $i -and [bool]$script:LatestEncoders[$i].HasPush)
        $tile.Text = if ($hasPush) { ('E' + ($i + 1) + '•') } else { ('E' + ($i + 1)) }
        $tile.Tag = ('e:' + $i)
        $tile.Size = [System.Drawing.Size]::new(54, 30)
        $tile.Margin = New-Object System.Windows.Forms.Padding(4, 3, 4, 3)
        $tile.TextAlign = 'MiddleCenter'
        $selectorFlow.Controls.Add($tile)
        $selectors += $tile
    }

    $state = [pscustomobject]@{
        Kind = $(if ([int]$script:DetectedToggleCount -gt 0) { 't' } else { 'e' })
        Index = 0
        Suppress = $false
        Map1 = New-Object System.Collections.ArrayList
        Map2 = New-Object System.Collections.ArrayList
        Map3 = New-Object System.Collections.ArrayList
        LastToggles = @($script:LatestToggles)
        LastEncoderPositions = @($script:LatestEncoders | ForEach-Object { [int64]$_.Position })
        LastEncoderPush = @($script:LatestEncoders | ForEach-Object { if ([bool]$_.HasPush) { [int]$_.Push } else { 1 } })
    }

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
        $key = & $getProfileDraftKey ([string]$profileState.Process)
        $profileDrafts[$key] = [pscustomobject][ordered]@{
            toggles = @(Copy-AdaptiveProfileToggles -Items @($pendingToggles))
            encoders = @(Copy-AdaptiveProfileEncoders -Items @($pendingEncoders))
        }
    }

    $loadProfileDraft = {
        param([string]$ProcessName)

        $normalized = Normalize-TargetName -Value $ProcessName
        $key = & $getProfileDraftKey $normalized
        $draft = $null

        if ($profileDrafts.ContainsKey($key)) {
            $draft = $profileDrafts[$key]
        }
        elseif ([string]::IsNullOrWhiteSpace($normalized)) {
            $draft = [pscustomobject][ordered]@{
                toggles = @(Copy-AdaptiveProfileToggles -Items @($script:AdaptiveToggleActions))
                encoders = @(Copy-AdaptiveProfileEncoders -Items @($script:AdaptiveEncoderActions))
            }
            $profileDrafts[$key] = $draft
        }
        else {
            $profile = & $findWorkingProfile $normalized
            if ($null -eq $profile) { return }
            $draft = [pscustomobject][ordered]@{
                toggles = @(Copy-AdaptiveProfileToggles -Items @($profile.toggles))
                encoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
            }
            $profileDrafts[$key] = $draft
        }

        $pendingToggles.Clear()
        foreach ($item in @($draft.toggles)) {
            [void]$pendingToggles.Add([pscustomobject][ordered]@{
                on = [string]$item.on
                off = [string]$item.off
            })
        }
        while ($pendingToggles.Count -lt [int]$script:DetectedToggleCount) {
            [void]$pendingToggles.Add([pscustomobject][ordered]@{ on = 'none'; off = 'none' })
        }

        $pendingEncoders.Clear()
        foreach ($item in @($draft.encoders)) {
            [void]$pendingEncoders.Add([pscustomobject][ordered]@{
                cw = [string]$item.cw
                ccw = [string]$item.ccw
                push = [string]$item.push
            })
        }
        while ($pendingEncoders.Count -lt [int]$script:DetectedEncoderCount) {
            [void]$pendingEncoders.Add([pscustomobject][ordered]@{ cw = 'none'; ccw = 'none'; push = 'none' })
        }

        $profileState.Process = $normalized
    }

    $populateProfileCombo = {
        param([string]$SelectProcess = '')

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
        $picker.Font = $settingsForm.Font
        Set-FormAppIcon -Form $picker

        $pickerHeading = New-Object System.Windows.Forms.Label
        $pickerHeading.Text = if ($script:Language -eq 'ru') { 'Для какого приложения создать профиль?' } else { 'Which application should have its own profile?' }
        $pickerHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
        $pickerHeading.AutoSize = $true
        $pickerHeading.Location = [System.Drawing.Point]::new(20, 18)
        $picker.Controls.Add($pickerHeading)

        $pickerHint = New-Object System.Windows.Forms.Label
        $pickerHint.Text = if ($script:Language -eq 'ru') {
            'Новый профиль получит копию текущих назначений Общего профиля.'
        } else {
            'The new profile will start with a copy of the current Global mappings.'
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
        $pickerAdd.Text = if ($script:Language -eq 'ru') { 'Создать' } else { 'Create' }
        $pickerAdd.Tag = 'MugenPrimary'
        $pickerAdd.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $pickerAdd.Location = [System.Drawing.Point]::new(438, 164)
        $pickerAdd.Size = [System.Drawing.Size]::new(100, 36)
        $picker.Controls.Add($pickerAdd)

        Apply-ThemeToForm -Form $picker -ThemeName (Get-EffectiveTheme)
        $picker.Add_Shown({ Ensure-FormVisible -Form $picker -CenterIfOffscreen })
        $picker.AcceptButton = $pickerAdd
        $picker.CancelButton = $pickerCancel

        $result = $picker.ShowDialog($settingsForm)
        $chosen = if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            [string]$runningProcesses[[int]$pickerCombo.SelectedIndex]
        } else {
            ''
        }
        $picker.Dispose()
        return (Normalize-TargetName -Value $chosen)
    }

    & $captureCurrentProfileDraft

    $refreshAssignmentList = {
        $showAll = ($assignmentFilter.SelectedIndex -eq 1)
        $rows = @()
        $assignedCount = 0
        $totalCount = 0

        for ($i = 0; $i -lt [int]$script:DetectedToggleCount; $i++) {
            if ($i -ge $pendingToggles.Count) { continue }

            $toggleEntries = @(
                [pscustomobject]@{ Event = $(if ($script:Language -eq 'ru') { 'Включение' } else { 'Switch ON' }); Action = [string]$pendingToggles[$i].on },
                [pscustomobject]@{ Event = $(if ($script:Language -eq 'ru') { 'Выключение' } else { 'Switch OFF' }); Action = [string]$pendingToggles[$i].off }
            )

            foreach ($entry in $toggleEntries) {
                $totalCount++
                $action = ConvertTo-SafeAdaptiveAction -Action ([string]$entry.Action)
                if ($action -ne 'none') { $assignedCount++ }
                if ($showAll -or $action -ne 'none') {
                    $rows += [pscustomobject]@{
                        Control = ('T' + ($i + 1))
                        Event = [string]$entry.Event
                        Action = (Get-AdaptiveActionDisplay -Action $action)
                        Target = ('t:' + $i)
                    }
                }
            }
        }

        for ($i = 0; $i -lt [int]$script:DetectedEncoderCount; $i++) {
            if ($i -ge $pendingEncoders.Count) { continue }
            $hasPush = (@($script:LatestEncoders).Count -gt $i -and [bool]$script:LatestEncoders[$i].HasPush)

            $encoderEntries = @(
                [pscustomobject]@{ Event = $(if ($script:Language -eq 'ru') { 'По часовой' } else { 'Clockwise' }); Action = [string]$pendingEncoders[$i].cw },
                [pscustomobject]@{ Event = $(if ($script:Language -eq 'ru') { 'Против часовой' } else { 'Counter-clockwise' }); Action = [string]$pendingEncoders[$i].ccw }
            )
            if ($hasPush) {
                $encoderEntries += [pscustomobject]@{ Event = $(if ($script:Language -eq 'ru') { 'Нажатие' } else { 'Push' }); Action = [string]$pendingEncoders[$i].push }
            }

            foreach ($entry in $encoderEntries) {
                $totalCount++
                $action = ConvertTo-SafeAdaptiveAction -Action ([string]$entry.Action)
                if ($action -ne 'none') { $assignedCount++ }
                if ($showAll -or $action -ne 'none') {
                    $rows += [pscustomobject]@{
                        Control = ('E' + ($i + 1))
                        Event = [string]$entry.Event
                        Action = (Get-AdaptiveActionDisplay -Action $action)
                        Target = ('e:' + $i)
                    }
                }
            }
        }

        $assignmentCount.Text = if ($script:Language -eq 'ru') {
            'Назначения: {0} из {1}' -f $assignedCount, $totalCount
        }
        else {
            'Assignments: {0} of {1}' -f $assignedCount, $totalCount
        }

        $assignmentList.BeginUpdate()
        try {
            $assignmentList.Items.Clear()
            foreach ($row in $rows) {
                $item = New-Object System.Windows.Forms.ListViewItem([string]$row.Control)
                [void]$item.SubItems.Add([string]$row.Event)
                [void]$item.SubItems.Add([string]$row.Action)
                $item.Tag = [string]$row.Target
                [void]$assignmentList.Items.Add($item)
            }
        }
        finally {
            $assignmentList.EndUpdate()
        }
    }

    $getCurrentAction = {
        param([string]$Slot)
        $index = [int]$state.Index
        if ($state.Kind -eq 't') {
            if ($index -ge $pendingToggles.Count) { return 'none' }
            if ($Slot -eq '1') { return [string]$pendingToggles[$index].on }
            return [string]$pendingToggles[$index].off
        }
        if ($index -ge $pendingEncoders.Count) { return 'none' }
        switch ($Slot) {
            '1' { return [string]$pendingEncoders[$index].cw }
            '2' { return [string]$pendingEncoders[$index].ccw }
            default { return [string]$pendingEncoders[$index].push }
        }
    }

    $setCurrentAction = {
        param([string]$Slot, [string]$Action)
        $index = [int]$state.Index
        $Action = ConvertTo-SafeAdaptiveAction -Action $Action
        if ($state.Kind -eq 't') {
            if ($Slot -eq '1') { $pendingToggles[$index].on = $Action }
            else { $pendingToggles[$index].off = $Action }
            return
        }
        switch ($Slot) {
            '1' { $pendingEncoders[$index].cw = $Action }
            '2' { $pendingEncoders[$index].ccw = $Action }
            default { $pendingEncoders[$index].push = $Action }
        }
    }

    $refreshSelectors = {
        $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
        foreach ($tile in $selectors) {
            $parts = ([string]$tile.Tag).Split(':')
            $kind = [string]$parts[0]
            $index = [int]$parts[1]
            $selected = ($kind -eq [string]$state.Kind -and $index -eq [int]$state.Index)
            $active = $false
            if ($kind -eq 't' -and @($script:LatestToggles).Count -gt $index) {
                $active = ([int]$script:LatestToggles[$index] -eq 1)
            }
            elseif ($kind -eq 'e' -and @($script:LatestEncoders).Count -gt $index) {
                $enc = $script:LatestEncoders[$index]
                $active = ([bool]$enc.HasPush -and [int]$enc.Push -eq 0)
            }
            $tile.BackColor = if ($active) { $palette.Accent } else { $palette.Control }
            $tile.ForeColor = if ($active) { $palette.AccentText } else { $palette.Text }
            $tile.BorderColor = if ($selected) { $palette.Accent } else { $palette.Border }
        }
    }

    $refreshEditor = {
        $state.Suppress = $true
        try {
            $index = [int]$state.Index
            if ($state.Kind -eq 't') {
                $selectedHeading.Text = if ($script:Language -eq 'ru') { 'Тумблер ' + ($index + 1) } else { 'Toggle ' + ($index + 1) }
                $row1Label.Text = if ($script:Language -eq 'ru') { 'При включении' } else { 'When switched ON' }
                $row2Label.Text = if ($script:Language -eq 'ru') { 'При выключении' } else { 'When switched OFF' }
                $row3Label.Visible = $false
                $row3Combo.Visible = $false
                Populate-AdaptiveActionCombo -Combo $row1Combo -Map $state.Map1 -CurrentAction (& $getCurrentAction '1')
                Populate-AdaptiveActionCombo -Combo $row2Combo -Map $state.Map2 -CurrentAction (& $getCurrentAction '2')
            }
            else {
                $hasPush = $false
                if (@($script:LatestEncoders).Count -gt $index) { $hasPush = [bool]$script:LatestEncoders[$index].HasPush }
                $selectedHeading.Text = if ($script:Language -eq 'ru') {
                    'Энкодер ' + ($index + 1) + $(if ($hasPush) { ' · с нажатием' } else { ' · только вращение' })
                }
                else {
                    'Encoder ' + ($index + 1) + $(if ($hasPush) { ' · push-capable' } else { ' · rotation only' })
                }
                $row1Label.Text = if ($script:Language -eq 'ru') { 'По часовой' } else { 'Clockwise' }
                $row2Label.Text = if ($script:Language -eq 'ru') { 'Против часовой' } else { 'Counter-clockwise' }
                $row3Label.Text = if ($script:Language -eq 'ru') { 'Нажатие' } else { 'Push' }
                $hasPush = $false
                if (@($script:LatestEncoders).Count -gt $index) { $hasPush = [bool]$script:LatestEncoders[$index].HasPush }
                $row3Label.Visible = $hasPush
                $row3Combo.Visible = $hasPush
                Populate-AdaptiveActionCombo -Combo $row1Combo -Map $state.Map1 -CurrentAction (& $getCurrentAction '1')
                Populate-AdaptiveActionCombo -Combo $row2Combo -Map $state.Map2 -CurrentAction (& $getCurrentAction '2')
                if ($hasPush) { Populate-AdaptiveActionCombo -Combo $row3Combo -Map $state.Map3 -CurrentAction (& $getCurrentAction '3') }
            }
        }
        finally { $state.Suppress = $false }
        & $refreshSelectors
    }

    $selectControl = {
        param([string]$Kind, [int]$Index)
        if ($Kind -eq 't') {
            if ($Index -lt 0 -or $Index -ge [int]$script:DetectedToggleCount) { return }
        }
        else {
            if ($Index -lt 0 -or $Index -ge [int]$script:DetectedEncoderCount) { return }
        }
        $state.Kind = $Kind
        $state.Index = $Index
        & $refreshEditor
    }

    foreach ($tile in $selectors) {
        $tile.Add_Click({
            param($sender, $eventArgs)
            $parts = ([string]$sender.Tag).Split(':')
            & $selectControl -Kind ([string]$parts[0]) -Index ([int]$parts[1])
        })
    }

    $handleCombo = {
        param($Combo, $Map, [string]$Slot)
        if ($state.Suppress) { return }
        $selectedIndex = [int]$Combo.SelectedIndex
        if ($selectedIndex -lt 0 -or $selectedIndex -ge $Map.Count) { return }
        $chosen = [string]$Map[$selectedIndex]
        $previous = [string](& $getCurrentAction $Slot)
        $configured = Resolve-AdaptiveConfiguredAction -SelectedAction $chosen -PreviousAction $previous
        if (-not [string]::IsNullOrWhiteSpace($configured)) { & $setCurrentAction $Slot ([string]$configured) }
        & $refreshEditor
        & $refreshAssignmentList
    }

    $row1Combo.Add_SelectedIndexChanged({ & $handleCombo $row1Combo $state.Map1 '1' })
    $row2Combo.Add_SelectedIndexChanged({ & $handleCombo $row2Combo $state.Map2 '2' })
    $row3Combo.Add_SelectedIndexChanged({ & $handleCombo $row3Combo $state.Map3 '3' })
    $profileCombo.Add_SelectedIndexChanged({
        if ($profileState.Suppress) { return }
        $index = [int]$profileCombo.SelectedIndex
        if ($index -lt 0 -or $index -ge $profileState.Map.Count) { return }

        & $captureCurrentProfileDraft
        & $loadProfileDraft ([string]$profileState.Map[$index])
        & $refreshEditor
        & $refreshAssignmentList
    })
    $addProfileButton.Add_Click({
        & $captureCurrentProfileDraft
        $processName = [string](& $showAddProfileDialog)
        if ([string]::IsNullOrWhiteSpace($processName)) { return }

        $existingProfile = & $findWorkingProfile $processName
        if ($null -eq $existingProfile) {
            $globalDraft = $profileDrafts['__global__']
            $profile = [pscustomobject][ordered]@{
                name = (Get-FriendlyProcessName -ProcessName $processName)
                process = $processName
                buttons = @(Copy-AdaptiveProfileButtons -Items @($script:ButtonActions))
                toggles = @(Copy-AdaptiveProfileToggles -Items @($globalDraft.toggles))
                encoders = @(Copy-AdaptiveProfileEncoders -Items @($globalDraft.encoders))
            }
            [void]$workingProfiles.Add($profile)
            $key = & $getProfileDraftKey $processName
            $profileDrafts[$key] = [pscustomobject][ordered]@{
                toggles = @(Copy-AdaptiveProfileToggles -Items @($profile.toggles))
                encoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
            }
        }

        & $populateProfileCombo $processName
        & $loadProfileDraft $processName
        & $refreshEditor
        & $refreshAssignmentList
    })
    $assignmentFilter.Add_SelectedIndexChanged({ & $refreshAssignmentList })
    $assignmentList.Add_SelectedIndexChanged({
        if ($assignmentList.SelectedItems.Count -eq 0) { return }
        $parts = ([string]$assignmentList.SelectedItems[0].Tag).Split(':')
        if ($parts.Count -ne 2) { return }
        & $selectControl -Kind ([string]$parts[0]) -Index ([int]$parts[1])
    })

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(580, 744)
    $cancel.Size = [System.Drawing.Size]::new(100, 36)
    $settingsForm.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(692, 744)
    $save.Size = [System.Drawing.Size]::new(106, 36)
    $settingsForm.Controls.Add($save)
    $save.Add_Click({
        & $captureCurrentProfileDraft

        $globalDraft = $profileDrafts['__global__']
        $script:AdaptiveToggleActions = @(Copy-AdaptiveProfileToggles -Items @($globalDraft.toggles))
        $script:AdaptiveEncoderActions = @(Copy-AdaptiveProfileEncoders -Items @($globalDraft.encoders))
        Save-AdaptiveActions

        foreach ($profile in @($workingProfiles)) {
            $key = & $getProfileDraftKey ([string]$profile.process)
            if ($profileDrafts.ContainsKey($key)) {
                $draft = $profileDrafts[$key]
                $profile.toggles = @(Copy-AdaptiveProfileToggles -Items @($draft.toggles))
                $profile.encoders = @(Copy-AdaptiveProfileEncoders -Items @($draft.encoders))
            }
        }

        $script:AdaptiveProfiles = @($workingProfiles)
        $script:AdaptiveProfilesLoaded = $true
        Save-AdaptiveProfiles

        Write-Log ('Adaptive profile settings saved: profiles={0}; selected={1}' -f @($script:AdaptiveProfiles).Count, $(if ([string]::IsNullOrWhiteSpace([string]$profileState.Process)) { 'Global' } else { [string]$profileState.Process + '.exe' })) 'INFO'
        $settingsForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $settingsForm.Close()
    })

    $liveTimer = New-Object System.Windows.Forms.Timer
    $liveTimer.Interval = 50
    $liveTimer.Add_Tick({
        $latestToggles = @($script:LatestToggles)
        for ($i = 0; $i -lt [Math]::Min($latestToggles.Count, @($state.LastToggles).Count); $i++) {
            if ([int]$latestToggles[$i] -ne [int]$state.LastToggles[$i]) {
                & $selectControl -Kind 't' -Index $i
                break
            }
        }

        $latestEncoders = @($script:LatestEncoders)
        for ($i = 0; $i -lt $latestEncoders.Count; $i++) {
            $oldPos = if (@($state.LastEncoderPositions).Count -gt $i) { [int64]$state.LastEncoderPositions[$i] } else { [int64]$latestEncoders[$i].Position }
            $oldPush = if (@($state.LastEncoderPush).Count -gt $i) { [int]$state.LastEncoderPush[$i] } else { 1 }
            $newPos = [int64]$latestEncoders[$i].Position
            $newPush = if ([bool]$latestEncoders[$i].HasPush) { [int]$latestEncoders[$i].Push } else { 1 }
            if ($newPos -ne $oldPos -or ($newPush -eq 0 -and $oldPush -ne 0)) {
                & $selectControl -Kind 'e' -Index $i
                break
            }
        }

        $state.LastToggles = @($latestToggles)
        $state.LastEncoderPositions = @($latestEncoders | ForEach-Object { [int64]$_.Position })
        $state.LastEncoderPush = @($latestEncoders | ForEach-Object { if ([bool]$_.HasPush) { [int]$_.Push } else { 1 } })

        if ($state.Kind -eq 't') {
            $isOn = (@($script:LatestToggles).Count -gt [int]$state.Index -and [int]$script:LatestToggles[[int]$state.Index] -eq 1)
            $liveState.Text = if ($script:Language -eq 'ru') { 'Сейчас: ' + $(if ($isOn) { 'ВКЛ' } else { 'ВЫКЛ' }) } else { 'Now: ' + $(if ($isOn) { 'ON' } else { 'OFF' }) }
        }
        else {
            $index = [int]$state.Index
            if (@($script:LatestEncoders).Count -gt $index) {
                $enc = $script:LatestEncoders[$index]
                $pushText = if ([bool]$enc.HasPush) {
                    if ([int]$enc.Push -eq 0) { $(if ($script:Language -eq 'ru') { 'нажат' } else { 'pressed' }) } else { $(if ($script:Language -eq 'ru') { 'отпущен' } else { 'released' }) }
                }
                else { $(if ($script:Language -eq 'ru') { 'без кнопки' } else { 'no push' }) }
                $liveState.Text = if ($script:Language -eq 'ru') { 'Позиция: {0} · {1}' -f [int64]$enc.Position, $pushText } else { 'Position: {0} · {1}' -f [int64]$enc.Position, $pushText }
            }
        }
        & $refreshSelectors
    })

    & $populateProfileCombo ''
    & $loadProfileDraft ''

    Apply-ThemeToForm -Form $settingsForm -ThemeName (Get-EffectiveTheme)
    $saveNotice.ForeColor = [System.Drawing.Color]::FromArgb(230, 170, 70)
    & $refreshEditor
    & $refreshAssignmentList

    $settingsForm.Add_Shown({
        Ensure-FormVisible -Form $settingsForm -CenterIfOffscreen
        $liveTimer.Start()
    })
    $settingsForm.Add_FormClosed({ $liveTimer.Stop(); $liveTimer.Dispose() })
    $settingsForm.AcceptButton = $save
    $settingsForm.CancelButton = $cancel
    [void]$settingsForm.ShowDialog($form)
    if (-not $settingsForm.IsDisposed) { $settingsForm.Dispose() }
}

'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText 'function Initialize-AdaptiveControlStates {' `
    -NewText ($actionHelpers + 'function Initialize-AdaptiveControlStates {') `
    -Label 'inject Adaptive action persistence/editor helpers'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
    Initialize-ButtonActions

    if (
        $ButtonIndex -lt 0 -or
        $ButtonIndex -ge @($script:ButtonActions).Count
    ) {
        return
    }

    $now = Get-Date
'@ `
    -NewText @'
    Initialize-ButtonActions

    if ($ButtonIndex -lt 0) { return }
    $action = Get-ProfiledButtonAction -ButtonIndex $ButtonIndex

    # Virtual Xbox mappings are stateful and were already submitted from the
    # complete physical-button frame before edge dispatch. Do not run them
    # through the legacy one-shot 80 ms debounce or its synchronous log path.
    if (
        $script:VirtualGamepadFeatureAvailable -and
        (Test-MugenVirtualGamepadAction -Action $action)
    ) {
        return
    }

    $now = Get-Date
'@ `
    -Label 'resolve button press action through foreground profile'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
    $action = [string]$script:ButtonActions[$ButtonIndex]

'@ `
    -NewText @'
    # Foreground-profile button action was resolved before debounce handling.

'@ `
    -Label 'remove global-only button action lookup'

# ---------------------------------------------------------------------------
# Execute first-class actions from actual state transitions / encoder detents
# ---------------------------------------------------------------------------

$adaptiveStateUpdate = @'
function Update-AdaptiveControlStates {
    param([Parameter(Mandatory = $true)]$Packet)

    $newToggles = @(Get-ControllerPacketArray -Packet $Packet -Name 'Toggles')
    $newEncoders = @(Get-ControllerPacketArray -Packet $Packet -Name 'Encoders')
    Initialize-AdaptiveActions

    $oldToggles = @($script:LatestToggles)
    for ($i = 0; $i -lt $newToggles.Count; $i++) {
        if ($i -lt $oldToggles.Count -and [int]$oldToggles[$i] -ne [int]$newToggles[$i]) {
            $newState = [int]$newToggles[$i]
            $stateText = if ($newState -eq 1) { 'ON' } else { 'OFF' }
            Write-Log ('Toggle {0} changed: {1}' -f ($i + 1), $stateText) 'INFO'
            $action = Get-AdaptiveToggleMappedAction -Index $i -State $newState
            Invoke-AdaptiveMappedAction -Action $action -Source ('Toggle {0} {1}' -f ($i + 1), $stateText)
        }
    }

    $oldEncoders = @($script:LatestEncoders)
    for ($i = 0; $i -lt $newEncoders.Count; $i++) {
        $position = [int64]$newEncoders[$i].Position

        if ($i -lt $script:LastEncoderPositions.Count) {
            $delta = $position - [int64]$script:LastEncoderPositions[$i]
            if ($delta -ne 0) {
                Write-Log ('Encoder {0} moved: delta={1}; position={2}' -f ($i + 1), $delta, $position) 'INFO'
                $kind = if ($delta -gt 0) { 'cw' } else { 'ccw' }
                $action = Get-AdaptiveEncoderMappedAction -Index $i -Kind $kind
                $requestedSteps = [Math]::Abs([double]$delta)
                $steps = [int][Math]::Min(32.0, $requestedSteps)
                if ($requestedSteps -gt 32.0) {
                    Write-Log ('Encoder {0} delta requested {1:N0} actions; safety cap limited this packet to 32' -f ($i + 1), $requestedSteps) 'WARN'
                }
                for ($step = 0; $step -lt $steps; $step++) {
                    Invoke-AdaptiveMappedAction -Action $action -Source ('Encoder {0} {1}' -f ($i + 1), $kind.ToUpperInvariant())
                }
            }
        }

        if ($i -lt $oldEncoders.Count) {
            $oldHasPush = [bool]$oldEncoders[$i].HasPush
            $newHasPush = [bool]$newEncoders[$i].HasPush
            if ($oldHasPush -and $newHasPush -and [int]$oldEncoders[$i].Push -ne [int]$newEncoders[$i].Push) {
                $pressed = ([int]$newEncoders[$i].Push -eq 0)
                $pushText = if ($pressed) { 'pressed' } else { 'released' }
                Write-Log ('Encoder {0} push {1}' -f ($i + 1), $pushText) 'INFO'
                if ($pressed) {
                    $action = Get-AdaptiveEncoderMappedAction -Index $i -Kind 'push'
                    Invoke-AdaptiveMappedAction -Action $action -Source ('Encoder {0} push' -f ($i + 1))
                }
            }
        }
    }

    $script:LatestToggles = @($newToggles)
    $script:LatestEncoders = @($newEncoders)
    $script:LastEncoderPositions = @()
    foreach ($encoder in $newEncoders) {
        $script:LastEncoderPositions += [int64]$encoder.Position
    }
}

'@

$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Update-AdaptiveControlStates \{.*?^function Get-ControllerConnectedStatusText \{' `
    -Replacement ($adaptiveStateUpdate + 'function Get-ControllerConnectedStatusText {') `
    -Label 'wire typed actions into live state changes'

# ---------------------------------------------------------------------------
# Replace the developer text dump with a visual, live, scrollable full-state UI
# ---------------------------------------------------------------------------

$fullStateUi = @'
function Show-FullControllerStateWindow {
    if (-not $script:IsConnected) { return }

    $stateForm = New-Object System.Windows.Forms.Form
    $stateForm.Text = if ($script:Language -eq 'ru') { 'Состояние контроллера' } else { 'Controller state' }
    $stateForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $stateForm.ClientSize = [System.Drawing.Size]::new(760, 620)
    $stateForm.MinimumSize = [System.Drawing.Size]::new(676, 500)
    $stateForm.Font = $form.Font
    $stateForm.ShowInTaskbar = $false
    Set-FormAppIcon -Form $stateForm

    $summary = New-Object MugenDeejWindowing.MugenCardPanel
    $summary.Location = [System.Drawing.Point]::new(18, 16)
    $summary.Size = [System.Drawing.Size]::new(724, 72)
    $summary.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Top -bor
        [System.Windows.Forms.AnchorStyles]::Left -bor
        [System.Windows.Forms.AnchorStyles]::Right
    )
    $stateForm.Controls.Add($summary)

    $summaryTitle = New-Object System.Windows.Forms.Label
    $summaryTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $summaryTitle.Location = [System.Drawing.Point]::new(16, 12)
    $summaryTitle.Size = [System.Drawing.Size]::new(690, 24)
    $summary.Controls.Add($summaryTitle)

    $summaryDetail = New-Object System.Windows.Forms.Label
    $summaryDetail.ForeColor = [System.Drawing.Color]::DimGray
    $summaryDetail.Location = [System.Drawing.Point]::new(16, 39)
    $summaryDetail.Size = [System.Drawing.Size]::new(690, 23)
    $summary.Controls.Add($summaryDetail)

    $scroll = New-Object System.Windows.Forms.Panel
    $scroll.Location = [System.Drawing.Point]::new(18, 100)
    $scroll.Size = [System.Drawing.Size]::new(724, 502)
    $scroll.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Top -bor
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Left -bor
        [System.Windows.Forms.AnchorStyles]::Right
    )
    $scroll.AutoScroll = $true
    $stateForm.Controls.Add($scroll)

    $sliderViews = @()
    $buttonViews = @()
    $toggleViews = @()
    $encoderViews = @()
    $contentY = 0
    $contentWidth = 696

    if ([int]$script:DetectedSliderCount -gt 0) {
        $count = [int]$script:DetectedSliderCount
        $groupHeight = 38 + ($count * 31)
        $group = New-Object MugenDeejWindowing.MugenGroupBox
        $group.Text = if ($script:Language -eq 'ru') { 'Регуляторы ({0})' -f $count } else { 'Controls ({0})' -f $count }
        $group.Location = [System.Drawing.Point]::new(0, $contentY)
        $group.Size = [System.Drawing.Size]::new($contentWidth, $groupHeight)
        $scroll.Controls.Add($group)

        for ($i = 0; $i -lt $count; $i++) {
            $y = 31 + ($i * 31)
            $name = New-Object System.Windows.Forms.Label
            $name.Text = if ($i -lt @($script:Config.sliders).Count) { [string]$script:Config.sliders[$i].name } else { (T -Key 'KnobN' -Args @($i + 1)) }
            if ([string]::IsNullOrWhiteSpace($name.Text)) { $name.Text = (T -Key 'KnobN' -Args @($i + 1)) }
            $name.Location = [System.Drawing.Point]::new(14, $y)
            $name.Size = [System.Drawing.Size]::new(180, 24)
            $name.AutoEllipsis = $true
            $group.Controls.Add($name)

            $bar = New-Object MugenDeejWindowing.MugenProgressBar
            $bar.Location = [System.Drawing.Point]::new(202, $y)
            $bar.Size = [System.Drawing.Size]::new(380, 21)
            $bar.Minimum = 0
            $bar.Maximum = 1000
            $group.Controls.Add($bar)

            $value = New-Object System.Windows.Forms.Label
            $value.Location = [System.Drawing.Point]::new(590, $y)
            $value.Size = [System.Drawing.Size]::new(82, 23)
            $value.TextAlign = 'MiddleRight'
            $group.Controls.Add($value)
            $sliderViews += [pscustomobject]@{ Bar = $bar; Value = $value }
        }
        $contentY += $groupHeight + 10
    }

    if ([int]$script:DetectedButtonCount -gt 0) {
        $count = [int]$script:DetectedButtonCount
        $columns = 12
        $rows = [int][Math]::Ceiling($count / [double]$columns)
        $flowHeight = ($rows * 34) + 4
        $group = New-Object MugenDeejWindowing.MugenGroupBox
        $group.Text = if ($script:Language -eq 'ru') { 'Кнопки ({0})' -f $count } else { 'Buttons ({0})' -f $count }
        $group.Location = [System.Drawing.Point]::new(0, $contentY)
        $group.Size = [System.Drawing.Size]::new($contentWidth, (38 + $flowHeight))
        $scroll.Controls.Add($group)

        $flow = New-Object System.Windows.Forms.FlowLayoutPanel
        $flow.Location = [System.Drawing.Point]::new(12, 29)
        $flow.Size = [System.Drawing.Size]::new(672, $flowHeight)
        $flow.WrapContents = $true
        $flow.AutoScroll = $false
        $flow.BackColor = $group.BackColor
        $group.Controls.Add($flow)

        for ($i = 0; $i -lt $count; $i++) {
            $tile = New-Object MugenDeejWindowing.MugenButtonTile
            $tile.Text = [string]($i + 1)
            $tile.Size = [System.Drawing.Size]::new(46, 28)
            $tile.Margin = New-Object System.Windows.Forms.Padding(4, 2, 4, 2)
            $tile.TextAlign = 'MiddleCenter'
            $flow.Controls.Add($tile)
            $buttonViews += $tile
        }
        $contentY += $group.Height + 10
    }

    if ([int]$script:DetectedToggleCount -gt 0) {
        $count = [int]$script:DetectedToggleCount
        $columns = 5
        $rows = [int][Math]::Ceiling($count / [double]$columns)
        $flowHeight = ($rows * 34) + 4
        $group = New-Object MugenDeejWindowing.MugenGroupBox
        $group.Text = if ($script:Language -eq 'ru') { 'Тумблеры ({0})' -f $count } else { 'Toggles ({0})' -f $count }
        $group.Location = [System.Drawing.Point]::new(0, $contentY)
        $group.Size = [System.Drawing.Size]::new($contentWidth, (38 + $flowHeight))
        $scroll.Controls.Add($group)

        $flow = New-Object System.Windows.Forms.FlowLayoutPanel
        $flow.Location = [System.Drawing.Point]::new(12, 29)
        $flow.Size = [System.Drawing.Size]::new(672, $flowHeight)
        $flow.WrapContents = $true
        $flow.AutoScroll = $false
        $flow.BackColor = $group.BackColor
        $group.Controls.Add($flow)

        for ($i = 0; $i -lt $count; $i++) {
            $hostPanel = New-Object System.Windows.Forms.Panel
            $hostPanel.Size = [System.Drawing.Size]::new(124, 30)
            $hostPanel.Margin = New-Object System.Windows.Forms.Padding(3, 1, 3, 1)
            $hostPanel.BackColor = $group.BackColor

            $number = New-Object System.Windows.Forms.Label
            $number.Text = [string]($i + 1)
            $number.Location = [System.Drawing.Point]::new(0, 3)
            $number.Size = [System.Drawing.Size]::new(22, 24)
            $number.TextAlign = 'MiddleCenter'
            $number.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
            $hostPanel.Controls.Add($number)

            $switchView = New-Object System.Windows.Forms.Panel
            $switchView.Tag = $i
            $switchView.Location = [System.Drawing.Point]::new(24, 2)
            $switchView.Size = [System.Drawing.Size]::new(42, 26)
            $switchView.BackColor = $group.BackColor
            Enable-AdaptiveIndicatorDoubleBuffer -Control $switchView
            $switchView.Add_Paint({
                param($sender, $eventArgs)
                $index = [int]$sender.Tag
                $on = (@($script:LatestToggles).Count -gt $index -and [int]$script:LatestToggles[$index] -eq 1)
                $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
                $eventArgs.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $path = New-Object System.Drawing.Drawing2D.GraphicsPath
                try {
                    $path.AddArc(1, 4, 18, 18, 90, 180)
                    $path.AddArc(22, 4, 18, 18, 270, 180)
                    $path.CloseFigure()
                    $trackBrush = New-Object System.Drawing.SolidBrush($(if ($on) { $palette.Accent } else { $palette.ControlPressed }))
                    $borderPen = New-Object System.Drawing.Pen($palette.Border)
                    try { $eventArgs.Graphics.FillPath($trackBrush, $path); $eventArgs.Graphics.DrawPath($borderPen, $path) }
                    finally { $trackBrush.Dispose(); $borderPen.Dispose() }
                    $knobBrush = New-Object System.Drawing.SolidBrush($(if ($on) { $palette.AccentText } else { $palette.Muted }))
                    try { $eventArgs.Graphics.FillEllipse($knobBrush, $(if ($on) { 22 } else { 3 }), 6, 14, 14) }
                    finally { $knobBrush.Dispose() }
                }
                finally { $path.Dispose() }
            })
            $hostPanel.Controls.Add($switchView)

            $stateLabel = New-Object System.Windows.Forms.Label
            $stateLabel.Location = [System.Drawing.Point]::new(70, 3)
            $stateLabel.Size = [System.Drawing.Size]::new(50, 24)
            $hostPanel.Controls.Add($stateLabel)

            $flow.Controls.Add($hostPanel)
            $toggleViews += [pscustomobject]@{ Switch = $switchView; Label = $stateLabel; Last = $null }
        }
        $contentY += $group.Height + 10
    }

    if ([int]$script:DetectedEncoderCount -gt 0) {
        $count = [int]$script:DetectedEncoderCount
        $columns = 5
        $rows = [int][Math]::Ceiling($count / [double]$columns)
        $flowHeight = ($rows * 36) + 4
        $group = New-Object MugenDeejWindowing.MugenGroupBox
        $group.Text = if ($script:Language -eq 'ru') { 'Энкодеры ({0})' -f $count } else { 'Encoders ({0})' -f $count }
        $group.Location = [System.Drawing.Point]::new(0, $contentY)
        $group.Size = [System.Drawing.Size]::new($contentWidth, (38 + $flowHeight))
        $scroll.Controls.Add($group)

        $flow = New-Object System.Windows.Forms.FlowLayoutPanel
        $flow.Location = [System.Drawing.Point]::new(12, 29)
        $flow.Size = [System.Drawing.Size]::new(672, $flowHeight)
        $flow.WrapContents = $true
        $flow.AutoScroll = $false
        $flow.BackColor = $group.BackColor
        $group.Controls.Add($flow)

        for ($i = 0; $i -lt $count; $i++) {
            $hostPanel = New-Object System.Windows.Forms.Panel
            $hostPanel.Size = [System.Drawing.Size]::new(124, 32)
            $hostPanel.Margin = New-Object System.Windows.Forms.Padding(3, 1, 3, 1)
            $hostPanel.BackColor = $group.BackColor

            $number = New-Object System.Windows.Forms.Label
            $number.Text = [string]($i + 1)
            $number.Location = [System.Drawing.Point]::new(0, 4)
            $number.Size = [System.Drawing.Size]::new(22, 24)
            $number.TextAlign = 'MiddleCenter'
            $number.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
            $hostPanel.Controls.Add($number)

            $knob = New-Object System.Windows.Forms.Panel
            $knob.Tag = $i
            $knob.Location = [System.Drawing.Point]::new(24, 2)
            $knob.Size = [System.Drawing.Size]::new(28, 28)
            $knob.BackColor = $group.BackColor
            Enable-AdaptiveIndicatorDoubleBuffer -Control $knob
            $knob.Add_Paint({
                param($sender, $eventArgs)
                $index = [int]$sender.Tag
                $position = [int64]0
                $hasPush = $false
                $pressed = $false
                if (@($script:LatestEncoders).Count -gt $index) {
                    $enc = $script:LatestEncoders[$index]
                    $position = [int64]$enc.Position
                    $hasPush = [bool]$enc.HasPush
                    $pressed = ($hasPush -and [int]$enc.Push -eq 0)
                }
                $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
                $eventArgs.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $fillBrush = New-Object System.Drawing.SolidBrush($(if ($pressed) { $palette.Accent } else { $palette.Control }))
                $borderPen = New-Object System.Drawing.Pen($(if ($pressed) { $palette.Accent } else { $palette.Border }), 1)
                try { $eventArgs.Graphics.FillEllipse($fillBrush, 2, 2, 24, 24); $eventArgs.Graphics.DrawEllipse($borderPen, 2, 2, 24, 24) }
                finally { $fillBrush.Dispose(); $borderPen.Dispose() }
                $phase = (($position % 24) + 24) % 24
                $angle = (($phase * 15.0) - 90.0) * [Math]::PI / 180.0
                $center = 14.0
                $innerRadius = if ($hasPush) { 5.5 } else { 3.5 }
                $x1 = $center + ([Math]::Cos($angle) * $innerRadius)
                $y1 = $center + ([Math]::Sin($angle) * $innerRadius)
                $x2 = $center + ([Math]::Cos($angle) * 9.0)
                $y2 = $center + ([Math]::Sin($angle) * 9.0)
                $marker = New-Object System.Drawing.Pen($(if ($pressed) { $palette.AccentText } else { $palette.Accent }), 2)
                try { $eventArgs.Graphics.DrawLine($marker, [single]$x1, [single]$y1, [single]$x2, [single]$y2) }
                finally { $marker.Dispose() }

                if ($hasPush) {
                    $pushCueColor = if ($pressed) { $palette.AccentText } else { $palette.Accent }
                    $pushCuePen = New-Object System.Drawing.Pen($pushCueColor, 1.5)
                    try {
                        $eventArgs.Graphics.DrawEllipse($pushCuePen, 11, 11, 6, 6)
                        if ($pressed) {
                            $pushCueBrush = New-Object System.Drawing.SolidBrush($pushCueColor)
                            try { $eventArgs.Graphics.FillEllipse($pushCueBrush, 12, 12, 4, 4) }
                            finally { $pushCueBrush.Dispose() }
                        }
                    }
                    finally { $pushCuePen.Dispose() }
                }
            })
            $hostPanel.Controls.Add($knob)

            $positionLabel = New-Object System.Windows.Forms.Label
            $positionLabel.Location = [System.Drawing.Point]::new(58, 4)
            $positionLabel.Size = [System.Drawing.Size]::new(62, 24)
            $positionLabel.TextAlign = 'MiddleCenter'
            $positionLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
            $hostPanel.Controls.Add($positionLabel)
            $flow.Controls.Add($hostPanel)
            $encoderViews += [pscustomobject]@{ Knob = $knob; Label = $positionLabel; LastPosition = $null; LastHasPush = $null; LastPressed = $null }
        }
        $contentY += $group.Height + 10
    }

    $scroll.AutoScrollMinSize = [System.Drawing.Size]::new(696, [Math]::Max(0, $contentY))

    $refreshState = {
        $summaryTitle.Text = if ($script:IsConnected) {
            '{0} · {1}' -f (Get-ControllerProtocolDisplayText), $(if ([string]::IsNullOrWhiteSpace($script:ConnectedPort)) { 'COM —' } else { $script:ConnectedPort })
        }
        else { $(if ($script:Language -eq 'ru') { 'Связь с контроллером потеряна' } else { 'Controller disconnected' }) }
        $summaryDetail.Text = if ($script:Language -eq 'ru') {
            '{0} регуляторов · {1} кнопок · {2} тумблеров · {3} энкодеров' -f $script:DetectedSliderCount, $script:DetectedButtonCount, $script:DetectedToggleCount, $script:DetectedEncoderCount
        }
        else {
            '{0} controls · {1} buttons · {2} toggles · {3} encoders' -f $script:DetectedSliderCount, $script:DetectedButtonCount, $script:DetectedToggleCount, $script:DetectedEncoderCount
        }

        for ($i = 0; $i -lt $sliderViews.Count; $i++) {
            $level = if (@($script:LatestLevels).Count -gt $i) { [double]$script:LatestLevels[$i] } else { 0.0 }
            $level = [Math]::Max(0.0, [Math]::Min(1.0, $level))
            $sliderViews[$i].Bar.Value = [int][Math]::Round($level * 1000.0)
            $sliderViews[$i].Value.Text = ('{0}%' -f [int][Math]::Round($level * 100.0))
        }
        for ($i = 0; $i -lt $buttonViews.Count; $i++) {
            Set-ButtonIndicatorAppearance -Indicator $buttonViews[$i] -ButtonIndex $i
        }
        for ($i = 0; $i -lt $toggleViews.Count; $i++) {
            $on = (@($script:LatestToggles).Count -gt $i -and [int]$script:LatestToggles[$i] -eq 1)
            $toggleViews[$i].Label.Text = if ($script:Language -eq 'ru') { if ($on) { 'Вкл' } else { 'Выкл' } } else { if ($on) { 'On' } else { 'Off' } }
            if ($null -eq $toggleViews[$i].Last -or [bool]$toggleViews[$i].Last -ne $on) {
                $toggleViews[$i].Last = $on
                $toggleViews[$i].Switch.Invalidate()
            }
        }
        for ($i = 0; $i -lt $encoderViews.Count; $i++) {
            $position = [int64]0
            $hasPush = $false
            $pressed = $false
            if (@($script:LatestEncoders).Count -gt $i) {
                $enc = $script:LatestEncoders[$i]
                $position = [int64]$enc.Position
                $hasPush = [bool]$enc.HasPush
                $pressed = ($hasPush -and [int]$enc.Push -eq 0)
            }
            $encoderViews[$i].Label.Text = [string]$position
            if ($null -eq $encoderViews[$i].LastPosition -or [int64]$encoderViews[$i].LastPosition -ne $position -or $null -eq $encoderViews[$i].LastHasPush -or [bool]$encoderViews[$i].LastHasPush -ne $hasPush -or $null -eq $encoderViews[$i].LastPressed -or [bool]$encoderViews[$i].LastPressed -ne $pressed) {
                $encoderViews[$i].LastPosition = $position
                $encoderViews[$i].LastHasPush = $hasPush
                $encoderViews[$i].LastPressed = $pressed
                $encoderViews[$i].Knob.Invalidate()
            }
        }
    }

    $stateTimer = New-Object System.Windows.Forms.Timer
    $stateTimer.Interval = 75
    $stateTimer.Add_Tick({ & $refreshState })

    try {
        Apply-ThemeToForm -Form $stateForm -ThemeName (Get-EffectiveTheme)
        & $refreshState
        $stateTimer.Start()
        [void]$stateForm.ShowDialog($form)
    }
    finally {
        $stateTimer.Stop()
        $stateTimer.Dispose()
        if (-not $stateForm.IsDisposed) { $stateForm.Dispose() }
    }
}

'@

$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Show-FullControllerStateWindow \{.*?^function Get-MainInputOverflowCount \{' `
    -Replacement ($fullStateUi + 'function Get-MainInputOverflowCount {') `
    -Label 'polish full controller state window'

# ---------------------------------------------------------------------------
# Main-window first-class settings button and compact three-column settings row
# ---------------------------------------------------------------------------

$mainLayout = @'
function Update-AdaptiveInputFeatureUi {
    $metrics = Get-AdaptiveInputStatusLayoutMetrics
    $hasButtons = ($script:IsConnected -and $script:DetectedButtonCount -gt 0)
    $hasAnyInput = ($hasButtons -or [bool]$metrics.HasControls)
    $hasTypedSettings = ($script:IsConnected -and ($metrics.ToggleCount -gt 0 -or $metrics.EncoderCount -gt 0))

    if ($null -ne $script:AdaptiveStateGroup -and -not $script:AdaptiveStateGroup.IsDisposed) {
        $script:AdaptiveStateGroup.Visible = $false
    }

    if ($null -ne $script:ButtonStateGroup -and -not $script:ButtonStateGroup.IsDisposed) {
        $script:ButtonStateGroup.Visible = $hasAnyInput
        if ($hasButtons -and $metrics.HasControls) {
            $script:ButtonStateGroup.Text = if ($script:Language -eq 'ru') { 'Состояние кнопок и переключателей' } else { 'Buttons and controls' }
        }
        elseif ($hasButtons) { $script:ButtonStateGroup.Text = Get-ButtonFeatureText -Key 'ButtonStatus' }
        else { $script:ButtonStateGroup.Text = Get-AdaptiveInputUiText -Key 'Group' }

        foreach ($control in @($script:ToggleStateLabel, $script:ToggleStateFlow, $script:EncoderStateLabel, $script:EncoderStateFlow)) {
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

    if ($null -eq $script:AdaptiveSettingsButton -or $script:AdaptiveSettingsButton.IsDisposed) {
        $script:AdaptiveSettingsButton = New-Object MugenDeejWindowing.MugenButton
        $script:AdaptiveSettingsButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
        $script:AdaptiveSettingsButton.Size = [System.Drawing.Size]::new(196, 42)
        $script:AdaptiveSettingsButton.Add_Click({ Show-AdaptiveControlSettings })
        $form.Controls.Add($script:AdaptiveSettingsButton)
        Apply-ThemeToControl -Control $script:AdaptiveSettingsButton -ThemeName (Get-EffectiveTheme)
    }
    $script:AdaptiveSettingsButton.Text = if ($script:Language -eq 'ru') { 'Тумблеры и энкодеры' } else { 'Toggles & encoders' }
    $script:AdaptiveSettingsButton.Visible = $hasTypedSettings
    $script:AdaptiveSettingsButton.Enabled = $hasTypedSettings

    if ($null -ne $script:ButtonStateFlow -and -not $script:ButtonStateFlow.IsDisposed) { $script:ButtonStateFlow.Visible = $hasButtons }
    if ($null -ne $script:ToggleStateLabel -and -not $script:ToggleStateLabel.IsDisposed) {
        $script:ToggleStateLabel.Text = Get-AdaptiveInputUiText -Key 'Toggles'
        $script:ToggleStateLabel.Visible = ($metrics.ToggleCount -gt 0)
    }
    if ($null -ne $script:ToggleStateFlow -and -not $script:ToggleStateFlow.IsDisposed) { $script:ToggleStateFlow.Visible = ($metrics.ToggleCount -gt 0) }
    if ($null -ne $script:EncoderStateLabel -and -not $script:EncoderStateLabel.IsDisposed) {
        $script:EncoderStateLabel.Text = Get-AdaptiveInputUiText -Key 'Encoders'
        $script:EncoderStateLabel.Visible = ($metrics.EncoderCount -gt 0)
    }
    if ($null -ne $script:EncoderStateFlow -and -not $script:EncoderStateFlow.IsDisposed) { $script:EncoderStateFlow.Visible = ($metrics.EncoderCount -gt 0) }

    $overflow = if ($script:IsConnected) { Get-MainInputOverflowCount } else { 0 }
    if ($null -ne $script:AdaptiveOverflowButton -and -not $script:AdaptiveOverflowButton.IsDisposed) {
        $script:AdaptiveOverflowButton.Visible = ($overflow -gt 0)
        if ($overflow -gt 0) {
            $script:AdaptiveOverflowButton.Text = if ($script:Language -eq 'ru') { ('Показать все… (+{0})' -f $overflow) } else { ('Show all… (+{0})' -f $overflow) }
        }
    }
}

function Set-MainButtonLayout {
    param([Parameter(Mandatory = $true)][bool]$HasButtons)

    if ($null -eq $form -or $null -eq $startupGroup -or $null -eq $advancedToggle -or $null -eq $advancedPanel -or $null -eq $footer) { return }

    $hasSliders = [bool](Update-SliderCapabilityUi)
    $buttonCount = if ($HasButtons) { [int]$script:DetectedButtonCount } else { 0 }
    $buttonMetrics = Get-AdaptiveButtonLayoutMetrics -Count $buttonCount
    $adaptiveMetrics = Get-AdaptiveInputStatusLayoutMetrics
    $hasAnyInput = ($HasButtons -or [bool]$adaptiveMetrics.HasControls)

    # The status card grows when XInput adds its second row. Start the rest
    # of the main content below the actual card bottom rather than a fixed Y.
    $statusPanelVariable = Get-Variable -Name statusPanel -Scope Script -ErrorAction SilentlyContinue
    $mainY = if (
        $null -ne $statusPanelVariable -and
        $null -ne $statusPanelVariable.Value -and
        -not $statusPanelVariable.Value.IsDisposed
    ) {
        [int]$statusPanelVariable.Value.Bottom + 12
    }
    else {
        160
    }
    if ($hasSliders) {
        $knobGroup.Location = [System.Drawing.Point]::new(24, $mainY)
        $mainY += $knobGroup.Height + 12
    }

    $cursorY = 29
    if ($null -ne $script:ButtonStateGroup -and -not $script:ButtonStateGroup.IsDisposed) { $script:ButtonStateGroup.Location = [System.Drawing.Point]::new(24, $mainY) }
    if ($null -ne $script:ButtonStateFlow -and -not $script:ButtonStateFlow.IsDisposed -and $HasButtons) {
        $script:ButtonStateFlow.Location = [System.Drawing.Point]::new(13, $cursorY)
        $script:ButtonStateFlow.Size = [System.Drawing.Size]::new(606, [int]$buttonMetrics.FlowHeight)
        $script:ButtonStateFlow.WrapContents = [bool]$buttonMetrics.Compact
        $script:ButtonStateFlow.AutoScroll = $false
        $cursorY += [int]$buttonMetrics.FlowHeight + 4
    }

    if ($adaptiveMetrics.HasControls) {
        $shareTypedRow = ($adaptiveMetrics.VisibleToggleCount -gt 0 -and $adaptiveMetrics.VisibleEncoderCount -gt 0 -and $adaptiveMetrics.VisibleToggleCount -le 3 -and $adaptiveMetrics.VisibleEncoderCount -le 2)
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

    if ($null -ne $script:AdaptiveStateGroup -and -not $script:AdaptiveStateGroup.IsDisposed) { $script:AdaptiveStateGroup.Visible = $false }
    $advancedPanel.Visible = $false

    $settingsControls = @()
    if ($hasSliders) { $settingsControls += $settingsButton }
    if ($null -ne $script:ButtonSettingsButton -and $script:ButtonSettingsButton.Visible) { $settingsControls += $script:ButtonSettingsButton }
    if ($null -ne $script:AdaptiveSettingsButton -and $script:AdaptiveSettingsButton.Visible) { $settingsControls += $script:AdaptiveSettingsButton }

    if ($settingsControls.Count -gt 0) {
        if ($settingsControls.Count -eq 1) {
            $settingsControls[0].Location = [System.Drawing.Point]::new(24, $mainY)
            $settingsControls[0].Size = [System.Drawing.Size]::new(230, 42)
        }
        elseif ($settingsControls.Count -eq 2) {
            for ($i = 0; $i -lt 2; $i++) {
                $settingsControls[$i].Location = [System.Drawing.Point]::new((24 + ($i * 248)), $mainY)
                $settingsControls[$i].Size = [System.Drawing.Size]::new(230, 42)
            }
        }
        else {
            for ($i = 0; $i -lt 3; $i++) {
                $settingsControls[$i].Location = [System.Drawing.Point]::new((24 + ($i * 204)), $mainY)
                $settingsControls[$i].Size = [System.Drawing.Size]::new(196, 42)
            }
        }

        if ($null -ne $script:SettingsHintControl) {
            $showHint = ($settingsControls.Count -eq 1 -and $hasSliders)
            $script:SettingsHintControl.Visible = $showHint
            if ($showHint) { $script:SettingsHintControl.Location = [System.Drawing.Point]::new(272, ($mainY - 2)) }
        }
        $mainY += 54
    }
    elseif ($null -ne $script:SettingsHintControl) { $script:SettingsHintControl.Visible = $false }

    $startupGroup.Location = [System.Drawing.Point]::new(24, $mainY)
    $mainY += 102
    $advancedToggle.Location = [System.Drawing.Point]::new(24, $mainY)
    if ($null -ne $script:BackupMenuButton -and -not $script:BackupMenuButton.IsDisposed) { $script:BackupMenuButton.Location = [System.Drawing.Point]::new(292, $mainY) }
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
    -Pattern '(?ms)^function Update-AdaptiveInputFeatureUi \{.*?^function Update-ButtonFeatureUi \{' `
    -Replacement ($mainLayout + 'function Update-ButtonFeatureUi {') `
    -Label 'add first-class typed settings button to compact main layout'

# Fresh installs and pre-restore emergency snapshots may legitimately contain
# zero button actions. Mandatory PowerShell collection parameters reject @()
# unless AllowEmptyCollection is explicit, which made both restore and rollback
# fail for an otherwise valid backup.
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
function Write-ButtonActionConfigFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Actions
    )
'@ `
    -NewText @'
function Write-ButtonActionConfigFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Actions
    )
'@ `
    -Label 'allow empty button action config writes'

# ---------------------------------------------------------------------------
# Universal backup schema v2: preserve typed mappings, still read v1 safely
# ---------------------------------------------------------------------------

$backupRead = @'
function Read-MugenDeejBackupFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $data) { throw 'Backup file is empty.' }
    if ([string]$data.format -cne 'MugenDeejBackup') { throw 'This file is not a Mugen Deej backup.' }
    if ($null -eq $data.PSObject.Properties['schemaVersion']) { throw 'Backup schema version is missing.' }
    $schema = [int]$data.schemaVersion
    if ($schema -notin @(1, 2)) { throw ('Unsupported backup schema version: {0}' -f $schema) }
    if ($null -eq $data.PSObject.Properties['config'] -or $null -eq $data.config) { throw 'Backup does not contain the main configuration.' }
    if ($null -eq $data.PSObject.Properties['buttonActions'] -or $null -eq $data.buttonActions) { throw 'Backup does not contain button actions.' }
    if ($null -eq $data.buttonActions.PSObject.Properties['version'] -or [int]$data.buttonActions.version -ne 1) { throw 'Unsupported or missing button-action configuration version in backup.' }
    if ($null -eq $data.buttonActions.PSObject.Properties['actions']) { throw 'Backup button-action list is missing.' }
    foreach ($item in @($data.buttonActions.actions)) { if ($null -eq $item) { throw 'Backup button-action list contains a null item.' } }

    if ($schema -eq 2) {
        if ($null -eq $data.PSObject.Properties['adaptiveActions'] -or $null -eq $data.adaptiveActions) { throw 'Backup v2 does not contain Adaptive actions.' }
        if ($null -eq $data.adaptiveActions.PSObject.Properties['version'] -or [int]$data.adaptiveActions.version -ne 1) { throw 'Unsupported Adaptive action schema in backup.' }
        if ($null -eq $data.adaptiveActions.PSObject.Properties['toggles'] -or $null -eq $data.adaptiveActions.PSObject.Properties['encoders']) { throw 'Backup Adaptive action payload is incomplete.' }

        if ($null -ne $data.PSObject.Properties['adaptiveProfiles'] -and $null -ne $data.adaptiveProfiles) {
            if ($null -eq $data.adaptiveProfiles.PSObject.Properties['version'] -or [int]$data.adaptiveProfiles.version -ne 1) { throw 'Unsupported Adaptive application-profile schema in backup.' }
            if ($null -eq $data.adaptiveProfiles.PSObject.Properties['profiles']) { throw 'Backup Adaptive application-profile list is missing.' }
        }
    }
    return $data
}

'@
$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Read-MugenDeejBackupFile \{.*?^function New-MugenDeejBackupSnapshot \{' `
    -Replacement ($backupRead + 'function New-MugenDeejBackupSnapshot {') `
    -Label 'read universal backup schemas v1 and v2'

$backupSnapshot = @'
function New-MugenDeejBackupSnapshot {
    Initialize-ButtonActions
    Initialize-AdaptiveActions
    Initialize-AdaptiveProfiles

    $configClone = $script:Config | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $actions = @($script:ButtonActions | ForEach-Object { [string]$_ })
    $typedToggles = @($script:AdaptiveToggleActions | ForEach-Object { [pscustomobject][ordered]@{ on = [string]$_.on; off = [string]$_.off } })
    $typedEncoders = @($script:AdaptiveEncoderActions | ForEach-Object { [pscustomobject][ordered]@{ cw = [string]$_.cw; ccw = [string]$_.ccw; push = [string]$_.push } })
    $typedProfiles = @(
        $script:AdaptiveProfiles | ForEach-Object {
            [pscustomobject][ordered]@{
                name = [string]$_.name
                process = [string]$_.process
                buttons = @(Copy-AdaptiveProfileButtons -Items @($_.buttons))
                toggles = @(Copy-AdaptiveProfileToggles -Items @($_.toggles))
                encoders = @(Copy-AdaptiveProfileEncoders -Items @($_.encoders))
            }
        }
    )

    return [pscustomobject][ordered]@{
        format = 'MugenDeejBackup'
        schemaVersion = 2
        createdAt = (Get-Date).ToString('o')
        createdBy = $script:AppVersion
        sourceController = [pscustomobject][ordered]@{
            protocol = [string]$script:ControllerProtocol
            sliders = [int]$script:DetectedSliderCount
            buttons = [int]$script:DetectedButtonCount
            toggles = [int]$script:DetectedToggleCount
            encoders = [int]$script:DetectedEncoderCount
        }
        config = $configClone
        buttonActions = [pscustomobject][ordered]@{ version = 1; actions = @($actions) }
        adaptiveActions = [pscustomobject][ordered]@{ version = 1; toggles = @($typedToggles); encoders = @($typedEncoders) }
        adaptiveProfiles = [pscustomobject][ordered]@{ version = 1; profiles = @($typedProfiles) }
    }
}

'@
$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function New-MugenDeejBackupSnapshot \{.*?^function Write-MugenDeejBackupFile \{' `
    -Replacement ($backupSnapshot + 'function Write-MugenDeejBackupFile {') `
    -Label 'write universal backup schema v2'

$backupRestore = @'
function Restore-MugenDeejBackupInteractive {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = (T -Key 'BackupOpenTitle')
    $dialog.Filter = 'Mugen Deej backup (*.backup)|*.backup|All files (*.*)|*.*'
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false
    if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try { $backup = Read-MugenDeejBackupFile -Path $dialog.FileName }
    catch {
        Write-Log ('Backup validation failed: {0}' -f $_.Exception.Message) 'WARN'
        [void](Show-MugenDeejStyledDialog -Message ((T -Key 'BackupInvalid') + "`r`n`r`n" + $_.Exception.Message) -Buttons 'OK' -Kind 'Warning')
        return
    }

    $schema = [int]$backup.schemaVersion
    $compatibility = ''
    if ($schema -eq 2 -and $null -ne $backup.PSObject.Properties['sourceController']) {
        $src = $backup.sourceController
        $current = if ($script:IsConnected) {
            '{0} — {1}/{2}/{3}/{4}' -f (Get-ControllerProtocolDisplayText), $script:DetectedSliderCount, $script:DetectedButtonCount, $script:DetectedToggleCount, $script:DetectedEncoderCount
        }
        else { $(if ($script:Language -eq 'ru') { 'контроллер не подключён' } else { 'no controller connected' }) }
        $sourceProtocol = if ([string]$src.protocol -eq 'adaptive') { 'Adaptive v3' } elseif ([string]$src.protocol -eq 'extended') { 'Extended' } elseif ([string]$src.protocol -eq 'legacy') { 'Legacy' } else { 'Unknown' }
        $compatibility = if ($script:Language -eq 'ru') {
            "`r`n`r`nБэкап создан при: $sourceProtocol — $($src.sliders)/$($src.buttons)/$($src.toggles)/$($src.encoders).`r`nСейчас: $current.`r`nОтсутствующие назначения будут сохранены как неактивные."
        }
        else {
            "`r`n`r`nBackup source: $sourceProtocol — $($src.sliders)/$($src.buttons)/$($src.toggles)/$($src.encoders).`r`nCurrent: $current.`r`nMappings for absent controls will remain dormant."
        }
    }

    $confirmation = Show-MugenDeejStyledDialog -Message ((T -Key 'BackupRestoreConfirm') + $compatibility) -Buttons 'YesNo' -Kind 'Warning'
    if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    Initialize-ButtonActions
    Initialize-AdaptiveActions
    $preRestoreSnapshot = New-MugenDeejBackupSnapshot
    $preRestorePath = Join-Path $script:BaseDir ('MugenDeej_PreRestore_{0}.backup' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    try { Write-MugenDeejBackupFile -Path $preRestorePath -Snapshot $preRestoreSnapshot }
    catch {
        Write-Log ('Restore aborted because emergency backup could not be created: {0}' -f $_.Exception.Message) 'ERROR'
        [void](Show-MugenDeejStyledDialog -Message ((T -Key 'BackupRestoreFailed') + "`r`n`r`n" + $_.Exception.Message) -Buttons 'OK' -Kind 'Error')
        return
    }

    try {
        $configClone = $backup.config | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $restoredConfig = Ensure-ConfigShape -Config $configClone
        $restoredActions = @($backup.buttonActions.actions | ForEach-Object { [string]$_ })

        Save-Config -Config $restoredConfig
        Write-ButtonActionConfigFile -Path $script:ButtonActionConfigPath -Actions $restoredActions

        if ($schema -eq 2) {
            $restoredToggles = @($backup.adaptiveActions.toggles | ForEach-Object { [pscustomobject][ordered]@{ on = [string]$_.on; off = [string]$_.off } })
            $restoredEncoders = @($backup.adaptiveActions.encoders | ForEach-Object { [pscustomobject][ordered]@{ cw = [string]$_.cw; ccw = [string]$_.ccw; push = [string]$_.push } })
            Write-AdaptiveActionConfigFile -Path $script:AdaptiveActionConfigPath -Toggles $restoredToggles -Encoders $restoredEncoders
            $script:AdaptiveToggleActions = @($restoredToggles)
            $script:AdaptiveEncoderActions = @($restoredEncoders)
            $script:AdaptiveActionsLoaded = $true

            if ($null -ne $backup.PSObject.Properties['adaptiveProfiles'] -and $null -ne $backup.adaptiveProfiles) {
                $restoredProfiles = @()
                foreach ($profile in @($backup.adaptiveProfiles.profiles)) {
                    $processName = Normalize-TargetName -Value ([string]$profile.process)
                    if ([string]::IsNullOrWhiteSpace($processName)) { continue }
                    $profileButtons = @()
                    if ($null -ne $profile.PSObject.Properties['buttons']) {
                        $profileButtons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
                    }

                    $restoredProfiles += [pscustomobject][ordered]@{
                        name = [string]$profile.name
                        process = $processName
                        buttons = @($profileButtons)
                        toggles = @(Copy-AdaptiveProfileToggles -Items @($profile.toggles))
                        encoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
                    }
                }
                $script:AdaptiveProfiles = @($restoredProfiles)
                $script:AdaptiveProfilesLoaded = $true
                Save-AdaptiveProfiles
                Write-Log ('Adaptive application profiles restored from backup: {0}' -f @($restoredProfiles).Count) 'INFO'
            }
            else {
                Write-Log 'Restored older backup schema v2 without application profiles; current application profiles were preserved.' 'INFO'
            }
        }
        else {
            Write-Log 'Restored backup schema v1: current Adaptive mappings and application profiles were preserved because v1 did not contain those setting families.' 'INFO'
        }

        $script:Config = $restoredConfig
        $script:ButtonActions = @($restoredActions)
        $script:ButtonActionsLoaded = $true
        Write-Log ('Settings restored from backup: {0}; schema={1}; emergencyBackup={2}' -f $dialog.FileName, $schema, $preRestorePath) 'INFO'

        $restartMessage = ((T -Key 'BackupRestored') + "`r`n`r`n" + (T -Key 'BackupEmergencyCopy') + "`r`n" + $preRestorePath + "`r`n`r`n" + (T -Key 'BackupRestartPrompt'))
        $restartResult = Show-MugenDeejStyledDialog -Message $restartMessage -Buttons 'YesNo' -Kind 'Info'
        if ($restartResult -eq [System.Windows.Forms.DialogResult]::Yes) {
            Write-Log 'Restart requested after backup restore.' 'INFO'
            $script:RestartRequested = $true
            $script:Closing = $true
            $script:ExitRequested = $true
            $script:ShutdownFinalizing = $true
            $form.Close()
        }
    }
    catch {
        $restoreError = $_.Exception.Message
        Write-Log ('Restore failed; attempting rollback from emergency backup: {0}' -f $restoreError) 'ERROR'
        try {
            $rollback = Read-MugenDeejBackupFile -Path $preRestorePath
            $rollbackConfig = Ensure-ConfigShape -Config ($rollback.config | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
            $rollbackActions = @($rollback.buttonActions.actions | ForEach-Object { [string]$_ })
            $rollbackToggles = @($rollback.adaptiveActions.toggles | ForEach-Object { [pscustomobject][ordered]@{ on = [string]$_.on; off = [string]$_.off } })
            $rollbackEncoders = @($rollback.adaptiveActions.encoders | ForEach-Object { [pscustomobject][ordered]@{ cw = [string]$_.cw; ccw = [string]$_.ccw; push = [string]$_.push } })
            Save-Config -Config $rollbackConfig
            Write-ButtonActionConfigFile -Path $script:ButtonActionConfigPath -Actions $rollbackActions
            Write-AdaptiveActionConfigFile -Path $script:AdaptiveActionConfigPath -Toggles $rollbackToggles -Encoders $rollbackEncoders
            $script:Config = $rollbackConfig
            $script:ButtonActions = @($rollbackActions)
            $script:ButtonActionsLoaded = $true
            $script:AdaptiveToggleActions = @($rollbackToggles)
            $script:AdaptiveEncoderActions = @($rollbackEncoders)
            $script:AdaptiveActionsLoaded = $true

            if ($null -ne $rollback.PSObject.Properties['adaptiveProfiles'] -and $null -ne $rollback.adaptiveProfiles) {
                $rollbackProfiles = @()
                foreach ($profile in @($rollback.adaptiveProfiles.profiles)) {
                    $processName = Normalize-TargetName -Value ([string]$profile.process)
                    if ([string]::IsNullOrWhiteSpace($processName)) { continue }
                    $profileButtons = @()
                    if ($null -ne $profile.PSObject.Properties['buttons']) {
                        $profileButtons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
                    }

                    $rollbackProfiles += [pscustomobject][ordered]@{
                        name = [string]$profile.name
                        process = $processName
                        buttons = @($profileButtons)
                        toggles = @(Copy-AdaptiveProfileToggles -Items @($profile.toggles))
                        encoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
                    }
                }
                $script:AdaptiveProfiles = @($rollbackProfiles)
                $script:AdaptiveProfilesLoaded = $true
                Save-AdaptiveProfiles
            }

            Write-Log 'Rollback after failed restore completed successfully.' 'WARN'
        }
        catch { Write-Log ('Rollback after failed restore also failed: {0}' -f $_.Exception.Message) 'ERROR' }
        [void](Show-MugenDeejStyledDialog -Message ((T -Key 'BackupRestoreFailed') + "`r`n`r`n" + $restoreError) -Buttons 'OK' -Kind 'Error')
    }
}

'@
$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Restore-MugenDeejBackupInteractive \{.*?^function Show-MugenDeejBackupMenu \{' `
    -Replacement ($backupRestore + 'function Show-MugenDeejBackupMenu {') `
    -Label 'restore Adaptive mappings from universal backup v2'

# Push-capable encoders use a persistent center dot. Rotation-only encoders
# remain plain knobs, while an active push still lights the whole knob.
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
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
'@ `
    -NewText @'
                $position = [int64]0
                $hasPush = $false
                $pressed = $false
                if (@($script:LatestEncoders).Count -gt $index) {
                    $currentEncoder = $script:LatestEncoders[$index]
                    if ($null -ne $currentEncoder) {
                        $position = [int64]$currentEncoder.Position
                        $hasPush = [bool]$currentEncoder.HasPush
                        $pressed = (
                            $hasPush -and
                            [int]$currentEncoder.Push -eq 0
                        )
                    }
                }
'@ `
    -Label 'read encoder push capability in compact knob'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
                try {
                    $eventArgs.Graphics.FillEllipse($fillBrush, 2, 2, 23, 23)
                    $eventArgs.Graphics.DrawEllipse($borderPen, 2, 2, 23, 23)
                }
'@ `
    -NewText @'
                try {
                    $eventArgs.Graphics.FillEllipse($fillBrush, 2, 2, 24, 24)
                    $eventArgs.Graphics.DrawEllipse($borderPen, 2, 2, 24, 24)
                }
'@ `
    -Label 'center compact encoder outer knob'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
                $centerX = 13.5
                $centerY = 13.5
                $innerRadius = 3.5
                $outerRadius = 9.0
'@ `
    -NewText @'
                $centerX = 14.0
                $centerY = 14.0
                $innerRadius = if ($hasPush) { 5.5 } else { 3.5 }
                $outerRadius = 9.0
'@ `
    -Label 'center compact encoder marker'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
                finally {
                    $markerPen.Dispose()
                }
            })
'@ `
    -NewText @'
                finally {
                    $markerPen.Dispose()
                }

                if ($hasPush) {
                    $pushCueColor = if ($pressed) { $palette.AccentText } else { $palette.Accent }
                    $pushCuePen = New-Object System.Drawing.Pen($pushCueColor, 1.5)
                    try {
                        $eventArgs.Graphics.DrawEllipse($pushCuePen, 11, 11, 6, 6)
                        if ($pressed) {
                            $pushCueBrush = New-Object System.Drawing.SolidBrush($pushCueColor)
                            try {
                                $eventArgs.Graphics.FillEllipse($pushCueBrush, 12, 12, 4, 4)
                            }
                            finally {
                                $pushCueBrush.Dispose()
                            }
                        }
                    }
                    finally {
                        $pushCuePen.Dispose()
                    }
                }
            })
'@ `
    -Label 'draw compact encoder push capability dot'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
                LastPosition = $null
                LastPressed = $null
                LastTheme = ''
'@ `
    -NewText @'
                LastPosition = $null
                LastHasPush = $null
                LastPressed = $null
                LastTheme = ''
'@ `
    -Label 'track compact encoder push capability'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
            $null -eq $view.LastPressed -or
            [bool]$view.LastPressed -ne $pressed -or
            [string]$view.LastTheme -ne $themeKey
'@ `
    -NewText @'
            $null -eq $view.LastHasPush -or
            [bool]$view.LastHasPush -ne $hasPush -or
            $null -eq $view.LastPressed -or
            [bool]$view.LastPressed -ne $pressed -or
            [string]$view.LastTheme -ne $themeKey
'@ `
    -Label 'invalidate compact encoder when push capability changes'

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText @'
            $view.LastPosition = $position
            $view.LastPressed = $pressed
            $view.LastTheme = $themeKey
'@ `
    -NewText @'
            $view.LastPosition = $position
            $view.LastHasPush = $hasPush
            $view.LastPressed = $pressed
            $view.LastTheme = $themeKey
'@ `
    -Label 'remember compact encoder push capability'

# First-run onboarding must describe the controller that was actually
# detected. The legacy wizard hardcoded five analog controls and could route a
# zero-slider Adaptive controller into an empty slider settings form.
$firstRunWizard = @'
function Show-FirstRunWizard {
    $wizard = New-Object System.Windows.Forms.Form
    $wizard.Text = (T -Key 'WizardTitle')
    $wizard.StartPosition = 'CenterParent'
    $wizard.ClientSize = New-Object System.Drawing.Size(660, 452)
    $wizard.MinimumSize = New-Object System.Drawing.Size(676, 491)
    $wizard.MaximumSize = New-Object System.Drawing.Size(676, 491)
    $wizard.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $wizard.FormBorderStyle = 'FixedDialog'
    $wizard.MaximizeBox = $false
    $wizard.MinimizeBox = $false
    Set-FormAppIcon -Form $wizard

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = (T -Key 'WizardHeading')
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 17)
    $heading.AutoSize = $true
    $heading.Location = New-Object System.Drawing.Point(24, 20)
    $wizard.Controls.Add($heading)

    # Use single-line labels instead of wrapped paragraphs so the vertical rhythm
    # is identical in RU and EN.
    $introLine1 = New-Object System.Windows.Forms.Label
    $introLine1.Location = New-Object System.Drawing.Point(27, 62)
    $introLine1.Size = New-Object System.Drawing.Size(606, 22)
    $wizard.Controls.Add($introLine1)

    $introLine2 = New-Object System.Windows.Forms.Label
    $introLine2.Location = New-Object System.Drawing.Point(27, 84)
    $introLine2.Size = New-Object System.Drawing.Size(606, 22)
    $wizard.Controls.Add($introLine2)

    # A card + explicit title keeps every line on the same left edge.
    $controllerCard = New-Object MugenDeejWindowing.MugenCardPanel
    $controllerCard.Location = New-Object System.Drawing.Point(24, 122)
    $controllerCard.Size = New-Object System.Drawing.Size(612, 126)
    $wizard.Controls.Add($controllerCard)

    $controllerTitle = New-Object System.Windows.Forms.Label
    $controllerTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $controllerTitle.Location = New-Object System.Drawing.Point(16, 12)
    $controllerTitle.Size = New-Object System.Drawing.Size(580, 22)
    $controllerCard.Controls.Add($controllerTitle)

    # Keep connected and disconnected card contents in separate panels.
    # This lets resume/disconnect switch the whole card atomically instead of
    # toggling Visible on a collection of individual labels from a timer tick.
    $connectedDetailsPanel = New-Object System.Windows.Forms.Panel
    $connectedDetailsPanel.Tag = 'MugenCardInner'
    $connectedDetailsPanel.Location = New-Object System.Drawing.Point(16, 37)
    $connectedDetailsPanel.Size = New-Object System.Drawing.Size(580, 74)
    $controllerCard.Controls.Add($connectedDetailsPanel)

    $waitingPanel = New-Object System.Windows.Forms.Panel
    $waitingPanel.Tag = 'MugenCardInner'
    $waitingPanel.Location = New-Object System.Drawing.Point(16, 37)
    $waitingPanel.Size = New-Object System.Drawing.Size(580, 74)
    $waitingPanel.Visible = $false
    $controllerCard.Controls.Add($waitingPanel)

    $portName = New-Object System.Windows.Forms.Label
    $portName.Location = New-Object System.Drawing.Point(0, 6)
    $portName.Size = New-Object System.Drawing.Size(42, 22)
    $connectedDetailsPanel.Controls.Add($portName)

    $portValue = New-Object System.Windows.Forms.Label
    $portValue.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $portValue.Location = New-Object System.Drawing.Point(42, 6)
    $portValue.Size = New-Object System.Drawing.Size(82, 22)
    $connectedDetailsPanel.Controls.Add($portValue)

    $protocolName = New-Object System.Windows.Forms.Label
    $protocolName.Location = New-Object System.Drawing.Point(132, 6)
    $protocolName.Size = New-Object System.Drawing.Size(76, 22)
    $connectedDetailsPanel.Controls.Add($protocolName)

    $protocolValue = New-Object System.Windows.Forms.Label
    $protocolValue.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $protocolValue.Location = New-Object System.Drawing.Point(208, 6)
    $protocolValue.Size = New-Object System.Drawing.Size(112, 22)
    $connectedDetailsPanel.Controls.Add($protocolValue)

    $baudName = New-Object System.Windows.Forms.Label
    $baudName.Location = New-Object System.Drawing.Point(332, 6)
    $baudName.Size = New-Object System.Drawing.Size(78, 22)
    $connectedDetailsPanel.Controls.Add($baudName)

    $baudValue = New-Object System.Windows.Forms.Label
    $baudValue.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $baudValue.Location = New-Object System.Drawing.Point(410, 6)
    $baudValue.Size = New-Object System.Drawing.Size(164, 22)
    $connectedDetailsPanel.Controls.Add($baudValue)

    $capabilityLabel = New-Object System.Windows.Forms.Label
    $capabilityLabel.Location = New-Object System.Drawing.Point(0, 39)
    $capabilityLabel.Size = New-Object System.Drawing.Size(574, 22)
    $connectedDetailsPanel.Controls.Add($capabilityLabel)

    $waitingLabel = New-Object System.Windows.Forms.Label
    $waitingLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $waitingLabel.Location = New-Object System.Drawing.Point(0, 8)
    $waitingLabel.Size = New-Object System.Drawing.Size(574, 22)
    $waitingPanel.Controls.Add($waitingLabel)

    $waitingHint = New-Object System.Windows.Forms.Label
    $waitingHint.Location = New-Object System.Drawing.Point(0, 39)
    $waitingHint.Size = New-Object System.Drawing.Size(574, 22)
    $waitingPanel.Controls.Add($waitingHint)

    $nextHintLine1 = New-Object System.Windows.Forms.Label
    $nextHintLine1.ForeColor = [System.Drawing.Color]::DimGray
    $nextHintLine1.Location = New-Object System.Drawing.Point(27, 266)
    $nextHintLine1.Size = New-Object System.Drawing.Size(606, 22)
    $wizard.Controls.Add($nextHintLine1)

    $nextHintLine2 = New-Object System.Windows.Forms.Label
    $nextHintLine2.ForeColor = [System.Drawing.Color]::DimGray
    $nextHintLine2.Location = New-Object System.Drawing.Point(27, 288)
    $nextHintLine2.Size = New-Object System.Drawing.Size(606, 22)
    $wizard.Controls.Add($nextHintLine2)

    $nextHintLine3 = New-Object System.Windows.Forms.Label
    $nextHintLine3.ForeColor = [System.Drawing.Color]::FromArgb(230, 170, 70)
    $nextHintLine3.Location = New-Object System.Drawing.Point(27, 310)
    $nextHintLine3.Size = New-Object System.Drawing.Size(606, 22)
    $nextHintLine3.Visible = $false
    $wizard.Controls.Add($nextHintLine3)

    $sliderButton = New-Object MugenDeejWindowing.MugenButton
    $sliderButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $sliderButton.Size = New-Object System.Drawing.Size(188, 38)
    $sliderButton.Visible = $false
    $wizard.Controls.Add($sliderButton)

    $buttonButton = New-Object MugenDeejWindowing.MugenButton
    $buttonButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $buttonButton.Size = New-Object System.Drawing.Size(188, 38)
    $buttonButton.Visible = $false
    $wizard.Controls.Add($buttonButton)

    $typedButton = New-Object MugenDeejWindowing.MugenButton
    $typedButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $typedButton.Size = New-Object System.Drawing.Size(188, 38)
    $typedButton.Visible = $false
    $wizard.Controls.Add($typedButton)

    $laterButton = New-Object MugenDeejWindowing.MugenButton
    $laterButton.Text = (T -Key 'CloseHint')
    $laterButton.Location = New-Object System.Drawing.Point(478, 400)
    $laterButton.Size = New-Object System.Drawing.Size(158, 36)
    $wizard.Controls.Add($laterButton)

    $wizardChoice = [pscustomobject]@{ Value = '' }

    $finishWizard = {
        if (-not [bool]$script:Config.app.firstRunCompleted) {
            $script:Config.app.firstRunCompleted = $true
            Save-Config -Config $script:Config
        }
    }

    $layoutButtons = {
        $available = @()
        if ($sliderButton.Visible) { $available += $sliderButton }
        if ($buttonButton.Visible) { $available += $buttonButton }
        if ($typedButton.Visible) { $available += $typedButton }

        $count = $available.Count
        if ($count -le 0) { return }

        $gap = 12
        $width = 188
        $total = ($count * $width) + (($count - 1) * $gap)
        $startX = [int][Math]::Floor((660 - $total) / 2)
        for ($i = 0; $i -lt $count; $i++) {
            $available[$i].Location = New-Object System.Drawing.Point(($startX + ($i * ($width + $gap))), 348)
        }
    }

    $refreshWizard = {
        $ru = ($script:Language -eq 'ru')
        $connected = [bool]$script:IsConnected
        $sliders = if ($connected) { [int]$script:DetectedSliderCount } else { 0 }
        $buttons = if ($connected) { [int]$script:DetectedButtonCount } else { 0 }
        $toggles = if ($connected) { [int]$script:DetectedToggleCount } else { 0 }
        $encoders = if ($connected) { [int]$script:DetectedEncoderCount } else { 0 }

        $controllerTitle.Text = if ($ru) { 'Ваш контроллер' } else { 'Your controller' }

        # Short category names fit all three peer buttons in both languages.
        $sliderButton.Text = if ($ru) { 'Регуляторы' } else { 'Analog controls' }
        $buttonButton.Text = if ($ru) { 'Кнопки' } else { 'Buttons' }
        $typedButton.Text = if ($ru) { 'Тумблеры и энкодеры' } else { 'Toggles & encoders' }

        if ($connected) {
            $introLine1.Text = if ($ru) { 'Контроллер найден и готов к работе.' } else { 'Your controller is connected and ready.' }
            $introLine2.Text = if ($ru) {
                'Проверьте органы управления — их состояние сразу видно в главном окне.'
            }
            else {
                'Try the controls — their state appears immediately in the main window.'
            }

            $port = if ([string]::IsNullOrWhiteSpace($script:ConnectedPort)) { '—' } else { $script:ConnectedPort }
            $baud = '—'
            if ($null -ne $script:Serial) {
                try { $baud = [string][int]$script:Serial.BaudRate } catch { }
            }

            $portName.Text = if ($ru) { 'Порт:' } else { 'Port:' }
            $protocolName.Text = if ($ru) { 'Протокол:' } else { 'Protocol:' }
            $baudName.Text = if ($ru) { 'Скорость:' } else { 'Baud:' }
            $portValue.Text = $port
            $protocolValue.Text = Get-ControllerProtocolDisplayText
            $baudValue.Text = if ($ru) { $baud + ' бод' } else { $baud }

            $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
            $normalText = $palette.Text
            foreach ($label in @($portName, $protocolName, $baudName)) {
                $label.ForeColor = $normalText
            }
            foreach ($value in @($portValue, $protocolValue, $baudValue)) {
                $value.ForeColor = [System.Drawing.Color]::SeaGreen
            }

            $capabilityLabel.Text = if ($ru) {
                'Доступно: {0} регуляторов · {1} кнопок · {2} тумблеров · {3} энкодеров' -f $sliders, $buttons, $toggles, $encoders
            }
            else {
                'Available: {0} controls · {1} buttons · {2} toggles · {3} encoders' -f $sliders, $buttons, $toggles, $encoders
            }

            $connectedDetailsPanel.Visible = $true
            $waitingPanel.Visible = $false

            $nextHintLine1.Text = if ($ru) { 'Можно настроить нужные элементы прямо сейчас.' } else { 'You can configure the controls you need right now.' }
            $nextHintLine2.Text = if ($ru) {
                'Или закрыть это окно и вернуться к настройкам позже.'
            }
            else {
                'Or close this window and return to the settings later.'
            }

            $nextHintLine3.Visible = ($sliders -gt 0)
            $nextHintLine3.Text = if ($sliders -gt 0) {
                if ($ru) {
                    'Если регуляторы работают наоборот — включите инверсию направления в «Регуляторах».'
                }
                else {
                    'If the controls move backwards, enable direction inversion in Controls.'
                }
            }
            else { '' }
        }
        else {
            $introLine1.Text = if ($ru) { 'Подключите контроллер по USB.' } else { 'Connect your controller by USB.' }
            $introLine2.Text = if ($ru) {
                'Mugen сам найдёт его и покажет, какие элементы управления доступны.'
            }
            else {
                'Mugen will find it automatically and show which controls are available.'
            }

            $connectedDetailsPanel.Visible = $false
            $waitingPanel.Visible = $true
            $waitingLabel.Text = if ($ru) { 'Жду контроллер…' } else { 'Waiting for controller…' }
            $waitingLabel.ForeColor = [System.Drawing.Color]::DarkOrange
            $waitingHint.Text = if ($ru) {
                'После подключения здесь появится состав контроллера.'
            }
            else {
                'The controller layout will appear here after it connects.'
            }

            $nextHintLine1.Text = if ($ru) {
                'Можно оставить это окно открытым — оно обновится автоматически.'
            }
            else {
                'You can leave this window open — it will update automatically.'
            }
            $nextHintLine2.Text = ''
            $nextHintLine3.Text = ''
            $nextHintLine3.Visible = $false
        }

        $sliderButton.Visible = ($connected -and $sliders -gt 0)
        $buttonButton.Visible = ($connected -and $buttons -gt 0)
        $typedButton.Visible = ($connected -and ($toggles -gt 0 -or $encoders -gt 0))
        & $layoutButtons
    }

    $laterButton.Add_Click({
        & $finishWizard
        $wizard.Close()
    })
    $sliderButton.Add_Click({
        $wizardChoice.Value = 'sliders'
        & $finishWizard
        $wizard.Close()
    })
    $buttonButton.Add_Click({
        $wizardChoice.Value = 'buttons'
        & $finishWizard
        $wizard.Close()
    })
    $typedButton.Add_Click({
        $wizardChoice.Value = 'typed'
        & $finishWizard
        $wizard.Close()
    })

    $wizardTimer = New-Object System.Windows.Forms.Timer
    $wizardTimer.Interval = 150
    $wizardTimer.Add_Tick({
        try {
            & $refreshWizard
        }
        catch {
            # A first-run helper must never surface a WinForms JIT exception.
            # Stop only this helper timer and keep the main application alive.
            Write-Log ('First-run wizard refresh failed: {0}' -f (Get-ExceptionDiagnosticText -ErrorRecord $_)) 'WARN'
            $wizardTimer.Stop()
        }
    })

    Apply-ThemeToForm -Form $wizard -ThemeName (Get-EffectiveTheme)
    & $refreshWizard
    $wizard.Add_Shown({
        Ensure-FormVisible -Form $wizard -CenterIfOffscreen
        $wizardTimer.Start()
    })
    $wizard.Add_FormClosing({
        if (-not [bool]$script:Config.app.firstRunCompleted) { & $finishWizard }
    })
    $wizard.Add_FormClosed({
        $wizardTimer.Stop()
        $wizardTimer.Dispose()
    })

    [void]$wizard.ShowDialog($form)
    $wizard.Dispose()

    switch ([string]$wizardChoice.Value) {
        'sliders' { Show-SliderSettings }
        'buttons' { Show-ButtonSettings }
        'typed' { Show-AdaptiveControlSettings }
    }
}

'@

$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Show-FirstRunWizard \{.*?^function Get-PortNames \{' `
    -Replacement ($firstRunWizard + 'function Get-PortNames {') `
    -Label 'make first-run wizard capability driven'

# Keep direct calls to the slider editor safe as well. The main-window slider
# button is already capability-driven, but tray/legacy entry points can call the
# editor directly.
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText 'function Show-SliderSettings {' `
    -NewText @'
function Show-SliderSettings {
    if ($script:IsConnected -and [int]$script:DetectedSliderCount -le 0) {
        $message = if ($script:Language -eq 'ru') {
            'У подключённого контроллера нет физических регуляторов.'
        }
        else {
            'The connected controller does not expose any physical analog controls.'
        }
        [void](Show-MugenDeejStyledDialog -Message $message -Buttons 'OK' -Kind 'Info')
        return
    }
'@ `
    -Label 'guard slider settings for zero-slider controllers'

# Use short category labels for the three peer settings buttons.
$text = $text.Replace(
    '$settingsButton.Text = (T -Key ''ConfigureKnobs'')',
    '$settingsButton.Text = if ($script:Language -eq ''ru'') { ''Регуляторы'' } else { ''Analog controls'' }'
)
$text = $text.Replace(
    '$script:ButtonSettingsButton.Text = Get-ButtonFeatureText -Key ''MainButton''',
    '$script:ButtonSettingsButton.Text = if ($script:Language -eq ''ru'') { ''Кнопки'' } else { ''Buttons'' }'
)
$text = $text.Replace(
    '$buttonSettingsButton.Text = Get-ButtonFeatureText -Key ''MainButton''',
    '$buttonSettingsButton.Text = if ($script:Language -eq ''ru'') { ''Кнопки'' } else { ''Buttons'' }'
)

# The three main Configure buttons are peers. Keep all of them neutral rather
# than making regulator settings look like the single preferred action.
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText '$settingsButton.Tag = ''MugenPrimary''' `
    -NewText '$settingsButton.Tag = ''''' `
    -Label 'make regulator settings button neutral'

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($resolved, $text, $utf8)
Write-Host "Applied first-class Adaptive mappings, visual full-state UI, and backup v2 support: $resolved"
