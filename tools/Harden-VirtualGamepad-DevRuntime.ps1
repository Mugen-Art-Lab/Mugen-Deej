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

$firstNormalize = $text.IndexOf($oldNormalizeBlock, [System.StringComparison]::Ordinal)
$lastNormalize = $text.LastIndexOf($oldNormalizeBlock, [System.StringComparison]::Ordinal)
if ($firstNormalize -lt 0 -or $firstNormalize -ne $lastNormalize) {
    throw "Dev runtime hardening 'preserve virtual button mappings' expected exactly one literal match."
}
$text = $text.Replace($oldNormalizeBlock, $newNormalizeBlock)

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($resolved, $text, $utf8)
Write-Host "Hardened development runtime against Windows startup registration changes and virtual mapping loss: $resolved"
