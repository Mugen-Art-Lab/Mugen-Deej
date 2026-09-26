Set-StrictMode -Version 2.0

$script:VirtualGamepadConfigPath = Join-Path $script:BaseDir 'virtual-controller.json'
$script:VirtualGamepadConfigLoaded = $false
$script:VirtualGamepadConfig = $null
$script:VirtualGamepadPipe = $null
$script:VirtualGamepadReader = $null
$script:VirtualGamepadWriter = $null
$script:VirtualGamepadHelperProcess = $null
$script:VirtualGamepadActive = $false
$script:VirtualGamepadStarting = $false
$script:VirtualGamepadStartWaitHandle = $null
$script:VirtualGamepadStartDeadline = [DateTime]::MinValue
$script:VirtualGamepadStartTimer = $null
$script:VirtualGamepadUiState = 'disabled'
$script:VirtualGamepadUiTimer = $null
$script:VirtualGamepadProfileTimer = $null
$script:VirtualGamepadLastStatusLayoutEnabled = $null
$script:VirtualGamepadLastProtocolAvailable = $null
$script:VirtualGamepadStatusDot = $null
$script:VirtualGamepadStatusLabel = $null
$script:VirtualGamepadToggleButton = $null
$script:VirtualGamepadLastMask = [uint32]::MaxValue
$script:VirtualGamepadLastOutputSignature = ''
$script:VirtualGamepadLastButtonProfileKey = ''
$script:VirtualGamepadCachedButtonProfileContext = $null
$script:VirtualGamepadSuppressedPhysicalButtons = @{}
$script:VirtualGamepadLastPhysicalButtons = @()
$script:VirtualGamepadInputSuspended = $false
$script:VirtualGamepadLastStartFailure = [DateTime]::MinValue
$script:VirtualGamepadStartFailureCooldownSeconds = 20

$script:VirtualGamepadActionBits = @{
    'virtual:xbox:a'  = [uint32]1
    'virtual:xbox:b'  = [uint32]2
    'virtual:xbox:x'  = [uint32]4
    'virtual:xbox:y'  = [uint32]8
    'virtual:xbox:lb' = [uint32]16
    'virtual:xbox:rb' = [uint32]32
    'virtual:xbox:back' = [uint32]64
    'virtual:xbox:start' = [uint32]128
    'virtual:xbox:l3' = [uint32]256
    'virtual:xbox:r3' = [uint32]512
}

$script:VirtualGamepadAxisActions = @{
    'virtual:xbox:lsx:left' = $true
    'virtual:xbox:lsx:right' = $true
    'virtual:xbox:lsy:up' = $true
    'virtual:xbox:lsy:down' = $true
    'virtual:xbox:rsx:left' = $true
    'virtual:xbox:rsx:right' = $true
    'virtual:xbox:rsy:up' = $true
    'virtual:xbox:rsy:down' = $true
}

$script:VirtualGamepadDpadActions = @{
    'virtual:xbox:dpad:left' = $true
    'virtual:xbox:dpad:right' = $true
    'virtual:xbox:dpad:up' = $true
    'virtual:xbox:dpad:down' = $true
}

$script:VirtualGamepadTriggerActions = @{
    'virtual:xbox:lt' = $true
    'virtual:xbox:rt' = $true
}

# The 2.0 product exposes virtual gamepad output only for Adaptive v3.
# Legacy/Extended mappings remain readable for compatibility, but their live
# UI/runtime must not create or advertise a virtual HID device.
function Test-MugenVirtualGamepadProtocolAvailable {
    return ([string]$script:ControllerProtocol -eq 'adaptive')
}


function Ensure-MugenVirtualGamepadStatusUi {
    $panelVariable = Get-Variable -Name statusPanel -Scope Script -ErrorAction SilentlyContinue
    $labelVariable = Get-Variable -Name statusLabel -Scope Script -ErrorAction SilentlyContinue
    $dotVariable = Get-Variable -Name statusDot -Scope Script -ErrorAction SilentlyContinue

    if ($null -eq $panelVariable -or $null -eq $labelVariable -or $null -eq $dotVariable) {
        return $false
    }

    $panel = $panelVariable.Value
    $physicalLabel = $labelVariable.Value
    $physicalDot = $dotVariable.Value

    if (
        $null -eq $panel -or $panel.IsDisposed -or
        $null -eq $physicalLabel -or $physicalLabel.IsDisposed -or
        $null -eq $physicalDot -or $physicalDot.IsDisposed
    ) {
        return $false
    }

    if ($null -eq $script:VirtualGamepadStatusDot -or $script:VirtualGamepadStatusDot.IsDisposed) {
        $script:VirtualGamepadStatusDot = New-Object System.Windows.Forms.Label
        $script:VirtualGamepadStatusDot.Text = '●'
        # Fixed-size centered glyphs avoid Segoe UI baseline drift between the
        # two status rows and remain stable across DPI/font metric changes.
        $script:VirtualGamepadStatusDot.Font = $physicalDot.Font
        $script:VirtualGamepadStatusDot.AutoSize = $false
        $script:VirtualGamepadStatusDot.Size = [System.Drawing.Size]::new(16, 16)
        $script:VirtualGamepadStatusDot.TextAlign = 'MiddleCenter'
        $script:VirtualGamepadStatusDot.Visible = $false
        $panel.Controls.Add($script:VirtualGamepadStatusDot)
    }

    if ($null -eq $script:VirtualGamepadStatusLabel -or $script:VirtualGamepadStatusLabel.IsDisposed) {
        $script:VirtualGamepadStatusLabel = New-Object System.Windows.Forms.Label
        $script:VirtualGamepadStatusLabel.AutoSize = $false
        $script:VirtualGamepadStatusLabel.Size = [System.Drawing.Size]::new(444, 26)
        $script:VirtualGamepadStatusLabel.TextAlign = 'MiddleLeft'
        $script:VirtualGamepadStatusLabel.ForeColor = $physicalLabel.ForeColor
        $script:VirtualGamepadStatusLabel.Visible = $false
        $panel.Controls.Add($script:VirtualGamepadStatusLabel)
    }

    if ($null -eq $script:VirtualGamepadToggleButton -or $script:VirtualGamepadToggleButton.IsDisposed) {
        $script:VirtualGamepadToggleButton = New-Object MugenDeejWindowing.MugenButton
        $script:VirtualGamepadToggleButton.Tag = 'MugenSection'
        $script:VirtualGamepadToggleButton.Size = [System.Drawing.Size]::new(112, 30)
        $script:VirtualGamepadToggleButton.Add_Click({
            try {
                $nextEnabled = -not (Get-MugenVirtualGamepadEnabled)
                Set-MugenVirtualGamepadEnabled -Enabled $nextEnabled
                [void](Sync-MugenVirtualGamepadState -Values @($script:LatestButtons))
                Update-MugenVirtualGamepadStatusUi
            }
            catch {
                Write-Log ('Virtual gamepad main toggle failed: {0}' -f $_.Exception.Message) 'WARN'
            }
        })
        $panel.Controls.Add($script:VirtualGamepadToggleButton)
        try { Apply-ThemeToControl -Control $script:VirtualGamepadToggleButton -ThemeName (Get-EffectiveTheme) } catch { }
    }

    return $true
}

