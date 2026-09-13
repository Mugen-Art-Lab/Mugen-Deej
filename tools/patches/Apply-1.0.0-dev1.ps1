param(
    [Parameter(Mandatory = $true)][string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "MugenDeej.ps1 was not found: $Path"
}

$text = [System.IO.File]::ReadAllText($Path)

function Replace-ExactOnce {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][string]$New,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $first = $Text.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($first -lt 0) {
        throw "Patch marker was not found: $Label"
    }

    $second = $Text.IndexOf($Old, $first + $Old.Length, [System.StringComparison]::Ordinal)
    if ($second -ge 0) {
        throw "Patch marker is not unique: $Label"
    }

    return $Text.Substring(0, $first) + $New + $Text.Substring($first + $Old.Length)
}

$text = Replace-ExactOnce -Text $text -Old '# Mugen Deej 0.9.0-dev25' -New '# Mugen Deej 1.0.0-dev1' -Label 'header version'
$oldAppVersion = '$script:AppVersion = ''0.9.0-dev25'''
$newAppVersion = '$script:AppVersion = ''1.0.0-dev1'''
$text = Replace-ExactOnce -Text $text -Old $oldAppVersion -New $newAppVersion -Label 'runtime version'

$oldPathLine = '$script:ButtonActionConfigPath = Join-Path $script:BaseDir ''button-actions.dev.json'''
$newPathLines = @'
$script:ButtonActionConfigPath = Join-Path $script:BaseDir 'button-actions.json'
$script:LegacyButtonActionConfigPath = Join-Path $script:BaseDir 'button-actions.dev.json'
'@
$newPathLines = $newPathLines.TrimEnd()
$text = Replace-ExactOnce -Text $text -Old $oldPathLine -New $newPathLines -Label 'button action config path'

$initializePattern = '(?s)function Initialize-ButtonActions \{.*?\r?\n\}\r?\n\r?\nfunction Normalize-ButtonActions \{'
$initializeReplacement = @'
function Read-ButtonActionConfigFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($null -eq $data) {
        throw 'Button action configuration is empty.'
    }
    if ($null -eq $data.PSObject.Properties['version']) {
        throw 'Button action configuration has no schema version.'
    }
    if ([int]$data.version -ne 1) {
        throw ('Unsupported button action configuration version: {0}' -f $data.version)
    }
    if ($null -eq $data.PSObject.Properties['actions']) {
        throw 'Button action configuration has no actions array.'
    }

    $actions = @()
    foreach ($item in @($data.actions)) {
        if ($null -eq $item) {
            throw 'Button action configuration contains a null action.'
        }
        $actions += [string]$item
    }

    return [pscustomobject]@{
        version = 1
        actions = @($actions)
    }
}

