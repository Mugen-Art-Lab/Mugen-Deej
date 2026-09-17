param(
    [Parameter(Mandatory = $true)][string]$Path
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
        throw "Dev runtime hardening '$Label' expected exactly one match, found $($matches.Count)."
    }

    return $regex.Replace($Text, $Replacement, 1)
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
        throw "Dev runtime hardening '$Label' expected exactly one literal match."
    }

    return $Text.Substring(0, $first) + $NewText + $Text.Substring($first + $OldText.Length)
}

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
    $regex = New-Object System.Text.RegularExpressions.Regex(
        $Pattern,
        $options
    )
    $matches = $regex.Matches($Text)
    if ($matches.Count -ne 1) {
        throw "Dev runtime hardening '$Label' expected exactly one regex block match, found $($matches.Count)."
    }

    $match = $matches[0]
    return $Text.Substring(0, $match.Index) + $Replacement + $Text.Substring($match.Index + $match.Length)
}

$resolved = (Resolve-Path -LiteralPath $Path).Path
$text = [System.IO.File]::ReadAllText($resolved, [System.Text.Encoding]::UTF8)

# A portable stable Mugen installation may already own the HKCU Run value.
# The experimental build lives in a throwaway folder and must never move that
# registration to itself merely because it was launched for hardware testing.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern '(?m)^Sync-StartupRegistrationPath\r?$' `
    -Replacement "Write-Log 'Development build: Windows startup registration sync suppressed.' 'INFO'" `
    -Label 'suppress startup path sync'

# Also prevent the development UI from changing the stable application's
# autostart registration. Start-minimized remains available; only the Run-key
# checkbox is disabled for this isolated package.
$text = Replace-RegexExactlyOnce `
    -Text $text `
    -Pattern '(?m)^\$startWithWindowsCheck\.Checked = \(Test-StartupEnabled\)\r?\n\$startWithWindowsCheck\.Enabled = \(Test-Path -LiteralPath \$script:ExecutablePath\)' `
    -Replacement @'
$startWithWindowsCheck.Checked = $false
$startWithWindowsCheck.Enabled = $false
'@ `
    -Label 'disable startup checkbox'

# The stable 1.0.0 action normalizer does not know the experimental virtual
# action namespace. Preserve validated virtual mappings instead of silently
# rewriting them to "none" when controller capabilities are re-detected.
# Use literal string replacement here: .NET Regex.Replace interprets '$name'
# sequences in replacement text as group references, which corrupts source
# containing PowerShell variables such as $action and $script:... .
$oldNormalizeBlock = @'
        $valid = (
            $action -eq 'none' -or
            $action -match '^mute:\d+$' -or
            $validFixedActions -contains $action
        )
'@

$newNormalizeBlock = @'
        $valid = (
            $action -eq 'none' -or
            $action -match '^mute:\d+$' -or
            $validFixedActions -contains $action -or
            (
                $script:VirtualGamepadFeatureAvailable -and
                (Test-MugenVirtualGamepadAction -Action $action)
            )
        )
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldNormalizeBlock `
    -NewText $newNormalizeBlock `
    -Label 'preserve virtual button mappings'

# ---------------------------------------------------------------------------
# Experimental serial auto-baud staging
# ---------------------------------------------------------------------------
# Keep stable/main untouched while the large-panel prototype is unproven.
# Existing 9600-baud controllers remain the first choice on a clean config.
# Once a controller is detected at 115200, that rate is remembered and tried
# first on the next connection. A fixed mode remains available through config.

$oldDefaultBaudBlock = @'
            baudRate = 9600
            expectedSliders = 5
'@
$newDefaultBaudBlock = @'
            baudRate = 9600
            baudRateMode = 'auto'
            lastWorkingBaudRate = 0
            expectedSliders = 5
'@
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldDefaultBaudBlock `
    -NewText $newDefaultBaudBlock `
    -Label 'add default auto-baud config'

$oldMigrationBaudBlock = @'
    Add-MissingConfigProperty -Object $Config.connection -Name 'baudRate' -Value 9600
    Add-MissingConfigProperty -Object $Config.connection -Name 'expectedSliders' -Value 5
'@
$newMigrationBaudBlock = @'
    Add-MissingConfigProperty -Object $Config.connection -Name 'baudRate' -Value 9600
    Add-MissingConfigProperty -Object $Config.connection -Name 'baudRateMode' -Value 'auto'
    Add-MissingConfigProperty -Object $Config.connection -Name 'lastWorkingBaudRate' -Value 0
    Add-MissingConfigProperty -Object $Config.connection -Name 'expectedSliders' -Value 5