function Set-MugenVirtualGamepadStatusLayout {
    param([Parameter(Mandatory = $true)][bool]$Enabled)

    if (-not (Ensure-MugenVirtualGamepadStatusUi)) { return }

    $panel = (Get-Variable -Name statusPanel -Scope Script).Value
    $physicalLabel = (Get-Variable -Name statusLabel -Scope Script).Value
    $physicalDot = (Get-Variable -Name statusDot -Scope Script).Value

    $targetHeight = if ($Enabled) { 68 } else { 60 }
    $layoutChanged = ($panel.Height -ne $targetHeight)
    $modeChanged = (
        $null -eq $script:VirtualGamepadLastStatusLayoutEnabled -or
        [bool]$script:VirtualGamepadLastStatusLayoutEnabled -ne $Enabled
    )

    if (-not $layoutChanged -and -not $modeChanged) { return }

    $script:VirtualGamepadLastStatusLayoutEnabled = $Enabled
    $panel.Size = [System.Drawing.Size]::new(632, $targetHeight)
    $physicalLabel.AutoEllipsis = $false
    $physicalLabel.TextAlign = 'MiddleLeft'

    if ($Enabled) {
        # Two tightly stacked status rows. Both markers use the same font and
        # X coordinate, so the rows read as one aligned status block.
        $physicalDot.Location = [System.Drawing.Point]::new(15, 9)
        $physicalLabel.Location = [System.Drawing.Point]::new(46, 3)
        $physicalLabel.Size = [System.Drawing.Size]::new(444, 28)

        $script:VirtualGamepadStatusDot.Location = [System.Drawing.Point]::new(15, 37)
        $script:VirtualGamepadStatusLabel.Location = [System.Drawing.Point]::new(46, 31)
        $script:VirtualGamepadStatusLabel.Size = [System.Drawing.Size]::new(444, 28)

        # The toggle belongs to the card as a whole rather than visually
        # hanging from the first status line.
        $script:VirtualGamepadToggleButton.Location = [System.Drawing.Point]::new(506, 31)
    }
    else {
        # Restore the original single-row card height/vertical rhythm when the
        # virtual device is off.
        $physicalDot.Location = [System.Drawing.Point]::new(15, 21)
        $physicalLabel.Location = [System.Drawing.Point]::new(46, 10)
        $physicalLabel.Size = [System.Drawing.Size]::new(444, 38)
        $script:VirtualGamepadToggleButton.Location = [System.Drawing.Point]::new(506, 15)
    }

    try {
        if ($null -ne (Get-Command -Name Set-MainButtonLayout -CommandType Function -ErrorAction SilentlyContinue)) {
            $hasButtons = ($script:IsConnected -and [int]$script:DetectedButtonCount -gt 0)
            Set-MainButtonLayout -HasButtons $hasButtons
        }
    }
    catch {
        Write-Log ('Virtual gamepad status layout refresh failed: {0}' -f $_.Exception.Message) 'WARN'
    }
}

function Update-MugenVirtualGamepadStatusUi {
    if (-not (Ensure-MugenVirtualGamepadStatusUi)) { return }

    $physicalLabel = (Get-Variable -Name statusLabel -Scope Script).Value
    $protocolAvailable = Test-MugenVirtualGamepadProtocolAvailable
    $script:VirtualGamepadLastProtocolAvailable = $protocolAvailable
    $enabled = (
        $protocolAvailable -and
        $script:VirtualGamepadConfigLoaded -and
        $null -ne $script:VirtualGamepadConfig -and
        [bool]$script:VirtualGamepadConfig.enabled
    )

    # Keep the virtual-device row visible whenever this controller supports it,
    # even while output is disabled. This makes the adjacent toggle unambiguous.
    Set-MugenVirtualGamepadStatusLayout -Enabled $protocolAvailable

    if ($null -ne $script:VirtualGamepadToggleButton -and -not $script:VirtualGamepadToggleButton.IsDisposed) {
        $script:VirtualGamepadToggleButton.Visible = $protocolAvailable
        $script:VirtualGamepadToggleButton.Text = if ($script:Language -eq 'ru') {
            if ($enabled) { 'XInput: Вкл' } else { 'XInput: Выкл' }
        }
        else {
            if ($enabled) { 'XInput: On' } else { 'XInput: Off' }
        }
    }

    if (-not $protocolAvailable) {
        $script:VirtualGamepadStatusDot.Visible = $false
        $script:VirtualGamepadStatusLabel.Visible = $false
        return
    }

    $script:VirtualGamepadStatusDot.Visible = $true
    $script:VirtualGamepadStatusLabel.Visible = $true
    $script:VirtualGamepadStatusLabel.ForeColor = $physicalLabel.ForeColor

    $ru = ($script:Language -eq 'ru')
    if (-not $enabled) {
        $script:VirtualGamepadStatusLabel.Text = if ($ru) { 'Виртуальный геймпад · выключен' } else { 'Virtual gamepad · disabled' }
        $script:VirtualGamepadStatusDot.ForeColor = [System.Drawing.Color]::Gray
        return
    }

    $text = if ($ru) { 'Виртуальный геймпад · включён · ожидает контроллер' } else { 'Virtual gamepad · enabled · waiting for controller' }
    $color = [System.Drawing.Color]::Gray

    switch ($script:VirtualGamepadUiState) {
        'starting' {
            $text = if ($ru) { 'Виртуальный геймпад · включается…' } else { 'Virtual gamepad · enabling…' }
            $color = [System.Drawing.Color]::RoyalBlue
        }
        'ready' {
            $text = if ($ru) { 'Виртуальный геймпад · включён' } else { 'Virtual gamepad · enabled' }
            $color = [System.Drawing.Color]::SeaGreen
        }
        'error' {
            $text = if ($ru) { 'Виртуальный геймпад · ошибка запуска' } else { 'Virtual gamepad · startup failed' }
            $color = [System.Drawing.Color]::Firebrick
        }
        default {
            $text = if ($ru) { 'Виртуальный геймпад · включён · ожидает контроллер' } else { 'Virtual gamepad · enabled · waiting for controller' }
            $color = [System.Drawing.Color]::Gray
        }
    }

    if ($script:VirtualGamepadStatusLabel.Text -ne $text) {
        $script:VirtualGamepadStatusLabel.Text = $text
    }
    $script:VirtualGamepadStatusDot.ForeColor = $color
}

