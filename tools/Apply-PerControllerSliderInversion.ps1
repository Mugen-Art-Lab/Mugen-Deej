param(
    [Parameter(Mandatory = $true)][string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$resolved = (Resolve-Path -LiteralPath $Path).Path
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$text = [System.IO.File]::ReadAllText($resolved, $utf8)
$hadBom = $false
$bytes = [System.IO.File]::ReadAllBytes($resolved)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $hadBom = $true
}

function Replace-Once {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][string]$New,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $first = $Source.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Patch anchor not found: $Label" }
    $second = $Source.IndexOf($Old, $first + $Old.Length, [System.StringComparison]::Ordinal)
    if ($second -ge 0) { throw "Patch anchor is ambiguous: $Label" }
    return $Source.Substring(0, $first) + $New + $Source.Substring($first + $Old.Length)
}

$text = Replace-Once -Source $text -Label 'default inversion config' -Old @'
        behavior = [ordered]@{
            invertSliders = $false
            noiseThreshold = 0.007
        }
'@ -New @'
        behavior = [ordered]@{
            invertSliders = $false
            invertSlidersByController = [ordered]@{}
            noiseThreshold = 0.007
        }
'@

$text = Replace-Once -Source $text -Label 'config-shape inversion map' -Old @'
    Add-MissingConfigProperty -Object $Config.behavior -Name 'invertSliders' -Value $false
    Add-MissingConfigProperty -Object $Config.behavior -Name 'noiseThreshold' -Value 0.007
'@ -New @'
    Add-MissingConfigProperty -Object $Config.behavior -Name 'invertSliders' -Value $false
    Add-MissingConfigProperty -Object $Config.behavior -Name 'invertSlidersByController' -Value ([pscustomobject]@{})
    Add-MissingConfigProperty -Object $Config.behavior -Name 'noiseThreshold' -Value 0.007
'@

$text = Replace-Once -Source $text -Label 'controller signature helpers' -Old @'
function Test-ControllerProtocolLine {
'@ -New @'
function Get-CurrentControllerSignature {
    if ([string]$script:ControllerProtocol -eq 'unknown') { return '' }

    return ('{0}:{1}:{2}:{3}:{4}' -f
        [string]$script:ControllerProtocol,
        [int]$script:DetectedSliderCount,
        [int]$script:DetectedButtonCount,
        [int]$script:DetectedToggleCount,
        [int]$script:DetectedEncoderCount
    )
}

function Get-SliderInversionProfileStore {
    $property = $script:Config.behavior.PSObject.Properties['invertSlidersByController']
    if ($null -eq $property -or $null -eq $property.Value) {
        $store = [pscustomobject]@{}
        if ($null -eq $property) {
            $script:Config.behavior | Add-Member -MemberType NoteProperty -Name 'invertSlidersByController' -Value $store
        }
        else {
            $property.Value = $store
        }
        return $store
    }
    return $property.Value
}

function Get-EffectiveSliderInversion {
    param([string]$Signature = '')

    if ([string]::IsNullOrWhiteSpace($Signature)) {
        $Signature = Get-CurrentControllerSignature
    }

    $store = Get-SliderInversionProfileStore
    if (-not [string]::IsNullOrWhiteSpace($Signature)) {
        $entry = $store.PSObject.Properties[$Signature]
        if ($null -ne $entry) {
            return [bool]$entry.Value
        }
    }

    # An empty profile store means this configuration predates per-controller
    # inversion. Preserve the old global setting until the first controller is
    # detected and migrated. After that, unseen controller signatures default
    # to normal direction instead of inheriting another device's wiring.
    if (@($store.PSObject.Properties).Count -eq 0) {
        return [bool]$script:Config.behavior.invertSliders
    }
    return $false
}

function Set-SliderInversionForController {
    param(
        [Parameter(Mandatory = $true)][string]$Signature,
        [Parameter(Mandatory = $true)][bool]$Invert
    )

    $store = Get-SliderInversionProfileStore
    $entry = $store.PSObject.Properties[$Signature]
    if ($null -eq $entry) {
        $store | Add-Member -MemberType NoteProperty -Name $Signature -Value $Invert
    }
    else {
        $entry.Value = $Invert
    }
}

function Initialize-SliderInversionProfileForCurrentController {
    $signature = Get-CurrentControllerSignature
    if ([string]::IsNullOrWhiteSpace($signature)) { return }

    $store = Get-SliderInversionProfileStore
    if (@($store.PSObject.Properties).Count -ne 0) { return }

    $legacyValue = [bool]$script:Config.behavior.invertSliders
    Set-SliderInversionForController -Signature $signature -Invert $legacyValue
    Save-Config -Config $script:Config
    Write-Log ('Migrated global slider inversion to controller profile: signature={0}; invert={1}' -f $signature, $legacyValue) 'INFO'
}

function Test-ControllerProtocolLine {
'@

$text = Replace-Once -Source $text -Label 'slider settings checkbox' -Old @'
    $invertCheck.Checked = [bool]$script:Config.behavior.invertSliders
'@ -New @'
    $invertCheck.Checked = [bool](Get-EffectiveSliderInversion)
'@

$text = Replace-Once -Source $text -Label 'slider settings save' -Old @'
        $script:Config.behavior.invertSliders = [bool]$invertMatches[0].Checked
'@ -New @'
        $selectedInvert = [bool]$invertMatches[0].Checked
        $controllerSignature = Get-CurrentControllerSignature
        if ([string]::IsNullOrWhiteSpace($controllerSignature)) {
            # Keep the legacy global setting as a disconnected fallback. Once a
            # controller is present, settings are stored against its topology.
            $script:Config.behavior.invertSliders = $selectedInvert
        }
        else {
            Set-SliderInversionForController -Signature $controllerSignature -Invert $selectedInvert
            Write-Log ('Slider inversion saved for controller: signature={0}; invert={1}' -f $controllerSignature, $selectedInvert) 'INFO'
        }
'@

$text = Replace-Once -Source $text -Label 'capability inversion migration' -Old @'
    Update-ButtonFeatureUi

    if ($changed) {
'@ -New @'
    Update-ButtonFeatureUi
    Initialize-SliderInversionProfileForCurrentController

    if ($changed) {
'@

$text = Replace-Once -Source $text -Label 'runtime slider inversion' -Old @'
    $invert = [bool]$script:Config.behavior.invertSliders
'@ -New @'
    $invert = [bool](Get-EffectiveSliderInversion)
'@

if ($text -notmatch 'invertSlidersByController') { throw 'Per-controller inversion config was not inserted.' }
if ($text -notmatch 'Migrated global slider inversion to controller profile') { throw 'Per-controller inversion migration was not inserted.' }
if ($text -notmatch 'Slider inversion saved for controller') { throw 'Per-controller inversion save path was not inserted.' }

$writerEncoding = New-Object System.Text.UTF8Encoding($hadBom)
[System.IO.File]::WriteAllText($resolved, $text, $writerEncoding)
Write-Host "Applied per-controller slider inversion profiles to $resolved"
