param(
    [string]$SourceDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Fail([string]$Message) {
    Write-Host ""
    Write-Host "ERROR: $Message" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

function Replace-RegexOnce {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Replacement,
        [string]$Label
    )

    $regex = New-Object System.Text.RegularExpressions.Regex(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $matches = $regex.Matches($Text)
    if ($matches.Count -ne 1) {
        throw "$Label: expected exactly 1 match, found $($matches.Count)"
    }

    return $regex.Replace(
        $Text,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            return $Replacement
        },
        1
    )
}

function Replace-Literal {
    param(
        [string]$Text,
        [string]$Old,
        [string]$New,
        [int]$ExpectedCount,
        [string]$Label
    )

    $count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($count -ne $ExpectedCount) {
        throw "$Label: expected $ExpectedCount match(es), found $count"
    }
    return $Text.Replace($Old, $New)
}

try {
    $SourceDir = [System.IO.Path]::GetFullPath($SourceDir)
    $sourceScript = Join-Path $SourceDir 'MugenDeej.ps1'
    $sourceExe = Join-Path $SourceDir 'MugenDeej.exe'

    if (-not (Test-Path -LiteralPath $sourceScript)) {
        Fail "MugenDeej.ps1 was not found in: $SourceDir"
    }
    if (-not (Test-Path -LiteralPath $sourceExe)) {
        Fail "MugenDeej.exe was not found in: $SourceDir"
    }

    $sourceText = [System.IO.File]::ReadAllText($sourceScript)
    if ($sourceText -notmatch "\$script:AppVersion\s*=\s*'0\.8\.7'") {
        Fail "This installer expects the tested Mugen Deej 0.8.7 source."
    }

    $parent = Split-Path -Parent $SourceDir
    $targetDir = Join-Path $parent 'Mugen-Deej-0.9.0-dev1'

    if (Test-Path -LiteralPath $targetDir) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $targetDir = Join-Path $parent ("Mugen-Deej-0.9.0-dev1-" + $stamp)
    }

    Write-Host ""
    Write-Host "Mugen Deej 0.9.0-dev1 laboratory installer" -ForegroundColor Cyan
    Write-Host "Source : $SourceDir"
    Write-Host "Target : $targetDir"
    Write-Host ""
    Write-Host "Copying the stable folder..." -ForegroundColor Yellow

    [void](New-Item -ItemType Directory -Path $targetDir)
    Get-ChildItem -LiteralPath $SourceDir -Force | ForEach-Object {
        if ($_.Name -eq 'logs') { return }
        Copy-Item -LiteralPath $_.FullName -Destination $targetDir -Recurse -Force
    }

    $targetScript = Join-Path $targetDir 'MugenDeej.ps1'
    $text = [System.IO.File]::ReadAllText($targetScript)

    $text = $text -replace '# Mugen Deej 0\.8\.7-dev', '# Mugen Deej 0.9.0-dev1'
    $text = $text -replace "\$script:AppVersion\s*=\s*'0\.8\.7'", "`$script:AppVersion = '0.9.0-dev1'"

    $stateBlock = @'
$script:ControllerProtocol = 'unknown'
$script:DetectedSliderCount = 0
$script:DetectedButtonCount = 0
$script:LatestButtons = @()
$script:LastButtonStates = @()
$script:LastCapabilityMismatchLog = [DateTime]::MinValue
'@

    $text = Replace-RegexOnce `
        -Text $text `
        -Pattern "(\$script:AppVersion\s*=\s*'0\.9\.0-dev1'\r?\n)" `
        -Replacement ("`$script:AppVersion = '0.9.0-dev1'`r`n" + $stateBlock + "`r`n") `
        -Label 'insert controller capability state'

    $protocolFunctions = @'
function Get-ControllerPacketSignature {
    param([Parameter(Mandatory = $true)]$Packet)
    return ('{0}:{1}:{2}' -f [string]$Packet.Protocol, @($Packet.Sliders).Count, @($Packet.Buttons).Count)
}

function Test-ControllerProtocolLine {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }

    $parts = @($Line.Trim() -split '\|')
    if ($parts.Count -lt 1 -or $parts.Count -gt 64) { return $null }

    $legacyValues = New-Object 'System.Collections.Generic.List[int]'
    $legacy = $true
    foreach ($part in $parts) {
        $value = 0
        if (-not [int]::TryParse($part, [ref]$value) -or $value -lt 0 -or $value -gt 1023) {
            $legacy = $false
            break
        }
        $legacyValues.Add($value)
    }

    if ($legacy -and $legacyValues.Count -gt 0) {
        return [pscustomobject]@{
            Protocol = 'legacy'
            Sliders = @($legacyValues.ToArray())
            Buttons = @()
        }
    }

    $sliders = New-Object 'System.Collections.Generic.List[int]'
    $buttons = New-Object 'System.Collections.Generic.List[int]'

    foreach ($part in $parts) {
        $match = [regex]::Match($part, '^(?<kind>[sSbB])(?<value>\d{1,4})$')
        if (-not $match.Success) { return $null }

        $kind = $match.Groups['kind'].Value.ToLowerInvariant()
        $value = 0
        if (-not [int]::TryParse($match.Groups['value'].Value, [ref]$value)) { return $null }

        if ($kind -eq 's') {
            if ($value -lt 0 -or $value -gt 1023) { return $null }
            $sliders.Add($value)
        }
        elseif ($kind -eq 'b') {
            if ($value -ne 0 -and $value -ne 1) { return $null }
            $buttons.Add($value)
        }
        else {
            return $null
        }
    }

    if ($sliders.Count -lt 1) { return $null }

    return [pscustomobject]@{
        Protocol = 'extended'
        Sliders = @($sliders.ToArray())
        Buttons = @($buttons.ToArray())
    }
}

