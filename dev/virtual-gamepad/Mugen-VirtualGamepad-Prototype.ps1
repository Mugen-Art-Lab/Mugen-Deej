param(
    [string]$Port = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Parse-ExtendedPacket {
    param([Parameter(Mandatory = $true)][string]$Line)

    $parts = @($Line.Trim() -split '\|')
    if ($parts.Count -lt 2 -or $parts.Count -gt 64) { return $null }

    $sliders = New-Object System.Collections.Generic.List[int]
    $buttons = New-Object System.Collections.Generic.List[int]
    $seenButton = $false

    foreach ($part in $parts) {
        if ($part -match '^s(\d{1,4})$') {
            if ($seenButton) { return $null }
            $value = [int]$Matches[1]
            if ($value -lt 0 -or $value -gt 1023) { return $null }
            $sliders.Add($value)
            continue
        }

        if ($part -match '^b([01])$') {
            $seenButton = $true
            $buttons.Add([int]$Matches[1])
            continue
        }

        return $null
    }

    if ($sliders.Count -lt 1 -or $buttons.Count -lt 1) { return $null }

    return [pscustomobject]@{
        Sliders = @($sliders)
        Buttons = @($buttons)
    }
}

function Open-ExtendedController {
    param([string]$RequestedPort = '')

    $ports = if ([string]::IsNullOrWhiteSpace($RequestedPort)) {
        @([System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object)
    }
    else {
        @($RequestedPort)
    }

    if ($ports.Count -eq 0) {
        throw 'No COM ports were found.'
    }

    foreach ($portName in $ports) {
        $serial = $null
        try {
            Write-Host "Checking $portName..."
            $serial = New-Object System.IO.Ports.SerialPort(
                $portName,
                9600,
                [System.IO.Ports.Parity]::None,
                8,
                [System.IO.Ports.StopBits]::One
            )
            $serial.Handshake = [System.IO.Ports.Handshake]::None
            $serial.NewLine = "`n"
            $serial.ReadTimeout = 250
            $serial.WriteTimeout = 250
            $serial.Open()

            # Classic Nano/USB-serial boards often reset when the port opens.
            Start-Sleep -Milliseconds 1400
            try { $serial.DiscardInBuffer() } catch { }

            $deadline = (Get-Date).AddSeconds(4)
            while ((Get-Date) -lt $deadline) {
                try {
                    $line = $serial.ReadLine().Trim("`r", "`n", " ", "`t")
                }
                catch [System.TimeoutException] {
                    continue
                }

                $packet = Parse-ExtendedPacket -Line $line
                if ($null -ne $packet) {
                    return [pscustomobject]@{
                        Port = $portName
                        Serial = $serial
                        Packet = $packet
                    }
                }
            }
        }
        catch {
            Write-Host ("  skipped: " + $_.Exception.Message) -ForegroundColor DarkYellow
        }

        if ($null -ne $serial) {
            try { if ($serial.IsOpen) { $serial.Close() } } catch { }
            try { $serial.Dispose() } catch { }
        }
    }

    throw 'No Extended Mugen Deej controller was recognized. Close the normal Mugen Deej app if it currently owns the COM port.'
}

function Send-HostCommand {
    param(
        [Parameter(Mandatory = $true)][System.IO.StreamWriter]$Writer,
        [Parameter(Mandatory = $true)][System.IO.StreamReader]$Reader,
        [Parameter(Mandatory = $true)][string]$Command
    )

    $Writer.WriteLine($Command)
    $response = $Reader.ReadLine()
    if ($null -eq $response) {
        throw 'Virtual gamepad host disconnected unexpectedly.'
    }
    if ($response -notin @('OK', 'PONG', 'BYE') -and -not $response.StartsWith('READY|')) {
        throw "Virtual gamepad host error: $response"
    }
    return $response
}

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$hostPath = Join-Path $baseDir 'host\MugenDeej.VirtualGamepadHost.exe'
$hostLogPath = Join-Path $env:TEMP 'MugenDeej-VirtualGamepadHost.log'

if (-not (Test-Path -LiteralPath $hostPath -PathType Leaf)) {
    throw "Virtual gamepad host is missing: $hostPath"
}

$controller = $null
$helperProcess = $null
$pipe = $null
$reader = $null
$writer = $null

try {
    Write-Host ''
    Write-Host 'Mugen Deej Virtual Gamepad Prototype' -ForegroundColor Cyan
    Write-Host '------------------------------------'
    Write-Host 'Close the normal Mugen Deej application before this test so the prototype can own the COM port.'
    Write-Host ''

    $controller = Open-ExtendedController -RequestedPort $Port
    $serial = $controller.Serial
    $firstPacket = $controller.Packet

    Write-Host (
        'Extended controller found on {0}: {1} controls, {2} buttons' -f
        $controller.Port,
        @($firstPacket.Sliders).Count,
        @($firstPacket.Buttons).Count
    ) -ForegroundColor Green

    $pipeName = 'MugenDeejVirtualGamepad-' + [Guid]::NewGuid().ToString('N')
    $helperArgs = @(
        'server',
        '--pipe', $pipeName,
        '--profile', 'xbox-360-wired',
        '--identity', 'mugen-deej-prototype'
    )

    Write-Host ''
    Write-Host 'Starting the elevated virtual-controller host. Accept the UAC prompt.' -ForegroundColor Yellow

    $helperProcess = Start-Process `
        -FilePath $hostPath `
        -ArgumentList $helperArgs `
        -Verb RunAs `
        -WindowStyle Hidden `
        -PassThru

    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(
        '.',
        $pipeName,
        [System.IO.Pipes.PipeDirection]::InOut,
        [System.IO.Pipes.PipeOptions]::None
    )

    try {
        $pipe.Connect(45000)
    }
    catch {
        $logHint = if (Test-Path -LiteralPath $hostLogPath) { " Host log: $hostLogPath" } else { '' }
        throw ('Could not connect to the virtual-controller host. The UAC prompt may have been cancelled or the backend failed.' + $logHint)
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $reader = New-Object System.IO.StreamReader($pipe, $utf8, $false, 4096, $true)
    $writer = New-Object System.IO.StreamWriter($pipe, $utf8, 4096, $true)
    $writer.AutoFlush = $true
    $writer.NewLine = "`n"

    $ready = $reader.ReadLine()
    if ($null -eq $ready -or -not $ready.StartsWith('READY|')) {
        throw "Virtual-controller host did not become ready. Response: $ready"
    }

    Write-Host ''
    Write-Host 'Virtual Xbox 360 controller is ready.' -ForegroundColor Green
    Write-Host 'Current prototype mapping:'
    Write-Host '  Physical button 1 -> A'
    Write-Host '  Physical button 2 -> B'
    Write-Host '  Physical button 3 -> X'
    Write-Host '  Physical button 4 -> Y'
    Write-Host '  Physical button 5 -> Left Bumper'
    Write-Host '  Physical button 6 -> Right Bumper'
    Write-Host ''
    Write-Host 'joy.cpl will open now. Open Properties for the virtual Xbox controller and press/release physical buttons.'
    Write-Host 'Press Q or Esc in this console to stop the test.' -ForegroundColor Cyan
    Write-Host ''

    try { Start-Process 'control.exe' -ArgumentList 'joy.cpl' | Out-Null } catch { }

    $expectedSliderCount = @($firstPacket.Sliders).Count
    $expectedButtonCount = @($firstPacket.Buttons).Count
    [uint32]$lastMask = [uint32]::MaxValue

    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -in @([ConsoleKey]::Q, [ConsoleKey]::Escape)) {
                break
            }
        }

        try {
            $line = $serial.ReadLine().Trim("`r", "`n", " ", "`t")
        }
        catch [System.TimeoutException] {
            continue
        }

        $packet = Parse-ExtendedPacket -Line $line
        if ($null -eq $packet) { continue }
        if (@($packet.Sliders).Count -ne $expectedSliderCount) { continue }
        if (@($packet.Buttons).Count -ne $expectedButtonCount) { continue }

        [uint32]$mask = 0
        $mappedCount = [Math]::Min(6, @($packet.Buttons).Count)
        for ($i = 0; $i -lt $mappedCount; $i++) {
            # Mugen Extended buttons are active-low: b0 = pressed, b1 = released.
            if ([int]$packet.Buttons[$i] -eq 0) {
                $mask = $mask -bor ([uint32]1 -shl $i)
            }
        }

        if ($mask -eq $lastMask) { continue }
        $lastMask = $mask

        [void](Send-HostCommand -Writer $writer -Reader $reader -Command ("buttons $mask"))
        Write-Host ("Buttons mask: 0x{0:X2}" -f $mask)
    }
}
finally {
    if ($null -ne $writer -and $null -ne $reader) {
        try { [void](Send-HostCommand -Writer $writer -Reader $reader -Command 'release') } catch { }
        try { [void](Send-HostCommand -Writer $writer -Reader $reader -Command 'quit') } catch { }
    }

    if ($null -ne $writer) { try { $writer.Dispose() } catch { } }
    if ($null -ne $reader) { try { $reader.Dispose() } catch { } }
    if ($null -ne $pipe) { try { $pipe.Dispose() } catch { } }

    if ($null -ne $controller) {
        try { if ($controller.Serial.IsOpen) { $controller.Serial.Close() } } catch { }
        try { $controller.Serial.Dispose() } catch { }
    }

    if ($null -ne $helperProcess) {
        try {
            if (-not $helperProcess.HasExited) {
                $helperProcess.WaitForExit(5000) | Out-Null
            }
            if (-not $helperProcess.HasExited) {
                $helperProcess.Kill()
            }
        }
        catch { }
    }

    Write-Host ''
    Write-Host 'Prototype stopped. Virtual buttons were released and the virtual controller host was closed.' -ForegroundColor DarkGray
}
