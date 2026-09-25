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
        throw "Adaptive protocol patch '$Label' expected exactly one literal match."
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
    $regex = New-Object System.Text.RegularExpressions.Regex($Pattern, $options)
    $matches = $regex.Matches($Text)
    if ($matches.Count -ne 1) {
        throw "Adaptive protocol patch '$Label' expected exactly one regex block match, found $($matches.Count)."
    }

    $match = $matches[0]
    return $Text.Substring(0, $match.Index) + $Replacement + $Text.Substring($match.Index + $match.Length)
}

$resolved = (Resolve-Path -LiteralPath $Path).Path
$text = [System.IO.File]::ReadAllText($resolved, [System.Text.Encoding]::UTF8)

# ---------------------------------------------------------------------------
# Runtime state for typed controls
# ---------------------------------------------------------------------------

$oldRuntimeState = @'
$script:DetectedSliderCount = 0
$script:DetectedButtonCount = 0
$script:LatestButtons = @()
'@

$newRuntimeState = @'
$script:DetectedSliderCount = 0
$script:DetectedButtonCount = 0
$script:DetectedToggleCount = 0
$script:DetectedEncoderCount = 0
$script:LatestButtons = @()
$script:LatestToggles = @()
$script:LatestEncoders = @()
$script:LastEncoderPositions = @()
$script:AdaptiveDebounceDiagnostics = $null
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldRuntimeState `
    -NewText $newRuntimeState `
    -Label 'typed-control runtime state'

# ---------------------------------------------------------------------------
# Packet signature + Adaptive v3 parser
# ---------------------------------------------------------------------------
# Protocol generations:
#   legacy   = raw numeric slider values
#   extended = typed s/b fields
#   adaptive = explicit v3 marker plus s/b/t/e typed fields
#
# Adaptive encoder token:
#   e<signed-position>[:<push-state>]
# Position is a cumulative detent counter, not a pulse. Missing serial frames
# therefore do not lose intermediate encoder movement; the desktop computes the
# delta from the last received position. push-state follows existing button
# electrical semantics: 0 = pressed, 1 = released.

$oldSignature = @'
function Get-ControllerPacketSignature {
    param([Parameter(Mandatory = $true)]$Packet)
    return ('{0}:{1}:{2}' -f [string]$Packet.Protocol, @($Packet.Sliders).Count, @($Packet.Buttons).Count)
}
'@