'@
$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldMigrationBaudBlock `
    -NewText $newMigrationBaudBlock `
    -Label 'migrate auto-baud config'

$autoBaudReplacement = @'
function Get-ControllerBaudCandidates {
    $configured = 9600
    try { $configured = [int]$script:Config.connection.baudRate } catch { }
    if ($configured -lt 300 -or $configured -gt 2000000) {
        $configured = 9600
    }

    $mode = 'auto'
    try { $mode = ([string]$script:Config.connection.baudRateMode).Trim().ToLowerInvariant() } catch { }
    if ($mode -eq 'fixed') {
        return @($configured)
    }

    $lastWorking = 0
    try { $lastWorking = [int]$script:Config.connection.lastWorkingBaudRate } catch { }

    $ordered = New-Object 'System.Collections.Generic.List[int]'
    foreach ($rate in @($lastWorking, $configured, 9600, 115200)) {
        $candidate = [int]$rate
        if ($candidate -lt 300 -or $candidate -gt 2000000) { continue }
        if (-not $ordered.Contains($candidate)) {
            $ordered.Add($candidate)
        }
    }

    return @($ordered.ToArray())
}

function Open-And-ProbePort {
    param([Parameter(Mandatory = $true)][string]$PortName)

    $probeGeneration = $script:ProbeGeneration
    if (Test-ConnectionWorkCancelled -Generation $probeGeneration) { return $false }

    $baudCandidates = @(Get-ControllerBaudCandidates)
    if ($baudCandidates.Count -eq 0) {
        $baudCandidates = @(9600)
    }

    $serial = New-Object System.IO.Ports.SerialPort
    $serial.PortName = $PortName
    $serial.BaudRate = [int]$baudCandidates[0]
    $serial.Parity = [System.IO.Ports.Parity]::None
    $serial.DataBits = 8
    $serial.StopBits = [System.IO.Ports.StopBits]::One
    $serial.Handshake = [System.IO.Ports.Handshake]::None
    $serial.DtrEnable = $false
    $serial.RtsEnable = $false
    $serial.ReadTimeout = 200
    $serial.WriteTimeout = 200
    $serial.NewLine = "`n"

    $accepted = $false
    $cancelled = $false
    $script:ActiveProbeSerial = $serial

    try {
        if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
            $cancelled = $true
            return $false
        }

        Write-Log ('Opening {0} for protocol probe; baud candidates={1}' -f $PortName, ($baudCandidates -join ','))
        $serial.Open()

        if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
            $cancelled = $true
            return $false
        }

        if ($script:PortProbeFailureCounts.ContainsKey($PortName)) {
            [void]$script:PortProbeFailureCounts.Remove($PortName)
        }

        # Opening a Nano/USB-serial device may reset the MCU. Wait once per
        # physical port, then switch SerialPort.BaudRate in-place so trying the
        # second rate does not cause another reset cycle.
        $readyAfter = (Get-Date).AddMilliseconds([int]$script:Config.connection.startupWaitMs)
        while ((Get-Date) -lt $readyAfter) {
            [System.Windows.Forms.Application]::DoEvents()

            if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
                $cancelled = $true
                return $false
            }

            Start-Sleep -Milliseconds 40
        }

        # Correct Mugen packets arrive frequently. 1400 ms is intentionally
        # generous enough for repeated-signature validation while keeping a
        # wrong-baud attempt from adding several seconds to every scan.
        $baudProbeWindowMs = 1400

        foreach ($baudRate in $baudCandidates) {
            if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
                $cancelled = $true
                return $false
            }

            try {
                if ($serial.BaudRate -ne [int]$baudRate) {
                    $serial.BaudRate = [int]$baudRate
                }
                try { $serial.DiscardInBuffer() } catch { }
            }
            catch {
                Write-Log ('Could not switch {0} to {1} baud: {2}' -f $PortName, $baudRate, $_.Exception.Message) 'WARN'
                continue
            }

            Write-Log ('Probing {0} at {1} baud' -f $PortName, $baudRate)

            $deadline = (Get-Date).AddMilliseconds($baudProbeWindowMs)
            $buffer = ''
            $candidateSignature = ''
            $candidateHits = 0

            while ((Get-Date) -lt $deadline) {
                [System.Windows.Forms.Application]::DoEvents()

                if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
                    $cancelled = $true
                    return $false
                }

                Start-Sleep -Milliseconds 40

                if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
                    $cancelled = $true
                    return $false
                }

                $chunk = $serial.ReadExisting()
                if ($chunk.Length -eq 0) { continue }

                $buffer += $chunk
                while ($buffer.Contains("`n")) {
                    $idx = $buffer.IndexOf("`n")
                    $line = $buffer.Substring(0, $idx).Trim("`r", "`n", " ", "`t")
                    $buffer = $buffer.Substring($idx + 1)
                    $parsed = Test-ControllerProtocolLine -Line $line

                    if ($null -ne $parsed) {
                        $signature = Get-ControllerPacketSignature -Packet $parsed
                        if ($signature -eq $candidateSignature) {
                            $candidateHits++
                        }
                        else {
                            $candidateSignature = $signature
                            $candidateHits = 1
                        }

                        # Requiring repeated packets makes accidental valid-looking
                        # garbage at a wrong baud extremely unlikely to be accepted.
                        $requiredHits = if ([string]$parsed.Protocol -eq 'extended') { 2 } else { 3 }
                        if ($candidateHits -lt $requiredHits) { continue }

                        Set-DetectedControllerCapabilities -Packet $parsed -PortName $PortName
                        Initialize-ButtonStates -Values @($parsed.Buttons)
                        if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
                            $cancelled = $true
                            return $false
                        }

                        $script:Serial = $serial
                        $script:ActiveProbeSerial = $null
                        $script:SerialBuffer = $buffer
                        $script:IsConnected = $true
                        $script:ConnectedPort = $PortName
                        $script:ResumeAutoReconnectSuppressed = $false
                        $script:LastSerialPacketAt = Get-Date
                        $script:Config.connection.lastWorkingPort = $PortName
                        $script:Config.connection.lastWorkingBaudRate = [int]$baudRate
                        Clear-PortProbeCooldown -PortName $PortName
                        $script:PendingNewPorts = @($script:PendingNewPorts | Where-Object { $_ -ne $PortName })
                        Save-Config -Config $script:Config
                        Write-Log ('Controller detected on {0} at {1} baud' -f $PortName, $baudRate)
                        $accepted = $true
                        return $true
                    }
                }
            }
        }

        if (-not (Test-ConnectionWorkCancelled -Generation $probeGeneration)) {
            Write-Log ('{0} opened, but Mugen Deej protocol was not detected at baud rates: {1}' -f $PortName, ($baudCandidates -join ',')) 'WARN'
            Set-PortProbeCooldown -PortName $PortName -Seconds $script:NegativeProbeCooldownSeconds
        }
        else {
            $cancelled = $true
        }
    }
    catch {
        if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
            $cancelled = $true
        }
        else {
            $diagnostic = Get-ExceptionDiagnosticText -ErrorRecord $_
            if (Test-IsPortBusyError -ErrorRecord $_) {
                if ($script:LastScanBusyPorts -notcontains $PortName) {
                    $script:LastScanBusyPorts += $PortName
                }
                $retrySeconds = Register-PortProbeFailure -PortName $PortName -Busy
                Write-Log "$PortName is busy or unavailable; $diagnostic; retry in $retrySeconds s" 'WARN'
            }
            else {
                $retrySeconds = Register-PortProbeFailure -PortName $PortName
                Write-Log "Failed to open ${PortName}; $diagnostic; retry in $retrySeconds s" 'WARN'
            }
        }
    }
    finally {
        if ($script:ActiveProbeSerial -eq $serial) {
            $script:ActiveProbeSerial = $null
        }

        if (-not $accepted) {
            try { if ($serial.IsOpen) { $serial.Close() } } catch { }
            try { $serial.Dispose() } catch { }
        }

        if ($cancelled) {
            Write-Log ("Probe of {0} ended because connection work was cancelled" -f $PortName) 'DEBUG'
        }
    }

    return $false
}

function Get-PortsInPreferredOrder {
'@

$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Open-And-ProbePort \{.*?^function Get-PortsInPreferredOrder \{' `
    -Replacement $autoBaudReplacement `
    -Label 'replace port probe with auto-baud probe'

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($resolved, $text, $utf8)
Write-Host "Hardened development runtime and enabled staged automatic 9600/115200 baud probing: $resolved"