function Get-ControllerConnectedStatusText {
    param([Parameter(Mandatory = $true)][string]$PortName)

    $sliderCount = [int]$script:DetectedSliderCount
    $buttonCount = [int]$script:DetectedButtonCount

    if ($sliderCount -le 0) {
        $sliderCount = [int]$script:Config.connection.expectedSliders
    }

    if ($script:Language -eq 'ru') {
        if ($buttonCount -gt 0) {
            return ('Контроллер подключён — {0} · {1} регуляторов · {2} кнопок' -f $PortName, $sliderCount, $buttonCount)
        }
        return ('Контроллер подключён — {0} · {1} регуляторов' -f $PortName, $sliderCount)
    }

    if ($buttonCount -gt 0) {
        return ('Controller connected — {0} · {1} controls · {2} buttons' -f $PortName, $sliderCount, $buttonCount)
    }
    return ('Controller connected — {0} · {1} controls' -f $PortName, $sliderCount)
}

function Set-DetectedControllerCapabilities {
    param(
        [Parameter(Mandatory = $true)]$Packet,
        [string]$PortName = ''
    )

    $protocol = [string]$Packet.Protocol
    $sliderCount = @($Packet.Sliders).Count
    $buttonCount = @($Packet.Buttons).Count

    $changed = (
        $script:ControllerProtocol -ne $protocol -or
        $script:DetectedSliderCount -ne $sliderCount -or
        $script:DetectedButtonCount -ne $buttonCount
    )

    $script:ControllerProtocol = $protocol
    $script:DetectedSliderCount = $sliderCount
    $script:DetectedButtonCount = $buttonCount

    if ($changed) {
        Write-Log (
            'Controller capabilities detected: port={0}; protocol={1}; sliders={2}; buttons={3}' -f
            $PortName, $protocol, $sliderCount, $buttonCount
        ) 'INFO'
    }
}

function Initialize-ButtonStates {
    param([int[]]$Values)

    $script:LatestButtons = @($Values)
    $script:LastButtonStates = @($Values)

    if (@($Values).Count -gt 0) {
        Write-Log ('Button states initialized: {0}' -f (@($Values) -join ',')) 'DEBUG'
    }
}

