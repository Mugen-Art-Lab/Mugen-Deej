# Development-stage overlay: keep HIDMaestro teardown off the WinForms UI path.
#
# HIDMaestro currently needs roughly ten seconds on the tested machine to
# dispose/remove the Xbox virtual device. That cleanup is real work, but Mugen
# must not synchronously WaitForExit() on the UI thread while it happens.

$script:VirtualGamepadStopping = $false
$script:VirtualGamepadStopProcess = $null
$script:VirtualGamepadStopReason = ''
$script:VirtualGamepadStopTimer = $null

# Preserve the proven nonblocking start implementation, then wrap it so a new
# virtual controller cannot be created while the previous helper is still
# removing its HID/PnP state.
$script:MugenVirtualGamepadStartCore = ${function:Start-MugenVirtualGamepad}

function Complete-MugenVirtualGamepadStop {
    if (-not $script:VirtualGamepadStopping) {
        if ($null -ne $script:VirtualGamepadStopTimer) {
            try { $script:VirtualGamepadStopTimer.Stop() } catch { }
        }
        return
    }

    $finished = $false
    if ($null -eq $script:VirtualGamepadStopProcess) {
        $finished = $true
    }
    else {
        try { $finished = [bool]$script:VirtualGamepadStopProcess.HasExited }
        catch { $finished = $true }
    }

    if (-not $finished) { return }

    if ($null -ne $script:VirtualGamepadStopTimer) {
        try { $script:VirtualGamepadStopTimer.Stop() } catch { }
    }

    $reason = $script:VirtualGamepadStopReason
    $script:VirtualGamepadStopping = $false
    $script:VirtualGamepadStopProcess = $null
    $script:VirtualGamepadStopReason = ''

    Write-Log ('Virtual controller background cleanup finished: {0}' -f $reason) 'INFO'

    # If the user re-enabled the feature while the old HID was still being
    # removed, start a fresh controller only after the old helper has exited.
    if (
        $script:VirtualGamepadConfigLoaded -and
        $null -ne $script:VirtualGamepadConfig -and
        [bool]$script:VirtualGamepadConfig.enabled -and
        $script:IsConnected -and
        $script:DetectedButtonCount -gt 0
    ) {
        Set-MugenVirtualGamepadUiState -State 'waiting'
        [void](Start-MugenVirtualGamepad)
    }
}

function Ensure-MugenVirtualGamepadStopTimer {
    if ($null -ne $script:VirtualGamepadStopTimer) { return }

    $script:VirtualGamepadStopTimer = New-Object System.Windows.Forms.Timer
    $script:VirtualGamepadStopTimer.Interval = 150
    $script:VirtualGamepadStopTimer.Add_Tick({
        try { Complete-MugenVirtualGamepadStop }
        catch { Write-Log ('Virtual controller background cleanup polling failed: {0}' -f $_.Exception.Message) 'WARN' }
    })
}

function Stop-MugenVirtualGamepad {
    param([string]$Reason = 'stop requested')

    # Repeated full-state packets can arrive while cleanup is in progress. The
    # first stop request already disconnected the bridge, so later requests are
    # no-ops instead of restarting or waiting on the helper.
    if (
        $script:VirtualGamepadStopping -and
        -not $script:VirtualGamepadActive -and
        -not $script:VirtualGamepadStarting
    ) {
        return
    }

    $wasActive = $script:VirtualGamepadActive
    $wasStarting = $script:VirtualGamepadStarting
    $helperToReap = $script:VirtualGamepadHelperProcess

    if ($wasStarting) {
        $script:VirtualGamepadStarting = $false
        Stop-MugenVirtualGamepadStartTimer
        Clear-MugenVirtualGamepadStartWait
    }

    if ($wasActive) {
        try { [void](Send-MugenVirtualGamepadCommand -Command 'release') } catch { }
    }

    # Closing our side of the pipe is the proven signal that makes the elevated
    # helper release the controller and run HIDMaestro cleanup.
    Reset-MugenVirtualGamepadBridgeObjects
    $script:VirtualGamepadHelperProcess = $null

    $helperStillRunning = $false
    if ($null -ne $helperToReap) {
        try { $helperStillRunning = -not [bool]$helperToReap.HasExited }
        catch { $helperStillRunning = $false }
    }

    if ($helperStillRunning) {
        $script:VirtualGamepadStopping = $true
        $script:VirtualGamepadStopProcess = $helperToReap
        $script:VirtualGamepadStopReason = $Reason
        Ensure-MugenVirtualGamepadStopTimer
        $script:VirtualGamepadStopTimer.Start()
        Write-Log ('Virtual controller teardown is pending in the background; UI remains responsive: {0}' -f $Reason) 'DEBUG'
    }
    else {
        $script:VirtualGamepadStopping = $false
        $script:VirtualGamepadStopProcess = $null
        $script:VirtualGamepadStopReason = ''
        if ($wasActive -or $wasStarting) {
            Write-Log ('Virtual controller stopped immediately: {0}' -f $Reason) 'INFO'
        }
    }

    if (
        $script:VirtualGamepadConfigLoaded -and
        $null -ne $script:VirtualGamepadConfig -and
        [bool]$script:VirtualGamepadConfig.enabled
    ) {
        Set-MugenVirtualGamepadUiState -State 'waiting'
    }
    else {
        Set-MugenVirtualGamepadUiState -State 'disabled'
    }
}

function Start-MugenVirtualGamepad {
    if ($script:VirtualGamepadStopping) {
        if (
            $script:VirtualGamepadConfigLoaded -and
            $null -ne $script:VirtualGamepadConfig -and
            [bool]$script:VirtualGamepadConfig.enabled
        ) {
            Set-MugenVirtualGamepadUiState -State 'waiting'
        }
        return $false
    }

    return (& $script:MugenVirtualGamepadStartCore)
}