function Refresh-MugenVirtualGamepadLocalizedStatus {
    if (-not (Ensure-MugenVirtualGamepadStatusUi)) { return }

    try {
        if (
            $script:IsConnected -and
            -not [string]::IsNullOrWhiteSpace([string]$script:ConnectedPort) -and
            $null -ne (Get-Command -Name Get-ControllerConnectedStatusText -CommandType Function -ErrorAction SilentlyContinue)
        ) {
            $physicalLabel = (Get-Variable -Name statusLabel -Scope Script).Value
            $physicalLabel.Text = Get-ControllerConnectedStatusText -PortName ([string]$script:ConnectedPort)
        }
    }
    catch { }

    Update-MugenVirtualGamepadStatusUi
}

function Set-MugenVirtualGamepadUiState {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('disabled','waiting','starting','ready','error')]
        [string]$State
    )

    # Serial heartbeats repeat the same complete button state at ~25 ms.
    # Do not rebuild/repaint the status card when the lifecycle state did not
    # actually change.
    if ([string]$script:VirtualGamepadUiState -eq $State) { return }

    $script:VirtualGamepadUiState = $State
    try { Update-MugenVirtualGamepadStatusUi } catch { }
}

function Ensure-MugenVirtualGamepadUiTimer {
    if ($null -ne $script:VirtualGamepadUiTimer) { return }

    # This timer only waits for the base WinForms status card to exist. Once
    # the integration controls are attached, all further updates are driven by
    # explicit state/language/theme events; there is no reason to repaint the
    # card forever while XInput is off.
    $script:VirtualGamepadUiTimer = New-Object System.Windows.Forms.Timer
    $script:VirtualGamepadUiTimer.Interval = 250
    $script:VirtualGamepadUiTimer.Add_Tick({
        try {
            Initialize-MugenVirtualGamepadConfig
            if (Ensure-MugenVirtualGamepadStatusUi) {
                Update-MugenVirtualGamepadStatusUi
                $script:VirtualGamepadUiTimer.Stop()
            }
        }
        catch { }
    })
    $script:VirtualGamepadUiTimer.Start()
}

function New-MugenVirtualGamepadConfig {
    return [pscustomobject][ordered]@{
        configVersion = 1
        enabled = $false
        type = 'xbox360'
    }
}

function Initialize-MugenVirtualGamepadConfig {
    if ($script:VirtualGamepadConfigLoaded) { return }

    $script:VirtualGamepadConfigLoaded = $true
    $script:VirtualGamepadConfig = New-MugenVirtualGamepadConfig

    if (-not (Test-Path -LiteralPath $script:VirtualGamepadConfigPath -PathType Leaf)) {
        $script:VirtualGamepadUiState = 'disabled'
        return
    }

    try {
        $loaded = Get-Content -LiteralPath $script:VirtualGamepadConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $enabled = $false
        try { $enabled = [bool]$loaded.enabled } catch { }

        $type = 'xbox360'
        try {
            $candidateType = ([string]$loaded.type).Trim().ToLowerInvariant()
            if ($candidateType -eq 'xbox360') { $type = $candidateType }
        }
        catch { }

        $script:VirtualGamepadConfig = [pscustomobject][ordered]@{
            configVersion = 1
            enabled = $enabled
            type = $type
        }
        $script:VirtualGamepadUiState = $(if ($enabled) { 'waiting' } else { 'disabled' })
    }
    catch {
        Write-Log ('Virtual controller config could not be read; using defaults: {0}' -f $_.Exception.Message) 'WARN'
        $script:VirtualGamepadConfig = New-MugenVirtualGamepadConfig
        $script:VirtualGamepadUiState = 'disabled'
    }
}