function Update-ButtonStates {
    param([int[]]$Values)

    $valuesArray = @($Values)
    $script:LatestButtons = $valuesArray

    if ($valuesArray.Count -eq 0) {
        $script:LastButtonStates = @()
        return
    }

    if (@($script:LastButtonStates).Count -ne $valuesArray.Count) {
        Initialize-ButtonStates -Values $valuesArray
        return
    }

    for ($i = 0; $i -lt $valuesArray.Count; $i++) {
        $newValue = [int]$valuesArray[$i]
        $oldValue = [int]$script:LastButtonStates[$i]
        if ($newValue -eq $oldValue) { continue }

        $script:LastButtonStates[$i] = $newValue
        $state = if ($newValue -eq 0) { 'pressed' } else { 'released' }
        Write-Log ('Button {0} {1} (raw={2})' -f ($i + 1), $state, $newValue) 'INFO'
    }
}

function Test-ControllerPacketMatchesCapabilities {
    param([Parameter(Mandatory = $true)]$Packet)

    if ($script:ControllerProtocol -eq 'unknown' -or $script:DetectedSliderCount -le 0) {
        return $true
    }

    return (
        [string]$Packet.Protocol -eq $script:ControllerProtocol -and
        @($Packet.Sliders).Count -eq $script:DetectedSliderCount -and
        @($Packet.Buttons).Count -eq $script:DetectedButtonCount
    )
}
'@

    $text = Replace-RegexOnce `
        -Text $text `
        -Pattern "function Test-ProtocolLine \{.*?\r?\n\}\r?\n\r?\nfunction Close-ControllerPort" `
        -Replacement ($protocolFunctions + "`r`n`r`nfunction Close-ControllerPort") `
        -Label 'replace protocol parser'

    $closeReset = @'
    $script:LatestLevels = @()
    $script:ControllerProtocol = 'unknown'
    $script:DetectedSliderCount = 0
    $script:DetectedButtonCount = 0
    $script:LatestButtons = @()
    $script:LastButtonStates = @()
