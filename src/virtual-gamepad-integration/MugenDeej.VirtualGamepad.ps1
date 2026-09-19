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
$script:VirtualGamepadStatusDot = $null
$script:VirtualGamepadStatusLabel = $null
$script:VirtualGamepadLastMask = [uint32]::MaxValue
$script:VirtualGamepadLastButtonProfileKey = ''
$script:VirtualGamepadSuppressedPhysicalButtons = @{}
$script:VirtualGamepadLastPhysicalButtons = @()
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
        $script:VirtualGamepadStatusDot.Font = New-Object System.Drawing.Font('Segoe UI', 11)
        $script:VirtualGamepadStatusDot.AutoSize = $true
        $script:VirtualGamepadStatusDot.Location = [System.Drawing.Point]::new(16, 31)
        $script:VirtualGamepadStatusDot.Visible = $false
        $panel.Controls.Add($script:VirtualGamepadStatusDot)
    }

    if ($null -eq $script:VirtualGamepadStatusLabel -or $script:VirtualGamepadStatusLabel.IsDisposed) {
        $script:VirtualGamepadStatusLabel = New-Object System.Windows.Forms.Label
        $script:VirtualGamepadStatusLabel.AutoSize = $false
        $script:VirtualGamepadStatusLabel.Size = [System.Drawing.Size]::new(560, 25)
        $script:VirtualGamepadStatusLabel.Location = [System.Drawing.Point]::new(46, 30)
        $script:VirtualGamepadStatusLabel.TextAlign = 'MiddleLeft'
        $script:VirtualGamepadStatusLabel.ForeColor = $physicalLabel.ForeColor
        $script:VirtualGamepadStatusLabel.Visible = $false
        $panel.Controls.Add($script:VirtualGamepadStatusLabel)
    }

    return $true
}

function Update-MugenVirtualGamepadStatusUi {
    if (-not (Ensure-MugenVirtualGamepadStatusUi)) { return }

    $physicalLabel = (Get-Variable -Name statusLabel -Scope Script).Value
    $physicalDot = (Get-Variable -Name statusDot -Scope Script).Value

    $enabled = (
        $script:VirtualGamepadConfigLoaded -and
        $null -ne $script:VirtualGamepadConfig -and
        [bool]$script:VirtualGamepadConfig.enabled
    )

    if (-not $enabled) {
        $script:VirtualGamepadStatusDot.Visible = $false
        $script:VirtualGamepadStatusLabel.Visible = $false
        $physicalDot.Location = [System.Drawing.Point]::new(14, 12)
        $physicalLabel.Location = [System.Drawing.Point]::new(46, 10)
        $physicalLabel.Size = [System.Drawing.Size]::new(560, 38)
        return
    }

    $physicalDot.Location = [System.Drawing.Point]::new(14, 0)
    $physicalLabel.Location = [System.Drawing.Point]::new(46, 0)
    $physicalLabel.Size = [System.Drawing.Size]::new(560, 29)

    $script:VirtualGamepadStatusDot.Visible = $true
    $script:VirtualGamepadStatusLabel.Visible = $true
    $script:VirtualGamepadStatusLabel.ForeColor = $physicalLabel.ForeColor

    $ru = ($script:Language -eq 'ru')
    $text = if ($ru) { 'Виртуальный геймпад: ожидает контроллер' } else { 'Virtual gamepad: waiting for controller' }
    $color = [System.Drawing.Color]::Gray

    switch ($script:VirtualGamepadUiState) {
        'starting' {
            $text = if ($ru) { 'Виртуальный геймпад: подключается…' } else { 'Virtual gamepad: connecting…' }
            $color = [System.Drawing.Color]::RoyalBlue
        }
        'ready' {
            $text = if ($ru) { 'Mugen Deej Virtual Gamepad: подключён' } else { 'Mugen Deej Virtual Gamepad: connected' }
            $color = [System.Drawing.Color]::SeaGreen
        }
        'error' {
            $text = if ($ru) { 'Виртуальный геймпад: ошибка запуска' } else { 'Virtual gamepad: startup failed' }
            $color = [System.Drawing.Color]::Firebrick
        }
        default {
            $text = if ($ru) { 'Виртуальный геймпад: ожидает контроллер' } else { 'Virtual gamepad: waiting for controller' }
            $color = [System.Drawing.Color]::Gray
        }
    }

    if ($script:VirtualGamepadStatusLabel.Text -ne $text) {
        $script:VirtualGamepadStatusLabel.Text = $text
    }
    $script:VirtualGamepadStatusDot.ForeColor = $color
}

function Set-MugenVirtualGamepadUiState {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('disabled','waiting','starting','ready','error')]
        [string]$State
    )

    $script:VirtualGamepadUiState = $State
    try { Update-MugenVirtualGamepadStatusUi } catch { }
}