function Write-ButtonActionConfigFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Actions
    )

    $tempPath = "$Path.tmp-$PID"

    try {
        $payload = [pscustomobject]@{
            version = 1
            actions = @($Actions | ForEach-Object { [string]$_ })
        }

        $json = $payload | ConvertTo-Json -Depth 4
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tempPath, $json, $utf8NoBom)

        $verified = Read-ButtonActionConfigFile -Path $tempPath
        $expected = @($payload.actions)
        $actual = @($verified.actions)

        if ($actual.Count -ne $expected.Count) {
            throw 'Button action configuration failed action-count verification.'
        }

        for ($i = 0; $i -lt $expected.Count; $i++) {
            if ([string]$actual[$i] -cne [string]$expected[$i]) {
                throw ('Button action configuration failed verification at action {0}.' -f ($i + 1))
            }
        }

        if (Test-Path -LiteralPath $Path) {
            try {
                [System.IO.File]::Replace($tempPath, $Path, $null, $true)
            }
            catch {
                Copy-Item -LiteralPath $tempPath -Destination $Path -Force
                Remove-Item -LiteralPath $tempPath -Force
            }
        }
        else {
            [System.IO.File]::Move($tempPath, $Path)
        }

        [void](Read-ButtonActionConfigFile -Path $Path)
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Try-MigrateLegacyButtonActionConfig {
    if (Test-Path -LiteralPath $script:ButtonActionConfigPath) { return $false }
    if (-not (Test-Path -LiteralPath $script:LegacyButtonActionConfigPath)) { return $false }

    try {
        $legacy = Read-ButtonActionConfigFile -Path $script:LegacyButtonActionConfigPath
        Write-ButtonActionConfigFile -Path $script:ButtonActionConfigPath -Actions @($legacy.actions)

        Write-Log (
            'Button action config migrated safely: {0} -> {1}; actions={2}; legacy file preserved' -f
            [System.IO.Path]::GetFileName($script:LegacyButtonActionConfigPath),
            [System.IO.Path]::GetFileName($script:ButtonActionConfigPath),
            @($legacy.actions).Count
        ) 'INFO'

        return $true
    }
    catch {
        Write-Log (
            'Button action config migration failed; legacy file was left untouched: {0}' -f
            $_.Exception.Message
        ) 'WARN'
        return $false
    }
}

function Initialize-ButtonActions {
    if ($script:ButtonActionsLoaded) { return }

    $script:ButtonActionsLoaded = $true
    $script:ButtonActions = @()

    [void](Try-MigrateLegacyButtonActionConfig)

    $loadPath = ''
    if (Test-Path -LiteralPath $script:ButtonActionConfigPath) {
        $loadPath = $script:ButtonActionConfigPath
    }
    elseif (Test-Path -LiteralPath $script:LegacyButtonActionConfigPath) {
        # A migration can fail because the folder is temporarily unwritable.
        # Keep the user's existing button mappings active without modifying the
        # legacy file; the migration will be attempted again on the next run.
        $loadPath = $script:LegacyButtonActionConfigPath
    }
    else {
        return
    }

    try {
        $data = Read-ButtonActionConfigFile -Path $loadPath
        $script:ButtonActions = @($data.actions | ForEach-Object { [string]$_ })

        Write-Log (
            'Button action config loaded: file={0}; actions={1}' -f
            [System.IO.Path]::GetFileName($loadPath),
            @($script:ButtonActions).Count
        ) 'DEBUG'
    }
    catch {
        Write-Log (
            'Failed to load button action config {0}: {1}' -f
            [System.IO.Path]::GetFileName($loadPath),
            $_.Exception.Message
        ) 'WARN'
        $script:ButtonActions = @()
    }
}

function Normalize-ButtonActions {
'@

$match = [regex]::Matches($text, $initializePattern)
if ($match.Count -ne 1) {
    throw "Expected exactly one Initialize-ButtonActions block, found $($match.Count)."
}
$text = [regex]::Replace($text, $initializePattern, $initializeReplacement, 1)

$savePattern = '(?s)function Save-ButtonActions \{.*?\r?\n\}\r?\n\r?\nfunction Get-MuteStatusColor \{'
$saveReplacement = @'
function Save-ButtonActions {
    Write-ButtonActionConfigFile `
        -Path $script:ButtonActionConfigPath `
        -Actions @($script:ButtonActions)

    Write-Log (
        'Button actions saved to {0}: {1}' -f
        [System.IO.Path]::GetFileName($script:ButtonActionConfigPath),
        (@($script:ButtonActions) -join ',')
    ) 'INFO'
}

function Get-MuteStatusColor {
'@

$match = [regex]::Matches($text, $savePattern)
if ($match.Count -ne 1) {
    throw "Expected exactly one Save-ButtonActions block, found $($match.Count)."
}
$text = [regex]::Replace($text, $savePattern, $saveReplacement, 1)

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($Path, $text, $utf8Bom)

Write-Host 'Applied Mugen Deej 1.0.0-dev1 button-action migration patch.'