'@
    $text = Replace-RegexOnce `
        -Text $text `
        -Pattern "\s+\$script:LatestLevels = @\(\)\r?\n\r?\n    if \(\$Detailed\)" `
        -Replacement ("`r`n" + $closeReset + "`r`n    if (`$Detailed)") `
        -Label 'reset capability state on close'

    $text = Replace-RegexOnce `
        -Text $text `
        -Pattern "(\$readyAfter = \(Get-Date\)\.AddMilliseconds\(\[int\]\$script:Config\.connection\.startupWaitMs\)\r?\n\s+\$buffer = '')" `
        -Replacement ("`$readyAfter = (Get-Date).AddMilliseconds([int]`$script:Config.connection.startupWaitMs)`r`n        `$buffer = ''`r`n        `$candidateSignature = ''`r`n        `$candidateHits = 0") `
        -Label 'add probe confidence state'

    $oldParserCall = '$parsed = Test-ProtocolLine -Line $line -ExpectedCount ([int]$script:Config.connection.expectedSliders)'
    $newParserCall = '$parsed = Test-ControllerProtocolLine -Line $line'
    $text = Replace-Literal `
        -Text $text `
        -Old $oldParserCall `
        -New $newParserCall `
        -ExpectedCount 2 `
        -Label 'replace parser calls'

    $probeGate = @'
                if ($null -ne $parsed) {
                    $signature = Get-ControllerPacketSignature -Packet $parsed
                    if ($signature -eq $candidateSignature) {
                        $candidateHits++
                    }
                    else {
                        $candidateSignature = $signature
                        $candidateHits = 1
                    }

                    $requiredHits = if ([string]$parsed.Protocol -eq 'extended') { 2 } else { 3 }
                    if ($candidateHits -lt $requiredHits) { continue }

                    Set-DetectedControllerCapabilities -Packet $parsed -PortName $PortName
                    Initialize-ButtonStates -Values @($parsed.Buttons)
'@

    $text = Replace-RegexOnce `
        -Text $text `
        -Pattern "(function Open-And-ProbePort \{.*?\$parsed = Test-ControllerProtocolLine -Line \$line\r?\n\r?\n)\s+if \(\$null -ne \$parsed\) \{" `
        -Replacement ('$1' + $probeGate) `
        -Label 'add capability detection to probe'

    $runtimeBlock = @'
            if ($null -ne $parsed) {
                if (Test-ControllerPacketMatchesCapabilities -Packet $parsed) {
                    Update-ButtonStates -Values @($parsed.Buttons)
                    $latestParsed = $parsed
                }
                else {
                    $nowMismatch = Get-Date
                    if (
                        $script:LastCapabilityMismatchLog -eq [DateTime]::MinValue -or
                        ($nowMismatch - $script:LastCapabilityMismatchLog).TotalSeconds -ge 5
                    ) {
                        Write-Log (
                            'Ignored packet whose shape changed while connected: expected={0}:{1}:{2}; got={3}' -f
                            $script:ControllerProtocol,
                            $script:DetectedSliderCount,
                            $script:DetectedButtonCount,
                            (Get-ControllerPacketSignature -Packet $parsed)
                        ) 'WARN'
                        $script:LastCapabilityMismatchLog = $nowMismatch
                    }
                }
            }
'@

    $text = Replace-RegexOnce `
        -Text $text `
        -Pattern "(function Process-SerialData \{.*?\$parsed = Test-ControllerProtocolLine -Line \$line\r?\n)\s+if \(\$null -ne \$parsed\) \{ \$latestParsed = \$parsed \}" `
        -Replacement ('$1' + $runtimeBlock) `
        -Label 'add runtime extended packet handling'

    $text = Replace-Literal `
        -Text $text `
        -Old '    if ($Values.Count -ne [int]$script:Config.connection.expectedSliders) { return }' `
        -New '    if ($null -eq $Values -or $Values.Count -lt 1) { return }' `
        -ExpectedCount 1 `
        -Label 'allow detected slider count'

    $text = Replace-Literal `
        -Text $text `
        -Old '            Apply-SliderValues -Values $latestParsed' `
        -New '            Apply-SliderValues -Values @($latestParsed.Sliders)' `
        -ExpectedCount 1 `
        -Label 'apply slider values from packet object'

    $statusRegex = New-Object System.Text.RegularExpressions.Regex(
        "Set-Status \(T -Key 'StatusConnected' -Args @\((?<port>[^,\r\n]+), \[int\]\$script:Config\.connection\.expectedSliders\)\) 'ok'"
    )
    $statusMatches = $statusRegex.Matches($text)
    if ($statusMatches.Count -lt 2) {
        throw "connected status replacement: expected at least 2 matches, found $($statusMatches.Count)"
    }
    $text = $statusRegex.Replace(
        $text,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            return "Set-Status (Get-ControllerConnectedStatusText -PortName $($m.Groups['port'].Value)) 'ok'"
        }
    )

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput(
        $text,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        $details = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
        throw "PowerShell syntax validation failed: $details"
    }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($targetScript, $text, $utf8Bom)

    $marker = @"
Mugen Deej 0.9.0-dev1
Experimental controller protocol/autodetect build.

Base: 0.8.7
Purpose:
- classic numeric deej protocol
- extended s/b protocol
- automatic slider/button count detection
- raw button press/release logging only
- NO button actions yet

Stable source folder was not modified:
$SourceDir
"@
    [System.IO.File]::WriteAllText(
        (Join-Path $targetDir 'DEV_BUILD.txt'),
        $marker,
        $utf8Bom
    )

    Write-Host ""
    Write-Host "Syntax check passed." -ForegroundColor Green
    Write-Host "Created: $targetDir" -ForegroundColor Green
    Write-Host ""
    Write-Host "IMPORTANT:" -ForegroundColor Yellow
    Write-Host "1. Do NOT reflash the Arduino yet."
    Write-Host "2. Close the stable Mugen Deej before starting dev1."
    Write-Host "3. Run MugenDeej.exe from the new dev1 folder."
    Write-Host "4. Check that the status shows 5 controls and 6 buttons."
    Write-Host "5. Turn all knobs, then press each button once."
    Write-Host ""
    Write-Host "The button test only writes pressed/released events to logs\mugen-deej.log."
    Write-Host "It does NOT send any key presses or media commands yet."
    Write-Host ""
    Read-Host "Press Enter to close"
}
catch {
    Fail $_.Exception.Message
}