function Save-MugenVirtualGamepadConfig {
    Initialize-MugenVirtualGamepadConfig

    $json = $script:VirtualGamepadConfig | ConvertTo-Json -Depth 4
    $tempPath = $script:VirtualGamepadConfigPath + '.tmp'
    $utf8 = New-Object System.Text.UTF8Encoding($false)

    try {
        [System.IO.File]::WriteAllText($tempPath, ($json + "`r`n"), $utf8)
        if (Test-Path -LiteralPath $script:VirtualGamepadConfigPath -PathType Leaf) {
            $backupPath = $script:VirtualGamepadConfigPath + '.previous'
            try {
                [System.IO.File]::Replace($tempPath, $script:VirtualGamepadConfigPath, $backupPath, $true)
            }
            catch {
                Copy-Item -LiteralPath $script:VirtualGamepadConfigPath -Destination $backupPath -Force -ErrorAction SilentlyContinue
                Move-Item -LiteralPath $tempPath -Destination $script:VirtualGamepadConfigPath -Force
            }
        }
        else {
            Move-Item -LiteralPath $tempPath -Destination $script:VirtualGamepadConfigPath -Force
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-MugenVirtualGamepadEnabled {
    Initialize-MugenVirtualGamepadConfig
    return [bool]$script:VirtualGamepadConfig.enabled
}

function Set-MugenVirtualGamepadEnabled {
    param([Parameter(Mandatory = $true)][bool]$Enabled)

    Initialize-MugenVirtualGamepadConfig
    $script:VirtualGamepadConfig.enabled = $Enabled
    Save-MugenVirtualGamepadConfig

    if (-not $Enabled -or -not (Test-MugenVirtualGamepadProtocolAvailable)) {
        Set-MugenVirtualGamepadUiState -State 'disabled'
        try { Update-MugenVirtualGamepadStatusUi } catch { }
    }
    elseif ($script:VirtualGamepadActive) {
        Set-MugenVirtualGamepadUiState -State 'ready'
    }
    elseif ($script:VirtualGamepadStarting) {
        Set-MugenVirtualGamepadUiState -State 'starting'
    }
    else {
        Set-MugenVirtualGamepadUiState -State 'waiting'
    }

    Write-Log ('Virtual controller setting changed: enabled={0}; type={1}' -f $Enabled, $script:VirtualGamepadConfig.type) 'INFO'
}

function Test-MugenVirtualGamepadAction {
    param([string]$Action)
    if ([string]::IsNullOrWhiteSpace($Action)) { return $false }

    $normalized = $Action.ToLowerInvariant()
    return (
        $script:VirtualGamepadActionBits.ContainsKey($normalized) -or
        $script:VirtualGamepadAxisActions.ContainsKey($normalized) -or
        $script:VirtualGamepadDpadActions.ContainsKey($normalized) -or
        $script:VirtualGamepadTriggerActions.ContainsKey($normalized)
    )
}

function Get-MugenVirtualGamepadActionDefinitions {
    $ru = ($script:Language -eq 'ru')
    $prefix = if ($ru) { 'Геймпад' } else { 'Gamepad' }

    return @(
        [pscustomobject]@{ Action = 'virtual:xbox:a';     Display = "$prefix — A" },
        [pscustomobject]@{ Action = 'virtual:xbox:b';     Display = "$prefix — B" },
        [pscustomobject]@{ Action = 'virtual:xbox:x';     Display = "$prefix — X" },
        [pscustomobject]@{ Action = 'virtual:xbox:y';     Display = "$prefix — Y" },
        [pscustomobject]@{ Action = 'virtual:xbox:lb';    Display = "$prefix — LB" },
        [pscustomobject]@{ Action = 'virtual:xbox:rb';    Display = "$prefix — RB" },
        [pscustomobject]@{ Action = 'virtual:xbox:lt';    Display = "$prefix — LT (100%)" },
        [pscustomobject]@{ Action = 'virtual:xbox:rt';    Display = "$prefix — RT (100%)" },
        [pscustomobject]@{ Action = 'virtual:xbox:back';  Display = $(if ($ru) { "$prefix — Назад / View" } else { "$prefix — Back / View" }) },
        [pscustomobject]@{ Action = 'virtual:xbox:start'; Display = $(if ($ru) { "$prefix — Старт / Menu" } else { "$prefix — Start / Menu" }) },
        [pscustomobject]@{ Action = 'virtual:xbox:l3';    Display = "$prefix — L3" },
        [pscustomobject]@{ Action = 'virtual:xbox:r3';    Display = "$prefix — R3" },
        [pscustomobject]@{ Action = 'virtual:xbox:lsx:left';  Display = $(if ($ru) { "$prefix — левый стик ←" } else { "$prefix — left stick ←" }) },
        [pscustomobject]@{ Action = 'virtual:xbox:lsx:right'; Display = $(if ($ru) { "$prefix — левый стик →" } else { "$prefix — left stick →" }) },
        [pscustomobject]@{ Action = 'virtual:xbox:lsy:up';    Display = $(if ($ru) { "$prefix — левый стик ↑" } else { "$prefix — left stick ↑" }) },
        [pscustomobject]@{ Action = 'virtual:xbox:lsy:down';  Display = $(if ($ru) { "$prefix — левый стик ↓" } else { "$prefix — left stick ↓" }) },
        [pscustomobject]@{ Action = 'virtual:xbox:rsx:left';  Display = $(if ($ru) { "$prefix — правый стик ←" } else { "$prefix — right stick ←" }) },
        [pscustomobject]@{ Action = 'virtual:xbox:rsx:right'; Display = $(if ($ru) { "$prefix — правый стик →" } else { "$prefix — right stick →" }) },
        [pscustomobject]@{ Action = 'virtual:xbox:rsy:up';    Display = $(if ($ru) { "$prefix — правый стик ↑" } else { "$prefix — right stick ↑" }) },
        [pscustomobject]@{ Action = 'virtual:xbox:rsy:down';  Display = $(if ($ru) { "$prefix — правый стик ↓" } else { "$prefix — right stick ↓" }) },
        [pscustomobject]@{ Action = 'virtual:xbox:dpad:left';  Display = $(if ($ru) { "$prefix — крестовина ←" } else { "$prefix — D-pad ←" }) },
        [pscustomobject]@{ Action = 'virtual:xbox:dpad:right'; Display = $(if ($ru) { "$prefix — крестовина →" } else { "$prefix — D-pad →" }) },
        [pscustomobject]@{ Action = 'virtual:xbox:dpad:up';    Display = $(if ($ru) { "$prefix — крестовина ↑" } else { "$prefix — D-pad ↑" }) },
        [pscustomobject]@{ Action = 'virtual:xbox:dpad:down';  Display = $(if ($ru) { "$prefix — крестовина ↓" } else { "$prefix — D-pad ↓" }) }
    )
}

function Get-MugenVirtualGamepadHostPath {
    return (Join-Path $script:BaseDir 'virtual-gamepad\host\MugenDeej.VirtualGamepadHost.exe')
}

function Send-MugenVirtualGamepadCommand {
    param([Parameter(Mandatory = $true)][string]$Command)

    if (-not $script:VirtualGamepadActive -or $null -eq $script:VirtualGamepadWriter -or $null -eq $script:VirtualGamepadReader) {
        throw 'Virtual controller bridge is not active.'
    }

    $script:VirtualGamepadWriter.WriteLine($Command)
    $response = $script:VirtualGamepadReader.ReadLine()
    if ($null -eq $response) {
        throw 'Virtual controller host disconnected unexpectedly.'
    }
    if ($response -notin @('OK', 'PONG', 'BYE') -and -not $response.StartsWith('READY|')) {
        throw ('Virtual controller host error: ' + $response)
    }
    return $response
}

function Send-MugenVirtualGamepadStateCommand {
    param([Parameter(Mandatory = $true)][string]$Command)

    if (-not $script:VirtualGamepadActive -or $null -eq $script:VirtualGamepadWriter) {
        throw 'Virtual controller bridge is not active.'
    }

    # Gameplay state is a one-way hot path. Waiting for an acknowledgement made
    # the WinForms input loop serialize every press/release behind HID submission.
    # Lifecycle/control commands still use Send-MugenVirtualGamepadCommand.
    $script:VirtualGamepadWriter.WriteLine($Command)
}

function Stop-MugenVirtualGamepadStartTimer {
    if ($null -ne $script:VirtualGamepadStartTimer) {
        try { $script:VirtualGamepadStartTimer.Stop() } catch { }
    }
}

function Clear-MugenVirtualGamepadStartWait {
    if ($null -ne $script:VirtualGamepadStartWaitHandle) {
        try { $script:VirtualGamepadStartWaitHandle.AsyncWaitHandle.Close() } catch { }
    }
    $script:VirtualGamepadStartWaitHandle = $null
    $script:VirtualGamepadStartDeadline = [DateTime]::MinValue
}

function Stop-MugenVirtualGamepadProfileTimer {
    if ($null -ne $script:VirtualGamepadProfileTimer) {
        try { $script:VirtualGamepadProfileTimer.Stop() } catch { }
    }
}

function Reset-MugenVirtualGamepadBridgeObjects {
    Stop-MugenVirtualGamepadProfileTimer
    if ($null -ne $script:VirtualGamepadWriter) { try { $script:VirtualGamepadWriter.Dispose() } catch { } }
    if ($null -ne $script:VirtualGamepadReader) { try { $script:VirtualGamepadReader.Dispose() } catch { } }
    if ($null -ne $script:VirtualGamepadPipe) { try { $script:VirtualGamepadPipe.Dispose() } catch { } }

    $script:VirtualGamepadWriter = $null
    $script:VirtualGamepadReader = $null
    $script:VirtualGamepadPipe = $null
    $script:VirtualGamepadActive = $false
    $script:VirtualGamepadLastMask = [uint32]::MaxValue
    $script:VirtualGamepadLastOutputSignature = ''
    $script:VirtualGamepadLastButtonProfileKey = ''
    $script:VirtualGamepadCachedButtonProfileContext = $null
    $script:VirtualGamepadSuppressedPhysicalButtons = @{}
    $script:VirtualGamepadLastPhysicalButtons = @()
}

function Fail-MugenVirtualGamepadStart {
    param([Parameter(Mandatory = $true)][string]$Message)

    $script:VirtualGamepadLastStartFailure = Get-Date
    $script:VirtualGamepadStarting = $false
    Stop-MugenVirtualGamepadStartTimer
    Clear-MugenVirtualGamepadStartWait
    Write-Log ('Virtual controller start failed: {0}' -f $Message) 'WARN'
    Reset-MugenVirtualGamepadBridgeObjects
    Set-MugenVirtualGamepadUiState -State 'error'
}

function Complete-MugenVirtualGamepadStart {
    if (-not $script:VirtualGamepadStarting) {
        Stop-MugenVirtualGamepadStartTimer
        return
    }

    try {
        if ($null -ne $script:VirtualGamepadHelperProcess) {
            try {
                if ($script:VirtualGamepadHelperProcess.HasExited) {
                    throw 'Virtual controller helper exited before connecting.'
                }
            }
            catch [System.InvalidOperationException] { }
        }

        if (
            $script:VirtualGamepadStartDeadline -ne [DateTime]::MinValue -and
            (Get-Date) -ge $script:VirtualGamepadStartDeadline
        ) {
            throw 'Timed out waiting for the virtual controller helper. The UAC prompt may have been cancelled.'
        }

        if ($null -eq $script:VirtualGamepadStartWaitHandle -or -not $script:VirtualGamepadStartWaitHandle.IsCompleted) {
            return
        }

        $script:VirtualGamepadPipe.EndWaitForConnection($script:VirtualGamepadStartWaitHandle)
        Clear-MugenVirtualGamepadStartWait

        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $script:VirtualGamepadReader = New-Object System.IO.StreamReader($script:VirtualGamepadPipe, $utf8, $false, 4096, $true)
        $script:VirtualGamepadWriter = New-Object System.IO.StreamWriter($script:VirtualGamepadPipe, $utf8, 4096, $true)
        $script:VirtualGamepadWriter.AutoFlush = $true
        $script:VirtualGamepadWriter.NewLine = "`n"

        # The helper only connects after HID creation is complete, then writes
        # READY immediately. Keeping this final read synchronous avoids adding
        # another state machine while moving the expensive wait off the UI path.
        $ready = $script:VirtualGamepadReader.ReadLine()
        if ($null -eq $ready -or -not $ready.StartsWith('READY|')) {
            throw ('Virtual controller helper did not become ready. Response: ' + [string]$ready)
        }

        $script:VirtualGamepadActive = $true
        $script:VirtualGamepadStarting = $false
        $script:VirtualGamepadLastMask = [uint32]::MaxValue
        $script:VirtualGamepadLastStartFailure = [DateTime]::MinValue
        Stop-MugenVirtualGamepadStartTimer
        Ensure-MugenVirtualGamepadProfileTimer
        $script:VirtualGamepadProfileTimer.Start()
        Set-MugenVirtualGamepadUiState -State 'ready'
        Write-Log 'Virtual controller ready: Mugen Deej Virtual Gamepad (Xbox 360 / XInput).' 'INFO'
        [void](Get-MugenVirtualGamepadCachedButtonProfileContext -Refresh)

        # Push the freshest full button state immediately after the bridge comes
        # online. If no frame is available yet, the next serial frame will do it.
        if ($script:IsConnected -and @($script:LatestButtons).Count -gt 0) {
            Update-MugenVirtualGamepadButtonStates -Values @($script:LatestButtons)
        }
    }
    catch {
        Fail-MugenVirtualGamepadStart -Message $_.Exception.Message
    }
}

function Ensure-MugenVirtualGamepadStartTimer {
    if ($null -ne $script:VirtualGamepadStartTimer) { return }

    $script:VirtualGamepadStartTimer = New-Object System.Windows.Forms.Timer
    $script:VirtualGamepadStartTimer.Interval = 100
    $script:VirtualGamepadStartTimer.Add_Tick({
        Complete-MugenVirtualGamepadStart
    })
}

function Stop-MugenVirtualGamepad {
    param([string]$Reason = 'stop requested')

    $wasActive = $script:VirtualGamepadActive
    $wasStarting = $script:VirtualGamepadStarting

    if ($wasStarting) {
        $script:VirtualGamepadStarting = $false
        Stop-MugenVirtualGamepadStartTimer
        Clear-MugenVirtualGamepadStartWait
    }

    if ($wasActive) {
        try { [void](Send-MugenVirtualGamepadCommand -Command 'release') } catch { }
    }

    Reset-MugenVirtualGamepadBridgeObjects

    if ($null -ne $script:VirtualGamepadHelperProcess) {
        try {
            if (-not $script:VirtualGamepadHelperProcess.HasExited) {
                [void]$script:VirtualGamepadHelperProcess.WaitForExit(30000)
            }
            if (-not $script:VirtualGamepadHelperProcess.HasExited) {
                Write-Log ('Virtual controller helper did not exit within 30 seconds; leaving it to complete cleanup instead of force-killing it.') 'WARN'
            }
        }
        catch {
            Write-Log ('Virtual controller helper shutdown wait failed: {0}' -f $_.Exception.Message) 'WARN'
        }
    }

    $script:VirtualGamepadHelperProcess = $null

    if ($wasActive -or $wasStarting) {
        Write-Log ('Virtual controller stopped: {0}' -f $Reason) 'INFO'
    }
}

function Start-MugenVirtualGamepad {
    Initialize-MugenVirtualGamepadConfig

    if (-not [bool]$script:VirtualGamepadConfig.enabled) { return $false }
    if (-not (Test-MugenVirtualGamepadProtocolAvailable)) {
        Set-MugenVirtualGamepadUiState -State 'disabled'
        try { Update-MugenVirtualGamepadStatusUi } catch { }
        return $false
    }
    if ($script:VirtualGamepadActive) { return $true }
    if ($script:VirtualGamepadStarting) { return $false }
    if (-not $script:IsConnected -or $script:DetectedButtonCount -le 0) {
        Set-MugenVirtualGamepadUiState -State 'waiting'
        return $false
    }

    if (
        $script:VirtualGamepadLastStartFailure -ne [DateTime]::MinValue -and
        ((Get-Date) - $script:VirtualGamepadLastStartFailure).TotalSeconds -lt $script:VirtualGamepadStartFailureCooldownSeconds
    ) {
        return $false
    }

    $hostPath = Get-MugenVirtualGamepadHostPath
    if (-not (Test-Path -LiteralPath $hostPath -PathType Leaf)) {
        Write-Log ('Virtual controller host is missing: {0}' -f $hostPath) 'WARN'
        $script:VirtualGamepadLastStartFailure = Get-Date
        Set-MugenVirtualGamepadUiState -State 'error'
        return $false
    }

    $script:VirtualGamepadStarting = $true
    Set-MugenVirtualGamepadUiState -State 'starting'
    Reset-MugenVirtualGamepadBridgeObjects

    try {
        $pipeName = 'MugenDeejVirtualGamepad-' + [Guid]::NewGuid().ToString('N')
        $script:VirtualGamepadPipe = New-Object System.IO.Pipes.NamedPipeServerStream(
            $pipeName,
            [System.IO.Pipes.PipeDirection]::InOut,
            1,
            [System.IO.Pipes.PipeTransmissionMode]::Byte,
            [System.IO.Pipes.PipeOptions]::Asynchronous
        )

        $helperArgs = @(
            'server',
            '--pipe', $pipeName,
            '--profile', 'xbox-360-wired',
            '--identity', 'mugen-deej-main'
        )

        Write-Log 'Starting elevated virtual controller helper asynchronously.' 'INFO'
        $script:VirtualGamepadHelperProcess = Start-Process `
            -FilePath $hostPath `
            -ArgumentList $helperArgs `
            -Verb RunAs `
            -WindowStyle Hidden `
            -PassThru

        $script:VirtualGamepadStartWaitHandle = $script:VirtualGamepadPipe.BeginWaitForConnection($null, $null)
        $script:VirtualGamepadStartDeadline = (Get-Date).AddSeconds(75)

        Ensure-MugenVirtualGamepadStartTimer
        $script:VirtualGamepadStartTimer.Start()
        Write-Log 'Virtual controller startup is pending in the background; UI remains responsive.' 'DEBUG'
        return $false
    }
    catch {
        Fail-MugenVirtualGamepadStart -Message $_.Exception.Message
        return $false
    }
}

function Get-MugenVirtualGamepadButtonProfileContext {
    $fallbackActions = @($script:ButtonActions | ForEach-Object { [string]$_ })
    $fallback = [pscustomobject][ordered]@{
        Key = '__global__'
        Actions = @($fallbackActions)
    }

    try {
        if ($null -eq (Get-Command -Name Get-ProfiledButtonActionContext -CommandType Function -ErrorAction SilentlyContinue)) {
            return $fallback
        }

        $context = Get-ProfiledButtonActionContext
        if ($null -eq $context) { return $fallback }

        $key = [string]$context.Key
        if ([string]::IsNullOrWhiteSpace($key)) { $key = '__global__' }
        return [pscustomobject][ordered]@{
            Key = $key
            Actions = @($context.Actions | ForEach-Object { [string]$_ })
        }
    }
    catch {
        Write-Log ('Virtual controller profile lookup failed; using Global buttons: {0}' -f $_.Exception.Message) 'WARN'
        return $fallback
    }
}

function Get-MugenVirtualGamepadCachedButtonProfileContext {
    param([switch]$Refresh)

    if ($Refresh -or $null -eq $script:VirtualGamepadCachedButtonProfileContext) {
        $script:VirtualGamepadCachedButtonProfileContext = Get-MugenVirtualGamepadButtonProfileContext
    }

    return $script:VirtualGamepadCachedButtonProfileContext
}

function Get-MugenVirtualGamepadOutputState {
    param(
        [int[]]$Values,
        [object[]]$Actions
    )

    [uint32]$mask = 0
    $leftXNegative = $false
    $leftXPositive = $false
    $leftYNegative = $false
    $leftYPositive = $false
    $rightXNegative = $false
    $rightXPositive = $false
    $rightYNegative = $false
    $rightYPositive = $false
    $dpadXNegative = $false
    $dpadXPositive = $false
    $dpadYNegative = $false
    $dpadYPositive = $false
    $leftTriggerPressed = $false
    $rightTriggerPressed = $false

    $valuesArray = @($Values)
    $actionsArray = @($Actions)
    $count = [Math]::Min($valuesArray.Count, $actionsArray.Count)

    for ($i = 0; $i -lt $valuesArray.Count; $i++) {
        if ([int]$valuesArray[$i] -ne 0) {
            if ($script:VirtualGamepadSuppressedPhysicalButtons.ContainsKey($i)) {
                [void]$script:VirtualGamepadSuppressedPhysicalButtons.Remove($i)
            }
            continue
        }

        if ($script:VirtualGamepadSuppressedPhysicalButtons.ContainsKey($i)) { continue }
        if ($i -ge $count) { continue }

        $action = ([string]$actionsArray[$i]).ToLowerInvariant()
        if ($script:VirtualGamepadActionBits.ContainsKey($action)) {
            $mask = $mask -bor [uint32]$script:VirtualGamepadActionBits[$action]
            continue
        }

        switch ($action) {
            'virtual:xbox:lsx:left' { $leftXNegative = $true; break }
            'virtual:xbox:lsx:right' { $leftXPositive = $true; break }
            'virtual:xbox:lsy:up' { $leftYPositive = $true; break }
            'virtual:xbox:lsy:down' { $leftYNegative = $true; break }
            'virtual:xbox:rsx:left' { $rightXNegative = $true; break }
            'virtual:xbox:rsx:right' { $rightXPositive = $true; break }
            'virtual:xbox:rsy:up' { $rightYPositive = $true; break }
            'virtual:xbox:rsy:down' { $rightYNegative = $true; break }
            'virtual:xbox:dpad:left' { $dpadXNegative = $true; break }
            'virtual:xbox:dpad:right' { $dpadXPositive = $true; break }
            'virtual:xbox:dpad:up' { $dpadYPositive = $true; break }
            'virtual:xbox:dpad:down' { $dpadYNegative = $true; break }
            'virtual:xbox:lt' { $leftTriggerPressed = $true; break }
            'virtual:xbox:rt' { $rightTriggerPressed = $true; break }
        }
    }

    $lx = if ($leftXNegative -and -not $leftXPositive) { -1 } elseif ($leftXPositive -and -not $leftXNegative) { 1 } else { 0 }
    $ly = if ($leftYNegative -and -not $leftYPositive) { -1 } elseif ($leftYPositive -and -not $leftYNegative) { 1 } else { 0 }
    $rx = if ($rightXNegative -and -not $rightXPositive) { -1 } elseif ($rightXPositive -and -not $rightXNegative) { 1 } else { 0 }
    $ry = if ($rightYNegative -and -not $rightYPositive) { -1 } elseif ($rightYPositive -and -not $rightYNegative) { 1 } else { 0 }
    $dpadX = if ($dpadXNegative -and -not $dpadXPositive) { -1 } elseif ($dpadXPositive -and -not $dpadXNegative) { 1 } else { 0 }
    $dpadY = if ($dpadYNegative -and -not $dpadYPositive) { -1 } elseif ($dpadYPositive -and -not $dpadYNegative) { 1 } else { 0 }
    $lt = if ($leftTriggerPressed) { 1 } else { 0 }
    $rt = if ($rightTriggerPressed) { 1 } else { 0 }

    return [pscustomobject][ordered]@{
        Mask = [uint32]$mask
        LX = [int]$lx
        LY = [int]$ly
        RX = [int]$rx
        RY = [int]$ry
        DPadX = [int]$dpadX
        DPadY = [int]$dpadY
        LT = [int]$lt
        RT = [int]$rt
        Signature = ('{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}' -f [uint32]$mask, $lx, $ly, $rx, $ry, $dpadX, $dpadY, $lt, $rt)
    }
}


function Test-MugenVirtualGamepadPhysicalStateChanged {
    param([int[]]$Values)

    $current = @($Values)
    $previous = @($script:VirtualGamepadLastPhysicalButtons)
    if ($current.Count -ne $previous.Count) { return $true }

    for ($i = 0; $i -lt $current.Count; $i++) {
        if ([int]$current[$i] -ne [int]$previous[$i]) { return $true }
    }

    return $false
}

function Update-MugenVirtualGamepadButtonStates {
    param(
        [int[]]$Values,
        [switch]$ForceProfileCheck
    )

    Initialize-MugenVirtualGamepadConfig

    $protocolAvailable = Test-MugenVirtualGamepadProtocolAvailable
    if ($null -eq $script:VirtualGamepadLastProtocolAvailable -or [bool]$script:VirtualGamepadLastProtocolAvailable -ne $protocolAvailable) {
        try { Update-MugenVirtualGamepadStatusUi } catch { }
    }

    if (-not $protocolAvailable) {
        if ($script:VirtualGamepadActive -or $script:VirtualGamepadStarting) {
            Stop-MugenVirtualGamepad -Reason ('virtual controller unavailable for protocol: ' + [string]$script:ControllerProtocol)
        }
        Set-MugenVirtualGamepadUiState -State 'disabled'
        return
    }

    if (-not [bool]$script:VirtualGamepadConfig.enabled) {
        if ($script:VirtualGamepadActive -or $script:VirtualGamepadStarting) {
            Stop-MugenVirtualGamepad -Reason 'virtual controller disabled'
        }
        Set-MugenVirtualGamepadUiState -State 'disabled'
        return
    }

    $valuesArray = @($Values)
    if (-not $script:IsConnected -or $script:DetectedButtonCount -le 0 -or $valuesArray.Count -eq 0) {
        if ($script:VirtualGamepadActive -or $script:VirtualGamepadStarting) {
            Stop-MugenVirtualGamepad -Reason 'physical controller unavailable'
        }
        Set-MugenVirtualGamepadUiState -State 'waiting'
        return
    }

    $inputSuspended = $false
    try {
        if ($null -ne (Get-Command -Name Test-MugenInputActionsSuspended -CommandType Function -ErrorAction SilentlyContinue)) {
            $inputSuspended = [bool](Test-MugenInputActionsSuspended)
        }
    }
    catch {}

    if ($inputSuspended) {
        $heldWhileModal = @{}
        for ($i = 0; $i -lt $valuesArray.Count; $i++) {
            if ([int]$valuesArray[$i] -eq 0) {
                $heldWhileModal[$i] = $true
            }
        }
        $script:VirtualGamepadSuppressedPhysicalButtons = $heldWhileModal
        $script:VirtualGamepadLastPhysicalButtons = @($valuesArray)

        if (-not $script:VirtualGamepadInputSuspended) {
            $script:VirtualGamepadInputSuspended = $true
            if ($script:VirtualGamepadActive) {
                try {
                    Send-MugenVirtualGamepadStateCommand -Command 'state 0 0 0 0 0 0 0 0 0'
                    $script:VirtualGamepadLastMask = [uint32]0
                    $script:VirtualGamepadLastOutputSignature = '0|0|0|0|0|0|0|0|0'
                }
                catch {
                    Write-Log ('Virtual controller modal-safety neutralization failed: {0}' -f $_.Exception.Message) 'WARN'
                }
            }
            Write-Log ('Virtual controller input suspended while a modal Mugen dialog is open; held inputs={0}' -f $heldWhileModal.Count) 'DEBUG'
        }
        return
    }

    $resumingModalInput = $false
    if ($script:VirtualGamepadInputSuspended) {
        $script:VirtualGamepadInputSuspended = $false
        $resumingModalInput = $true
        Write-Log 'Virtual controller input resumed after modal Mugen dialog closed; held inputs remain suppressed until release.' 'DEBUG'
    }

    if (-not (Start-MugenVirtualGamepad)) { return }

    # Unchanged 25 ms button heartbeats must not resolve the foreground process
    # and rebuild profile state on the UI thread. A separate 200 ms profile
    # timer retains safe focus/profile boundary behavior.
    $physicalChanged = ($resumingModalInput -or (Test-MugenVirtualGamepadPhysicalStateChanged -Values $valuesArray))
    if (-not $physicalChanged -and -not $ForceProfileCheck) {
        return
    }

    # Foreground-process/profile discovery is deliberately kept off the physical
    # button hot path. The 200 ms profile timer refreshes this snapshot; a button
    # transition only resolves its already-cached mappings.
    $context = Get-MugenVirtualGamepadCachedButtonProfileContext -Refresh:$ForceProfileCheck
    $profileKey = [string]$context.Key
    $previousProfileKey = [string]$script:VirtualGamepadLastButtonProfileKey
    $previousValues = @($script:VirtualGamepadLastPhysicalButtons)

    if ([string]::IsNullOrWhiteSpace($previousProfileKey)) {
        $script:VirtualGamepadLastButtonProfileKey = $profileKey
    }
    elseif ($previousProfileKey -ne $profileKey) {
        try {
            # Profile identity, not the focus-change mechanism, is the boundary.
            Send-MugenVirtualGamepadStateCommand -Command 'state 0 0 0 0 0 0 0 0 0'

            $script:VirtualGamepadLastMask = [uint32]0
            $script:VirtualGamepadLastOutputSignature = '0|0|0|0|0|0|0|0|0'
            $script:VirtualGamepadSuppressedPhysicalButtons = @{}

            for ($i = 0; $i -lt $valuesArray.Count; $i++) {
                $wasHeld = ($previousValues.Count -gt $i -and [int]$previousValues[$i] -eq 0)
                $isHeld = ([int]$valuesArray[$i] -eq 0)
                if ($wasHeld -and $isHeld) {
                    $script:VirtualGamepadSuppressedPhysicalButtons[$i] = $true
                }
            }

            $script:VirtualGamepadLastButtonProfileKey = $profileKey
            Write-Log ('Virtual gamepad output profile changed: {0} -> {1}; state neutralized; held inputs suppressed until release={2}' -f $previousProfileKey, $profileKey, $script:VirtualGamepadSuppressedPhysicalButtons.Count) 'INFO'
        }
        catch {
            Write-Log ('Virtual controller profile-switch release failed: {0}' -f $_.Exception.Message) 'WARN'
            Stop-MugenVirtualGamepad -Reason 'profile-switch release failed'
            return
        }
    }

    $output = Get-MugenVirtualGamepadOutputState -Values $valuesArray -Actions @($context.Actions)
    $script:VirtualGamepadLastPhysicalButtons = @($valuesArray)
    if ([string]$output.Signature -eq [string]$script:VirtualGamepadLastOutputSignature) { return }

    try {
        $command = 'state {0} {1} {2} {3} {4} {5} {6} {7} {8}' -f [uint32]$output.Mask, [int]$output.LX, [int]$output.LY, [int]$output.RX, [int]$output.RY, [int]$output.DPadX, [int]$output.DPadY, [int]$output.LT, [int]$output.RT
        Send-MugenVirtualGamepadStateCommand -Command $command
        $script:VirtualGamepadLastMask = [uint32]$output.Mask
        $script:VirtualGamepadLastOutputSignature = [string]$output.Signature
    }
    catch {
        Write-Log ('Virtual controller state update failed: {0}' -f $_.Exception.Message) 'WARN'
        Stop-MugenVirtualGamepad -Reason 'bridge state update failed'
    }
}

function Ensure-MugenVirtualGamepadProfileTimer {
    if ($null -ne $script:VirtualGamepadProfileTimer) { return }

    # Foreground-profile checks are only useful while a virtual controller is
    # actually live. Keeping this WinForms timer stopped while XInput is off
    # removes another permanent UI-thread wake-up from ordinary Mugen use.
    $script:VirtualGamepadProfileTimer = New-Object System.Windows.Forms.Timer
    $script:VirtualGamepadProfileTimer.Interval = 200
    $script:VirtualGamepadProfileTimer.Add_Tick({
        try {
            if (
                $script:VirtualGamepadActive -and
                (Test-MugenVirtualGamepadProtocolAvailable) -and
                $script:IsConnected -and
                $script:DetectedButtonCount -gt 0 -and
                @($script:LatestButtons).Count -gt 0
            ) {
                Update-MugenVirtualGamepadButtonStates -Values @($script:LatestButtons) -ForceProfileCheck
            }
        }
        catch { }
    })
}

function Sync-MugenVirtualGamepadState {
    param([int[]]$Values = @())

    Initialize-MugenVirtualGamepadConfig

    $protocolAvailable = Test-MugenVirtualGamepadProtocolAvailable
    if ($null -eq $script:VirtualGamepadLastProtocolAvailable -or [bool]$script:VirtualGamepadLastProtocolAvailable -ne $protocolAvailable) {
        try { Update-MugenVirtualGamepadStatusUi } catch { }
    }

    if (-not $protocolAvailable) {
        Stop-MugenVirtualGamepad -Reason ('virtual controller unavailable for protocol: ' + [string]$script:ControllerProtocol)
        Set-MugenVirtualGamepadUiState -State 'disabled'
        return $false
    }

    if (-not [bool]$script:VirtualGamepadConfig.enabled) {
        Stop-MugenVirtualGamepad -Reason 'virtual controller disabled in settings'
        Set-MugenVirtualGamepadUiState -State 'disabled'
        return $true
    }

    if (-not $script:IsConnected -or $script:DetectedButtonCount -le 0) {
        Set-MugenVirtualGamepadUiState -State 'waiting'
        return $false
    }

    if ($script:VirtualGamepadActive) {
        Update-MugenVirtualGamepadButtonStates -Values @($Values)
        return $true
    }

    [void](Start-MugenVirtualGamepad)
    return $script:VirtualGamepadActive
}

Ensure-MugenVirtualGamepadUiTimer
Ensure-MugenVirtualGamepadProfileTimer