$newSignature = @'
function Get-ControllerPacketArray {
    param(
        [Parameter(Mandatory = $true)]$Packet,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $Packet.PSObject.Properties[$Name]
    if ($null -eq $property) { return @() }
    return @($property.Value)
}

function Get-ControllerPacketSignature {
    param([Parameter(Mandatory = $true)]$Packet)

    $toggles = @(Get-ControllerPacketArray -Packet $Packet -Name 'Toggles')
    $encoders = @(Get-ControllerPacketArray -Packet $Packet -Name 'Encoders')

    return ('{0}:{1}:{2}:{3}:{4}' -f
        [string]$Packet.Protocol,
        @($Packet.Sliders).Count,
        @($Packet.Buttons).Count,
        $toggles.Count,
        $encoders.Count
    )
}
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldSignature `
    -NewText $newSignature `
    -Label 'typed packet signature'

$oldParserPrelude = @'
    $parts = @($Line.Trim() -split '\|')
    if ($parts.Count -lt 1 -or $parts.Count -gt 64) { return $null }

    # Classic deej protocol: raw numeric values only.
'@

$newParserPrelude = @'
    $parts = @($Line.Trim() -split '\|')
    if ($parts.Count -lt 1 -or $parts.Count -gt 64) { return $null }

    # Adaptive v3: explicit version marker plus first-class typed controls.
    # Example:
    #   v3|s0|s512|b1|b0|t0|t1|e42:1
    #
    # b0/b1 preserve Extended semantics (0 pressed, 1 released).
    # t0/t1 are logical OFF/ON states.
    # eN[:P] reports a cumulative signed detent position and optional push
    # state P using button semantics (0 pressed, 1 released).
    #
    # Optional low-latency firmware diagnostic:
    #   d<debounceMs>:<filteredCount>:<filteredMaskHex>:<rapidCount>:<rapidMaskHex>
    # It is ignored for controller capability/signature matching.
    if ([string]$parts[0] -eq 'v3') {
        if ($parts.Count -lt 2) { return $null }

        $adaptiveSliders = New-Object 'System.Collections.Generic.List[int]'
        $adaptiveButtons = New-Object 'System.Collections.Generic.List[int]'
        $adaptiveToggles = New-Object 'System.Collections.Generic.List[int]'
        $adaptiveEncoders = New-Object System.Collections.ArrayList
        $adaptiveDiagnostics = $null

        for ($partIndex = 1; $partIndex -lt $parts.Count; $partIndex++) {
            $part = [string]$parts[$partIndex]
            if ([string]::IsNullOrWhiteSpace($part)) { return $null }

            if ($part -match '^s(\d{1,4})$') {
                $value = 0
                if (-not [int]::TryParse($Matches[1], [ref]$value)) { return $null }
                if ($value -lt 0 -or $value -gt 1023) { return $null }
                $adaptiveSliders.Add($value)
                continue
            }

            if ($part -match '^b([01])$') {
                $adaptiveButtons.Add([int]$Matches[1])
                continue
            }

            if ($part -match '^t([01])$') {
                $adaptiveToggles.Add([int]$Matches[1])
                continue
            }

            if ($part -match '^e(-?\d+)(?::([01]))?$') {
                $position = [int64]0
                if (-not [int64]::TryParse($Matches[1], [ref]$position)) { return $null }

                $hasPush = -not [string]::IsNullOrWhiteSpace([string]$Matches[2])
                $push = 1
                if ($hasPush) {
                    $push = [int]$Matches[2]
                }

                [void]$adaptiveEncoders.Add([pscustomobject]@{
                    Position = $position
                    Push = $push
                    HasPush = $hasPush
                })
                continue
            }

            if ($part -match '^d(\d{1,3}):(\d+):([0-9A-Fa-f]{1,8}):(\d+):([0-9A-Fa-f]{1,8})$') {
                if ($null -ne $adaptiveDiagnostics) { return $null }

                $debounceMs = 0
                [uint64]$filteredCount = 0
                [uint64]$rapidCount = 0
                if (-not [int]::TryParse($Matches[1], [ref]$debounceMs)) { return $null }
                if (-not [uint64]::TryParse($Matches[2], [ref]$filteredCount)) { return $null }
                if (-not [uint64]::TryParse($Matches[4], [ref]$rapidCount)) { return $null }

                try {
                    [uint32]$filteredMask = [Convert]::ToUInt32($Matches[3], 16)
                    [uint32]$rapidMask = [Convert]::ToUInt32($Matches[5], 16)
                }
                catch {
                    return $null
                }

                $adaptiveDiagnostics = [pscustomobject][ordered]@{
                    DebounceMs = $debounceMs
                    FilteredCount = $filteredCount
                    FilteredMask = $filteredMask
                    RapidCount = $rapidCount
                    RapidMask = $rapidMask
                }
                continue
            }

            return $null
        }

        if ($adaptiveSliders.Count -lt 1) { return $null }

        return [pscustomobject]@{
            Protocol = 'adaptive'
            Sliders = @($adaptiveSliders.ToArray())
            Buttons = @($adaptiveButtons.ToArray())
            Toggles = @($adaptiveToggles.ToArray())
            Encoders = @($adaptiveEncoders.ToArray())
            Diagnostics = $adaptiveDiagnostics
        }
    }

    # Classic deej protocol: raw numeric values only.
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldParserPrelude `
    -NewText $newParserPrelude `
    -Label 'Adaptive v3 parser branch'

# ---------------------------------------------------------------------------
# Typed-state bookkeeping and user-facing capability text
# ---------------------------------------------------------------------------

$typedHelpersAndStatus = @'
function Get-AdaptiveDebounceDiagnostics {
    param([Parameter(Mandatory = $true)]$Packet)

    $property = $Packet.PSObject.Properties['Diagnostics']
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-AdaptiveDebounceDiagnosticContacts {
    param([uint32]$Mask)

    $labels = New-Object 'System.Collections.Generic.List[string]'
    for ($bit = 0; $bit -lt 28; $bit++) {
        if (($Mask -band ([uint32]1 -shl $bit)) -ne 0) {
            $labels.Add(('B{0}' -f ($bit + 1)))
        }
    }
    if (($Mask -band ([uint32]1 -shl 28)) -ne 0) { $labels.Add('T1') }
    if (($Mask -band ([uint32]1 -shl 29)) -ne 0) { $labels.Add('T2') }

    if ($labels.Count -eq 0) { return 'none' }
    return ($labels -join ',')
}

function Initialize-AdaptiveControlStates {
    param([Parameter(Mandatory = $true)]$Packet)

    $script:LatestToggles = @(Get-ControllerPacketArray -Packet $Packet -Name 'Toggles')
    $script:LatestEncoders = @(Get-ControllerPacketArray -Packet $Packet -Name 'Encoders')
    $script:LastEncoderPositions = @()
    $script:AdaptiveDebounceDiagnostics = Get-AdaptiveDebounceDiagnostics -Packet $Packet

    foreach ($encoder in $script:LatestEncoders) {
        $script:LastEncoderPositions += [int64]$encoder.Position
    }

    if ($null -ne $script:AdaptiveDebounceDiagnostics) {
        Write-Log (
            'Firmware debounce diagnostics active: matrixDebounce={0} ms; filtered={1}; rapid={2}' -f
            [int]$script:AdaptiveDebounceDiagnostics.DebounceMs,
            [uint64]$script:AdaptiveDebounceDiagnostics.FilteredCount,
            [uint64]$script:AdaptiveDebounceDiagnostics.RapidCount
        ) 'INFO'
    }
}

function Update-AdaptiveControlStates {
    param([Parameter(Mandatory = $true)]$Packet)

    $newToggles = @(Get-ControllerPacketArray -Packet $Packet -Name 'Toggles')
    $newEncoders = @(Get-ControllerPacketArray -Packet $Packet -Name 'Encoders')
    $newDiagnostics = Get-AdaptiveDebounceDiagnostics -Packet $Packet

    if ($null -ne $newDiagnostics) {
        $oldDiagnostics = $script:AdaptiveDebounceDiagnostics
        $diagnosticsChanged = (
            $null -eq $oldDiagnostics -or
            [uint64]$newDiagnostics.FilteredCount -ne [uint64]$oldDiagnostics.FilteredCount -or
            [uint64]$newDiagnostics.RapidCount -ne [uint64]$oldDiagnostics.RapidCount
        )

        if ($diagnosticsChanged -and $null -ne $oldDiagnostics) {
            $filteredDelta = [int64]$newDiagnostics.FilteredCount - [int64]$oldDiagnostics.FilteredCount
            $rapidDelta = [int64]$newDiagnostics.RapidCount - [int64]$oldDiagnostics.RapidCount
            $contactsMask = [uint32]$newDiagnostics.FilteredMask -bor [uint32]$newDiagnostics.RapidMask
            Write-Log (
                'Firmware debounce diagnostic: matrixDebounce={0} ms; filtered={1} ({2:+#;-#;0}); rapid={3} ({4:+#;-#;0}); contacts={5}' -f
                [int]$newDiagnostics.DebounceMs,
                [uint64]$newDiagnostics.FilteredCount,
                $filteredDelta,
                [uint64]$newDiagnostics.RapidCount,
                $rapidDelta,
                (Get-AdaptiveDebounceDiagnosticContacts -Mask $contactsMask)
            ) 'INFO'
        }

        $script:AdaptiveDebounceDiagnostics = $newDiagnostics
    }

    $oldToggles = @($script:LatestToggles)
    for ($i = 0; $i -lt $newToggles.Count; $i++) {
        if ($i -lt $oldToggles.Count -and [int]$oldToggles[$i] -ne [int]$newToggles[$i]) {
            $stateText = if ([int]$newToggles[$i] -eq 1) { 'ON' } else { 'OFF' }
            Write-Log ('Toggle {0} changed: {1}' -f ($i + 1), $stateText) 'INFO'
        }
    }

    $oldEncoders = @($script:LatestEncoders)
    for ($i = 0; $i -lt $newEncoders.Count; $i++) {
        $position = [int64]$newEncoders[$i].Position

        if ($i -lt $script:LastEncoderPositions.Count) {
            $delta = $position - [int64]$script:LastEncoderPositions[$i]
            if ($delta -ne 0) {
                Write-Log ('Encoder {0} moved: delta={1}; position={2}' -f ($i + 1), $delta, $position) 'INFO'
            }
        }

        if ($i -lt $oldEncoders.Count) {
            $oldHasPush = [bool]$oldEncoders[$i].HasPush
            $newHasPush = [bool]$newEncoders[$i].HasPush
            if ($oldHasPush -and $newHasPush -and [int]$oldEncoders[$i].Push -ne [int]$newEncoders[$i].Push) {
                $pushText = if ([int]$newEncoders[$i].Push -eq 0) { 'pressed' } else { 'released' }
                Write-Log ('Encoder {0} push {1}' -f ($i + 1), $pushText) 'INFO'
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

function Get-ControllerConnectedStatusText {
    param([Parameter(Mandatory = $true)][string]$PortName)

    $sliderCount = [int]$script:DetectedSliderCount
    $buttonCount = [int]$script:DetectedButtonCount
    $toggleCount = [int]$script:DetectedToggleCount
    $encoderCount = [int]$script:DetectedEncoderCount

    if ($sliderCount -le 0) {
        $sliderCount = [int]$script:Config.connection.expectedSliders
    }

    if ($script:Language -eq 'ru') {
        $parts = New-Object 'System.Collections.Generic.List[string]'
        $parts.Add(('{0} регуляторов' -f $sliderCount))
        if ($buttonCount -gt 0) { $parts.Add(('{0} кнопок' -f $buttonCount)) }
        if ($toggleCount -gt 0) { $parts.Add(('{0} тумблеров' -f $toggleCount)) }
        if ($encoderCount -gt 0) { $parts.Add(('{0} энкодеров' -f $encoderCount)) }
        return ('Контроллер подключён — {0} · {1}' -f $PortName, ($parts -join ' · '))
    }

    $parts = New-Object 'System.Collections.Generic.List[string]'
    $parts.Add(('{0} controls' -f $sliderCount))
    if ($buttonCount -gt 0) { $parts.Add(('{0} buttons' -f $buttonCount)) }
    if ($toggleCount -gt 0) { $parts.Add(('{0} toggles' -f $toggleCount)) }
    if ($encoderCount -gt 0) { $parts.Add(('{0} encoders' -f $encoderCount)) }
    return ('Controller connected — {0} · {1}' -f $PortName, ($parts -join ' · '))
}

function Set-DetectedControllerCapabilities {
'@

$text = Replace-RegexBlockExactlyOnceLiteral `
    -Text $text `
    -Pattern '(?ms)^function Get-ControllerConnectedStatusText \{.*?^function Set-DetectedControllerCapabilities \{' `
    -Replacement $typedHelpersAndStatus `
    -Label 'typed control helpers and status text'

$oldCapabilityCounts = @'
    $sliderCount = @($Packet.Sliders).Count
    $buttonCount = @($Packet.Buttons).Count

    $changed = (
        $script:ControllerProtocol -ne $protocol -or
        $script:DetectedSliderCount -ne $sliderCount -or
        $script:DetectedButtonCount -ne $buttonCount
    )
'@

$newCapabilityCounts = @'
    $sliderCount = @($Packet.Sliders).Count
    $buttonCount = @($Packet.Buttons).Count
    $toggleCount = @(Get-ControllerPacketArray -Packet $Packet -Name 'Toggles').Count
    $encoderCount = @(Get-ControllerPacketArray -Packet $Packet -Name 'Encoders').Count

    $changed = (
        $script:ControllerProtocol -ne $protocol -or
        $script:DetectedSliderCount -ne $sliderCount -or
        $script:DetectedButtonCount -ne $buttonCount -or
        $script:DetectedToggleCount -ne $toggleCount -or
        $script:DetectedEncoderCount -ne $encoderCount
    )
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldCapabilityCounts `
    -NewText $newCapabilityCounts `
    -Label 'typed capability counts'

$oldCapabilityAssignments = @'
    $script:ControllerProtocol = $protocol
    $script:DetectedSliderCount = $sliderCount
    $script:DetectedButtonCount = $buttonCount
    $script:SoftMutedSliders = @{}
'@

$newCapabilityAssignments = @'
    $script:ControllerProtocol = $protocol
    $script:DetectedSliderCount = $sliderCount
    $script:DetectedButtonCount = $buttonCount
    $script:DetectedToggleCount = $toggleCount
    $script:DetectedEncoderCount = $encoderCount
    $script:SoftMutedSliders = @{}
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldCapabilityAssignments `
    -NewText $newCapabilityAssignments `
    -Label 'typed capability assignments'

$oldCapabilityLog = @'
        Write-Log (
            'Controller capabilities detected: port={0}; protocol={1}; sliders={2}; buttons={3}' -f
            $PortName, $protocol, $sliderCount, $buttonCount
        ) 'INFO'
'@

$newCapabilityLog = @'
        Write-Log (
            'Controller capabilities detected: port={0}; protocol={1}; sliders={2}; buttons={3}; toggles={4}; encoders={5}' -f
            $PortName, $protocol, $sliderCount, $buttonCount, $toggleCount, $encoderCount
        ) 'INFO'
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldCapabilityLog `
    -NewText $newCapabilityLog `
    -Label 'typed capability log'

# Capability matching must include all Adaptive typed controls. Legacy and
# Extended packets simply report zero optional typed arrays through the helper.
$oldCapabilityMatch = @'
    return (
        [string]$Packet.Protocol -eq $script:ControllerProtocol -and
        @($Packet.Sliders).Count -eq $script:DetectedSliderCount -and
        @($Packet.Buttons).Count -eq $script:DetectedButtonCount
    )
'@

$newCapabilityMatch = @'
    return (
        [string]$Packet.Protocol -eq $script:ControllerProtocol -and
        @($Packet.Sliders).Count -eq $script:DetectedSliderCount -and
        @($Packet.Buttons).Count -eq $script:DetectedButtonCount -and
        @(Get-ControllerPacketArray -Packet $Packet -Name 'Toggles').Count -eq $script:DetectedToggleCount -and
        @(Get-ControllerPacketArray -Packet $Packet -Name 'Encoders').Count -eq $script:DetectedEncoderCount
    )
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldCapabilityMatch `
    -NewText $newCapabilityMatch `
    -Label 'typed capability matching'

# Initialize typed state from the same packet that wins serial probing.
$oldProbeInit = @'
                        Set-DetectedControllerCapabilities -Packet $parsed -PortName $PortName
                        Initialize-ButtonStates -Values @($parsed.Buttons)
'@

$newProbeInit = @'
                        Set-DetectedControllerCapabilities -Packet $parsed -PortName $PortName
                        Initialize-ButtonStates -Values @($parsed.Buttons)
                        Initialize-AdaptiveControlStates -Packet $parsed
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldProbeInit `
    -NewText $newProbeInit `
    -Label 'typed state probe initialization'

# Adaptive and Extended packets are explicitly typed, so two repeated packet
# signatures are sufficient during a baud probe. Legacy remains supported, but
# a short-lived numeric fragment must not win the probe before a typed packet
# has a chance to arrive. Track how long the current candidate signature has
# remained stable and give Legacy candidates a small confidence delay.
$oldProbeCandidateInit = @'
            $buffer = ''
            $candidateSignature = ''
            $candidateHits = 0
'@

$newProbeCandidateInit = @'
            $buffer = ''
            $candidateSignature = ''
            $candidateHits = 0
            $candidateFirstSeenAt = [DateTime]::MinValue
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldProbeCandidateInit `
    -NewText $newProbeCandidateInit `
    -Label 'probe candidate stability timestamp'

$oldProbeSignatureTracking = @'
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
'@

$newProbeSignatureTracking = @'
                        if ($signature -eq $candidateSignature) {
                            $candidateHits++
                        }
                        else {
                            $candidateSignature = $signature
                            $candidateHits = 1
                            $candidateFirstSeenAt = Get-Date
                        }

                        # Explicitly typed packets are high-confidence and can win
                        # quickly. Legacy is intentionally held a little longer:
                        # opening/resetting a USB-serial device can expose a short
                        # numeric fragment that otherwise looks like a 1-slider
                        # classic deej packet. A topology that also disagrees with
                        # the configured slider count receives the longer grace.
                        $requiredHits = if ([string]$parsed.Protocol -in @('extended','adaptive')) { 2 } else { 3 }
                        if ($candidateHits -lt $requiredHits) { continue }

                        if ([string]$parsed.Protocol -eq 'legacy') {
                            $legacyObservedSliders = @($parsed.Sliders).Count
                            $legacyExpectedSliders = [Math]::Max(1, [int]$script:Config.connection.expectedSliders)
                            $legacyStableMs = ((Get-Date) - $candidateFirstSeenAt).TotalMilliseconds
                            $legacyMinStableMs = if ($legacyObservedSliders -eq $legacyExpectedSliders) { 300 } else { 900 }

                            if ($legacyStableMs -lt $legacyMinStableMs) {
                                if ($candidateHits -eq $requiredHits) {
                                    Write-Log (
                                        'Legacy probe candidate deferred: port={0}; baud={1}; observedSliders={2}; expectedSliders={3}; requireStableMs={4}' -f
                                        $PortName,
                                        $baudRate,
                                        $legacyObservedSliders,
                                        $legacyExpectedSliders,
                                        $legacyMinStableMs
                                    ) 'DEBUG'
                                }
                                continue
                            }
                        }
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldProbeSignatureTracking `
    -NewText $newProbeSignatureTracking `
    -Label 'Legacy probe confidence delay'

# Update typed state on every accepted packet. Button handling remains exactly
# where it already was so Extended/XInput behavior is not reordered.
$oldLiveUpdate = @'
                    Update-ButtonStates -Values @($parsed.Buttons)
                    $latestParsed = $parsed
'@

$newLiveUpdate = @'
                    Update-ButtonStates -Values @($parsed.Buttons)
                    Update-AdaptiveControlStates -Packet $parsed
                    $latestParsed = $parsed
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldLiveUpdate `
    -NewText $newLiveUpdate `
    -Label 'typed live-state update'

# Reset typed state alongside the existing protocol/button state when the COM
# port closes.
$oldCloseReset = @'
    $script:ControllerProtocol = 'unknown'
    $script:DetectedSliderCount = 0
    $script:DetectedButtonCount = 0
    $script:LatestButtons = @()
'@

$newCloseReset = @'
    $script:ControllerProtocol = 'unknown'
    $script:DetectedSliderCount = 0
    $script:DetectedButtonCount = 0
    $script:DetectedToggleCount = 0
    $script:DetectedEncoderCount = 0
    $script:LatestButtons = @()
    $script:LatestToggles = @()
    $script:LatestEncoders = @()
    $script:LastEncoderPositions = @()
    $script:AdaptiveDebounceDiagnostics = $null
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldCloseReset `
    -NewText $newCloseReset `
    -Label 'typed state close reset'

$oldMismatchLog = @'
                        Write-Log (
                            'Ignored packet whose shape changed while connected: expected={0}:{1}:{2}; got={3}' -f
                            $script:ControllerProtocol,
                            $script:DetectedSliderCount,
                            $script:DetectedButtonCount,
                            (Get-ControllerPacketSignature -Packet $parsed)
                        ) 'WARN'
'@

$newMismatchLog = @'
                        Write-Log (
                            'Ignored packet whose shape changed while connected: expected={0}:{1}:{2}:{3}:{4}; got={5}' -f
                            $script:ControllerProtocol,
                            $script:DetectedSliderCount,
                            $script:DetectedButtonCount,
                            $script:DetectedToggleCount,
                            $script:DetectedEncoderCount,
                            (Get-ControllerPacketSignature -Packet $parsed)
                        ) 'WARN'
'@

$text = Replace-LiteralExactlyOnce `
    -Text $text `
    -OldText $oldMismatchLog `
    -NewText $newMismatchLog `
    -Label 'typed capability mismatch log'

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($resolved, $text, $utf8)
Write-Host "Applied staged Adaptive v3 self-describing protocol support: $resolved"