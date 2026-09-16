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
$script:VirtualGamepadLastMask = [uint32]::MaxValue
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
    }
    catch {
        Write-Log ('Virtual controller config could not be read; using defaults: {0}' -f $_.Exception.Message) 'WARN'
        $script:VirtualGamepadConfig = New-MugenVirtualGamepadConfig
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

function Reset-MugenVirtualGamepadBridgeObjects {
    if ($null -ne $script:VirtualGamepadWriter) { try { $script:VirtualGamepadWriter.Dispose() } catch { } }
    if ($null -ne $script:VirtualGamepadReader) { try { $script:VirtualGamepadReader.Dispose() } catch { } }
    if ($null -ne $script:VirtualGamepadPipe) { try { $script:VirtualGamepadPipe.Dispose() } catch { } }

    $script:VirtualGamepadWriter = $null
    $script:VirtualGamepadReader = $null
    $script:VirtualGamepadPipe = $null
    $script:VirtualGamepadActive = $false
    $script:VirtualGamepadLastMask = [uint32]::MaxValue
}

function Stop-MugenVirtualGamepad {
    param([string]$Reason = 'stop requested')

    $wasActive = $script:VirtualGamepadActive

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

    if ($wasActive) {
        Write-Log ('Virtual controller stopped: {0}' -f $Reason) 'INFO'
    }
}

function Start-MugenVirtualGamepad {
    Initialize-MugenVirtualGamepadConfig

    if (-not [bool]$script:VirtualGamepadConfig.enabled) { return $false }
    if ($script:VirtualGamepadActive) { return $true }
    if ($script:VirtualGamepadStarting) { return $false }
    if (-not $script:IsConnected -or $script:DetectedButtonCount -le 0) { return $false }

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
        return $false
    }

    $script:VirtualGamepadStarting = $true
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

        Write-Log 'Starting elevated virtual controller helper.' 'INFO'
        $script:VirtualGamepadHelperProcess = Start-Process `
            -FilePath $hostPath `
            -ArgumentList $helperArgs `
            -Verb RunAs `
            -WindowStyle Hidden `
            -PassThru

        $waitHandle = $script:VirtualGamepadPipe.BeginWaitForConnection($null, $null)
        try {
            $deadline = (Get-Date).AddSeconds(75)
            while (-not $waitHandle.IsCompleted) {
                try {
                    if ($script:VirtualGamepadHelperProcess.HasExited) {
                        throw 'Virtual controller helper exited before connecting.'
                    }
                }
                catch [System.InvalidOperationException] { }

                if ((Get-Date) -ge $deadline) {
                    throw 'Timed out waiting for the virtual controller helper. The UAC prompt may have been cancelled.'
                }

                try { [System.Windows.Forms.Application]::DoEvents() } catch { }
                Start-Sleep -Milliseconds 80
            }

            $script:VirtualGamepadPipe.EndWaitForConnection($waitHandle)
        }
        finally {
            try { $waitHandle.AsyncWaitHandle.Close() } catch { }
        }

        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $script:VirtualGamepadReader = New-Object System.IO.StreamReader($script:VirtualGamepadPipe, $utf8, $false, 4096, $true)
        $script:VirtualGamepadWriter = New-Object System.IO.StreamWriter($script:VirtualGamepadPipe, $utf8, 4096, $true)
        $script:VirtualGamepadWriter.AutoFlush = $true
        $script:VirtualGamepadWriter.NewLine = "`n"

        $ready = $script:VirtualGamepadReader.ReadLine()
        if ($null -eq $ready -or -not $ready.StartsWith('READY|')) {
            throw ('Virtual controller helper did not become ready. Response: ' + [string]$ready)
        }

        $script:VirtualGamepadActive = $true
        $script:VirtualGamepadLastMask = [uint32]::MaxValue
        $script:VirtualGamepadLastStartFailure = [DateTime]::MinValue
        Write-Log 'Virtual controller ready: Mugen Deej Virtual Gamepad (Xbox 360 / XInput).' 'INFO'
        return $true
    }
    catch {
        $script:VirtualGamepadLastStartFailure = Get-Date
        Write-Log ('Virtual controller start failed: {0}' -f $_.Exception.Message) 'WARN'
        Reset-MugenVirtualGamepadBridgeObjects
        return $false
    }
    finally {
        $script:VirtualGamepadStarting = $false
    }
}

function Get-MugenVirtualGamepadMask {
    param([int[]]$Values)

    [uint32]$mask = 0
    $valuesArray = @($Values)
    $actionsArray = @($script:ButtonActions)
    $count = [Math]::Min($valuesArray.Count, $actionsArray.Count)

    for ($i = 0; $i -lt $count; $i++) {
        if ([int]$valuesArray[$i] -ne 0) { continue }

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
        if ($script:VirtualGamepadActive) {
            Stop-MugenVirtualGamepad -Reason 'virtual controller disabled'
        }
        return
    }

    if (-not $script:IsConnected -or $script:DetectedButtonCount -le 0 -or @($Values).Count -eq 0) {
        if ($script:VirtualGamepadActive) {
            Stop-MugenVirtualGamepad -Reason 'physical controller unavailable'
        }
        return
    }

    if (-not (Start-MugenVirtualGamepad)) { return }

    [uint32]$mask = Get-MugenVirtualGamepadMask -Values @($Values)
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
        return $true
    }

    if (-not $script:IsConnected -or $script:DetectedButtonCount -le 0) {
        return $false
    }

    if (-not (Start-MugenVirtualGamepad)) { return $false }

    Update-MugenVirtualGamepadButtonStates -Values @($Values)
    return $script:VirtualGamepadActive
}