function Ensure-MugenVirtualGamepadUiTimer {
    if ($null -ne $script:VirtualGamepadUiTimer) { return }

    $script:VirtualGamepadUiTimer = New-Object System.Windows.Forms.Timer
    $script:VirtualGamepadUiTimer.Interval = 500
    $script:VirtualGamepadUiTimer.Add_Tick({
        try {
            Initialize-MugenVirtualGamepadConfig
            Update-MugenVirtualGamepadStatusUi
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

    if (-not $Enabled) {
        Set-MugenVirtualGamepadUiState -State 'disabled'
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
    return $script:VirtualGamepadActionBits.ContainsKey($Action.ToLowerInvariant())
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
        [pscustomobject]@{ Action = 'virtual:xbox:back';  Display = $(if ($ru) { "$prefix — Назад / View" } else { "$prefix — Back / View" }) },
        [pscustomobject]@{ Action = 'virtual:xbox:start'; Display = $(if ($ru) { "$prefix — Старт / Menu" } else { "$prefix — Start / Menu" }) },
        [pscustomobject]@{ Action = 'virtual:xbox:l3';    Display = "$prefix — L3" },
        [pscustomobject]@{ Action = 'virtual:xbox:r3';    Display = "$prefix — R3" }
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

function Reset-MugenVirtualGamepadBridgeObjects {
    if ($null -ne $script:VirtualGamepadWriter) { try { $script:VirtualGamepadWriter.Dispose() } catch { } }
    if ($null -ne $script:VirtualGamepadReader) { try { $script:VirtualGamepadReader.Dispose() } catch { } }
    if ($null -ne $script:VirtualGamepadPipe) { try { $script:VirtualGamepadPipe.Dispose() } catch { } }

    $script:VirtualGamepadWriter = $null
    $script:VirtualGamepadReader = $null
    $script:VirtualGamepadPipe = $null
    $script:VirtualGamepadActive = $false
    $script:VirtualGamepadLastMask = [uint32]::MaxValue
    $script:VirtualGamepadLastButtonProfileKey = ''
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
        Set-MugenVirtualGamepadUiState -State 'ready'
        Write-Log 'Virtual controller ready: Mugen Deej Virtual Gamepad (Xbox 360 / XInput).' 'INFO'

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

function Get-MugenVirtualGamepadMask {
    param(
        [int[]]$Values,
        [object[]]$Actions
    )

    [uint32]$mask = 0
    $valuesArray = @($Values)
    $actionsArray = @($Actions)
    $count = [Math]::Min($valuesArray.Count, $actionsArray.Count)

    for ($i = 0; $i -lt $valuesArray.Count; $i++) {
        if ([int]$valuesArray[$i] -ne 0) {
            if ($script:VirtualGamepadSuppressedPhysicalButtons.ContainsKey($i)) {
                $script:VirtualGamepadSuppressedPhysicalButtons.Remove($i)
            }
            continue
        }

        if ($script:VirtualGamepadSuppressedPhysicalButtons.ContainsKey($i)) { continue }
        if ($i -ge $count) { continue }

        $action = ([string]$actionsArray[$i]).ToLowerInvariant()
        if ($script:VirtualGamepadActionBits.ContainsKey($action)) {
            $mask = $mask -bor [uint32]$script:VirtualGamepadActionBits[$action]
        }
    }

    return $mask
}

function Update-MugenVirtualGamepadButtonStates {
    param([int[]]$Values)

    Initialize-MugenVirtualGamepadConfig

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

    if (-not (Start-MugenVirtualGamepad)) { return }

    $context = Get-MugenVirtualGamepadButtonProfileContext
    $profileKey = [string]$context.Key
    $previousProfileKey = [string]$script:VirtualGamepadLastButtonProfileKey
    $previousValues = @($script:VirtualGamepadLastPhysicalButtons)

    if ([string]::IsNullOrWhiteSpace($previousProfileKey)) {
        $script:VirtualGamepadLastButtonProfileKey = $profileKey
    }
    elseif ($previousProfileKey -ne $profileKey) {
        try {
            if (
                $script:VirtualGamepadLastMask -ne [uint32]::MaxValue -and
                $script:VirtualGamepadLastMask -ne [uint32]0
            ) {
                [void](Send-MugenVirtualGamepadCommand -Command 'buttons 0')
            }

            $script:VirtualGamepadLastMask = [uint32]0
            $script:VirtualGamepadSuppressedPhysicalButtons = @{}

            # A button that was already physically held before the foreground
            # profile changed must not become a fresh press in the new profile.
            # It stays suppressed until its real release edge arrives.
            for ($i = 0; $i -lt $valuesArray.Count; $i++) {
                $wasHeld = ($previousValues.Count -gt $i -and [int]$previousValues[$i] -eq 0)
                $isHeld = ([int]$valuesArray[$i] -eq 0)
                if ($wasHeld -and $isHeld) {
                    $script:VirtualGamepadSuppressedPhysicalButtons[$i] = $true
                }
            }

            $script:VirtualGamepadLastButtonProfileKey = $profileKey
            Write-Log ('Virtual gamepad button profile changed: {0} -> {1}; held inputs suppressed until release={2}' -f $previousProfileKey, $profileKey, $script:VirtualGamepadSuppressedPhysicalButtons.Count) 'INFO'
        }
        catch {
            Write-Log ('Virtual controller profile-switch release failed: {0}' -f $_.Exception.Message) 'WARN'
            Stop-MugenVirtualGamepad -Reason 'profile-switch release failed'
            return
        }
    }

    [uint32]$mask = Get-MugenVirtualGamepadMask -Values $valuesArray -Actions @($context.Actions)
    $script:VirtualGamepadLastPhysicalButtons = @($valuesArray)
    if ($mask -eq $script:VirtualGamepadLastMask) { return }

    try {
        [void](Send-MugenVirtualGamepadCommand -Command ('buttons ' + [string]$mask))
        $script:VirtualGamepadLastMask = $mask
    }
    catch {
        Write-Log ('Virtual controller state update failed: {0}' -f $_.Exception.Message) 'WARN'
        Stop-MugenVirtualGamepad -Reason 'bridge state update failed'
    }
}

function Sync-MugenVirtualGamepadState {
    param([int[]]$Values = @())

    Initialize-MugenVirtualGamepadConfig

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
