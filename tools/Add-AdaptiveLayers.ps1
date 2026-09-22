param(
    [Parameter(Mandatory = $true)][string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Replace-LayerLiteralExactlyOnce {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$OldText,
        [Parameter(Mandatory = $true)][string]$NewText,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $first = $Text.IndexOf($OldText, [System.StringComparison]::Ordinal)
    $last = $Text.LastIndexOf($OldText, [System.StringComparison]::Ordinal)
    if ($first -lt 0 -or $first -ne $last) {
        throw "Adaptive layer patch '$Label' expected exactly one literal match."
    }

    return $Text.Substring(0, $first) + $NewText + $Text.Substring($first + $OldText.Length)
}

function Replace-LayerRegexExactlyOnce {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Replacement,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $options = [System.Text.RegularExpressions.RegexOptions]::Multiline -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
    $regex = New-Object System.Text.RegularExpressions.Regex($Pattern, $options)
    $matches = $regex.Matches($Text)
    if ($matches.Count -ne 1) {
        throw "Adaptive layer patch '$Label' expected exactly one regex match, found $($matches.Count)."
    }

    $match = $matches[0]
    return $Text.Substring(0, $match.Index) + $Replacement + $Text.Substring($match.Index + $match.Length)
}

$resolved = (Resolve-Path -LiteralPath $Path).Path
$text = [System.IO.File]::ReadAllText($resolved, [System.Text.Encoding]::UTF8)

# Keep layer configuration completely separate from the established flat
# button-actions.json path. Legacy/Extended therefore retain their exact
# existing action storage and runtime resolution.
$profilePathNeedle = "'adaptive-profiles.json'"
$profilePathIndex = $text.IndexOf($profilePathNeedle, [System.StringComparison]::Ordinal)
if ($profilePathIndex -lt 0) {
    throw 'Adaptive layer patch could not find the adaptive-profiles.json assignment.'
}

$profileLineStart = $text.LastIndexOf("`n", $profilePathIndex)
if ($profileLineStart -lt 0) { $profileLineStart = 0 } else { $profileLineStart++ }
$profileLineEnd = $text.IndexOf("`n", $profilePathIndex)
if ($profileLineEnd -lt 0) { $profileLineEnd = $text.Length }

$profileLine = $text.Substring($profileLineStart, $profileLineEnd - $profileLineStart).TrimEnd("`r")
if ($profileLine -notmatch '^\s*\$script:AdaptiveProfileConfigPath\s*=') {
    throw ("Adaptive layer patch found adaptive-profiles.json on an unexpected line: " + $profileLine)
}

$stateNew = @'
$script:AdaptiveProfileConfigPath = Join-Path $script:BaseDir 'adaptive-profiles.json'
$script:AdaptiveLayerConfigPath = Join-Path $script:BaseDir 'adaptive-layers.json'
$script:AdaptiveLayersLoaded = $false
$script:AdaptiveLayerConfig = $null
'@
$text = $text.Substring(0, $profileLineStart) + $stateNew + $text.Substring($profileLineEnd)

$layerFunctions = @'
function New-DefaultAdaptiveLayerConfig {
    return [pscustomobject][ordered]@{
        version = 1
        modifierToggles = @($false, $false)
        contexts = @()
    }
}

function ConvertTo-SafeAdaptiveLayerButtonOverride {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'inherit') {
        return 'inherit'
    }

    return ConvertTo-SafeProfileButtonAction -Action $Action
}

function ConvertTo-SafeAdaptiveLayerTypedOverride {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'inherit') {
        return 'inherit'
    }

    return ConvertTo-SafeAdaptiveAction -Action $Action
}

function Normalize-AdaptiveLayerContextKey {
    param([string]$Key)

    if ([string]::IsNullOrWhiteSpace($Key) -or $Key -eq '__global__') {
        return '__global__'
    }

    $normalized = Normalize-TargetName -Value $Key
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return '__global__'
    }

    return $normalized.ToLowerInvariant()
}

function ConvertTo-NormalizedAdaptiveLayerConfig {
    param($Data)

    $result = New-DefaultAdaptiveLayerConfig
    if ($null -eq $Data) { return $result }

    if ($null -ne $Data.PSObject.Properties['modifierToggles']) {
        $mods = @($Data.modifierToggles)
        $result.modifierToggles = @(
            $(if ($mods.Count -gt 0) { [bool]$mods[0] } else { $false }),
            $(if ($mods.Count -gt 1) { [bool]$mods[1] } else { $false })
        )
    }

    $seen = @{}
    $contexts = @()
    if ($null -ne $Data.PSObject.Properties['contexts']) {
        foreach ($raw in @($Data.contexts)) {
            if ($null -eq $raw) { continue }

            $key = Normalize-AdaptiveLayerContextKey -Key ([string]$raw.key)
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true

            $context = [pscustomobject][ordered]@{
                key = $key
                t1 = @()
                t2 = @()
                both = @()
                t1Encoders = @()
                t2Encoders = @()
                bothEncoders = @()
            }

            foreach ($layerName in @('t1','t2','both')) {
                $safe = @()
                $property = $raw.PSObject.Properties[$layerName]
                if ($null -ne $property) {
                    foreach ($action in @($property.Value)) {
                        $safe += ConvertTo-SafeAdaptiveLayerButtonOverride -Action ([string]$action)
                    }
                }
                $context.$layerName = @($safe)

                $encoderField = $layerName + 'Encoders'
                $safeEncoders = @()
                $encoderProperty = $raw.PSObject.Properties[$encoderField]
                if ($null -ne $encoderProperty) {
                    foreach ($encoder in @($encoderProperty.Value)) {
                        if ($null -eq $encoder) { continue }
                        $safeEncoders += [pscustomobject][ordered]@{
                            cw = ConvertTo-SafeAdaptiveLayerTypedOverride -Action ([string]$encoder.cw)
                            ccw = ConvertTo-SafeAdaptiveLayerTypedOverride -Action ([string]$encoder.ccw)
                            push = ConvertTo-SafeAdaptiveLayerTypedOverride -Action ([string]$encoder.push)
                        }
                    }
                }
                $context.$encoderField = @($safeEncoders)
            }

            $contexts += $context
        }
    }

    $result.contexts = @($contexts)
    return $result
}

function Read-AdaptiveLayerConfigFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $data) { throw 'Adaptive layer configuration is empty.' }
    if ($null -eq $data.PSObject.Properties['version'] -or [int]$data.version -ne 1) {
        throw 'Unsupported or missing Adaptive layer configuration version.'
    }

    return ConvertTo-NormalizedAdaptiveLayerConfig -Data $data
}

function Write-AdaptiveLayerConfigFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Config
    )

    $safe = ConvertTo-NormalizedAdaptiveLayerConfig -Data $Config
    $tempPath = "$Path.tmp-$PID"

    try {
        $json = $safe | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        $verified = Read-AdaptiveLayerConfigFile -Path $tempPath

        if (@($verified.modifierToggles).Count -ne 2) {
            throw 'Adaptive layer configuration failed modifier verification.'
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

        [void](Read-AdaptiveLayerConfigFile -Path $Path)
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Initialize-AdaptiveLayers {
    if ($script:AdaptiveLayersLoaded) { return }

    $script:AdaptiveLayersLoaded = $true
    $script:AdaptiveLayerConfig = New-DefaultAdaptiveLayerConfig

    if (-not (Test-Path -LiteralPath $script:AdaptiveLayerConfigPath -PathType Leaf)) {
        return
    }

    try {
        $script:AdaptiveLayerConfig = Read-AdaptiveLayerConfigFile -Path $script:AdaptiveLayerConfigPath
        Write-Log (
            'Adaptive layers loaded: modifierToggles={0},{1}; contexts={2}' -f
            [bool]$script:AdaptiveLayerConfig.modifierToggles[0],
            [bool]$script:AdaptiveLayerConfig.modifierToggles[1],
            @($script:AdaptiveLayerConfig.contexts).Count
        ) 'DEBUG'
    }
    catch {
        $script:AdaptiveLayerConfig = New-DefaultAdaptiveLayerConfig
        Write-Log ('Failed to load Adaptive layer config; defaults restored: {0}' -f $_.Exception.Message) 'WARN'
    }
}

function Save-AdaptiveLayers {
    Initialize-AdaptiveLayers
    Write-AdaptiveLayerConfigFile -Path $script:AdaptiveLayerConfigPath -Config $script:AdaptiveLayerConfig
    Write-Log (
        'Adaptive layers saved: modifierToggles={0},{1}; contexts={2}' -f
        [bool]$script:AdaptiveLayerConfig.modifierToggles[0],
        [bool]$script:AdaptiveLayerConfig.modifierToggles[1],
        @($script:AdaptiveLayerConfig.contexts).Count
    ) 'INFO'
}

function Copy-AdaptiveLayerConfig {
    param($Config)

    if ($null -eq $Config) {
        return New-DefaultAdaptiveLayerConfig
    }

    $json = $Config | ConvertTo-Json -Depth 12
    return ConvertTo-NormalizedAdaptiveLayerConfig -Data ($json | ConvertFrom-Json)
}

function Get-AdaptiveLayerContextObject {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$Key = '__global__',
        [switch]$Create
    )

    $normalized = Normalize-AdaptiveLayerContextKey -Key $Key
    foreach ($context in @($Config.contexts)) {
        if ([string]$context.key -eq $normalized) {
            return $context
        }
    }

    if (-not $Create) { return $null }

    $created = [pscustomobject][ordered]@{
        key = $normalized
        t1 = @()
        t2 = @()
        both = @()
        t1Encoders = @()
        t2Encoders = @()
        bothEncoders = @()
    }

    $contexts = @($Config.contexts)
    $contexts += $created
    $Config.contexts = @($contexts)
    return $created
}

function Ensure-AdaptiveLayerContextCapacity {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [int]$ButtonCount
    )

    if ($ButtonCount -lt 0) { $ButtonCount = 0 }

    foreach ($layerName in @('t1','t2','both')) {
        $actions = @($Context.$layerName)
        while ($actions.Count -lt $ButtonCount) {
            $actions += 'inherit'
        }
        $Context.$layerName = @($actions)
    }
}

function Ensure-AdaptiveLayerEncoderCapacity {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [int]$EncoderCount
    )

    if ($EncoderCount -lt 0) { $EncoderCount = 0 }

    foreach ($field in @('t1Encoders','t2Encoders','bothEncoders')) {
        $items = @($Context.$field)
        while ($items.Count -lt $EncoderCount) {
            $items += [pscustomobject][ordered]@{
                cw = 'inherit'
                ccw = 'inherit'
                push = 'inherit'
            }
        }
        $Context.$field = @($items)
    }
}

function Get-AdaptiveLayerNameForIndex {
    param([int]$Layer)

    switch ($Layer) {
        1 { return 't1' }
        2 { return 't2' }
        3 { return 'both' }
        default { return '' }
    }
}

function Get-AdaptiveLayerDisplayName {
    param([int]$Layer)

    if ($script:Language -eq 'ru') {
        switch ($Layer) {
            1 { return 'T1' }
            2 { return 'T2' }
            3 { return 'T1 + T2' }
            default { return 'Основной' }
        }
    }

    switch ($Layer) {
        1 { return 'T1' }
        2 { return 'T2' }
        3 { return 'T1 + T2' }
        default { return 'Base' }
    }
}

function Get-AdaptiveLayerIndexFromValues {
    param([object[]]$Values)

    # Hard compatibility gate: Legacy and Extended do not participate in
    # toggle layers and retain their established flat button mappings.
    if ([string]$script:ControllerProtocol -ne 'adaptive') { return 0 }

    Initialize-AdaptiveLayers
    $mods = @($script:AdaptiveLayerConfig.modifierToggles)
    $valuesArray = @($Values)
    $layer = 0

    if (
        $mods.Count -gt 0 -and
        [bool]$mods[0] -and
        $valuesArray.Count -gt 0 -and
        [int]$valuesArray[0] -eq 1
    ) {
        $layer = $layer -bor 1
    }

    if (
        $mods.Count -gt 1 -and
        [bool]$mods[1] -and
        $valuesArray.Count -gt 1 -and
        [int]$valuesArray[1] -eq 1
    ) {
        $layer = $layer -bor 2
    }

    return [int]$layer
}

function Get-AdaptiveLayerIndex {
    return Get-AdaptiveLayerIndexFromValues -Values @($script:LatestToggles)
}

function Test-AdaptiveLayersEnabled {
    if ([string]$script:ControllerProtocol -ne 'adaptive') { return $false }

    Initialize-AdaptiveLayers
    $mods = @($script:AdaptiveLayerConfig.modifierToggles)
    return (
        ($mods.Count -gt 0 -and [bool]$mods[0] -and [int]$script:DetectedToggleCount -gt 0) -or
        ($mods.Count -gt 1 -and [bool]$mods[1] -and [int]$script:DetectedToggleCount -gt 1)
    )
}

function Test-AdaptiveToggleIsLayerModifier {
    param([int]$Index)

    if ([string]$script:ControllerProtocol -ne 'adaptive') { return $false }
    if ($Index -lt 0 -or $Index -gt 1) { return $false }

    Initialize-AdaptiveLayers
    $mods = @($script:AdaptiveLayerConfig.modifierToggles)
    return (
        $mods.Count -gt $Index -and
        [bool]$mods[$Index] -and
        [int]$script:DetectedToggleCount -gt $Index
    )
}

function Get-AdaptiveLayerButtonOverride {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$ContextKey,
        [int]$Layer,
        [int]$ButtonIndex
    )

    if ($Layer -le 0 -or $ButtonIndex -lt 0) { return 'inherit' }

    $context = Get-AdaptiveLayerContextObject -Config $Config -Key $ContextKey
    if ($null -eq $context) { return 'inherit' }

    $layerName = Get-AdaptiveLayerNameForIndex -Layer $Layer
    if ([string]::IsNullOrWhiteSpace($layerName)) { return 'inherit' }

    $actions = @($context.$layerName)
    if ($ButtonIndex -ge $actions.Count) { return 'inherit' }

    return ConvertTo-SafeAdaptiveLayerButtonOverride -Action ([string]$actions[$ButtonIndex])
}

function Set-AdaptiveLayerButtonOverride {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$ContextKey,
        [int]$Layer,
        [int]$ButtonIndex,
        [string]$Action,
        [int]$ButtonCount
    )

    if ($Layer -le 0 -or $ButtonIndex -lt 0) { return }

    $context = Get-AdaptiveLayerContextObject -Config $Config -Key $ContextKey -Create
    Ensure-AdaptiveLayerContextCapacity -Context $context -ButtonCount $ButtonCount

    $layerName = Get-AdaptiveLayerNameForIndex -Layer $Layer
    if ([string]::IsNullOrWhiteSpace($layerName)) { return }

    $actions = @($context.$layerName)
    $actions[$ButtonIndex] = ConvertTo-SafeAdaptiveLayerButtonOverride -Action $Action
    $context.$layerName = @($actions)
}

function Get-AdaptiveLayerEncoderFieldName {
    param([int]$Layer)

    switch ($Layer) {
        1 { return 't1Encoders' }
        2 { return 't2Encoders' }
        3 { return 'bothEncoders' }
        default { return '' }
    }
}

function Get-AdaptiveLayerEncoderOverride {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$ContextKey,
        [int]$Layer,
        [int]$EncoderIndex,
        [ValidateSet('cw','ccw','push')][string]$Kind
    )

    if ($Layer -le 0 -or $EncoderIndex -lt 0) { return 'inherit' }

    $context = Get-AdaptiveLayerContextObject -Config $Config -Key $ContextKey
    if ($null -eq $context) { return 'inherit' }

    $field = Get-AdaptiveLayerEncoderFieldName -Layer $Layer
    if ([string]::IsNullOrWhiteSpace($field)) { return 'inherit' }

    $items = @($context.$field)
    if ($EncoderIndex -ge $items.Count) { return 'inherit' }

    return ConvertTo-SafeAdaptiveLayerTypedOverride -Action ([string]$items[$EncoderIndex].$Kind)
}

function Set-AdaptiveLayerEncoderOverride {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$ContextKey,
        [int]$Layer,
        [int]$EncoderIndex,
        [ValidateSet('cw','ccw','push')][string]$Kind,
        [string]$Action,
        [int]$EncoderCount
    )

    if ($Layer -le 0 -or $EncoderIndex -lt 0) { return }

    $context = Get-AdaptiveLayerContextObject -Config $Config -Key $ContextKey -Create
    Ensure-AdaptiveLayerEncoderCapacity -Context $context -EncoderCount $EncoderCount

    $field = Get-AdaptiveLayerEncoderFieldName -Layer $Layer
    if ([string]::IsNullOrWhiteSpace($field)) { return }

    $items = @($context.$field)
    $items[$EncoderIndex].$Kind = ConvertTo-SafeAdaptiveLayerTypedOverride -Action $Action
    $context.$field = @($items)
}

function Get-AdaptiveLayerBaseEncoderAction {
    param(
        [string]$ContextKey,
        [int]$EncoderIndex,
        [ValidateSet('cw','ccw','push')][string]$Kind
    )

    Initialize-AdaptiveActions
    Initialize-AdaptiveProfiles

    if ($EncoderIndex -lt 0) { return 'none' }

    $key = Normalize-AdaptiveLayerContextKey -Key $ContextKey
    $source = @($script:AdaptiveEncoderActions)

    if ($key -ne '__global__') {
        foreach ($profile in @($script:AdaptiveProfiles)) {
            $processName = Normalize-TargetName -Value ([string]$profile.process)
            if ([string]::IsNullOrWhiteSpace($processName)) { continue }
            if ($processName.ToLowerInvariant() -ne $key) { continue }

            $profileEncoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
            if ($profileEncoders.Count -gt 0) {
                $source = @($profileEncoders)
            }
            break
        }
    }

    if ($EncoderIndex -ge $source.Count) { return 'none' }
    return ConvertTo-SafeAdaptiveAction -Action ([string]$source[$EncoderIndex].$Kind)
}

function Populate-AdaptiveLayerTypedActionCombo {
    param(
        [Parameter(Mandatory = $true)]$Combo,
        [Parameter(Mandatory = $true)]$Map,
        [string]$CurrentAction = 'inherit'
    )

    $safe = ConvertTo-SafeAdaptiveLayerTypedOverride -Action $CurrentAction
    Populate-AdaptiveActionCombo -Combo $Combo -Map $Map -CurrentAction $(if ($safe -eq 'inherit') { 'none' } else { $safe })

    $inheritText = if ($script:Language -eq 'ru') { 'Наследовать основное действие' } else { 'Inherit base action' }
    $Combo.Items.Insert(0, $inheritText)
    $Map.Insert(0, 'inherit')

    if ($safe -eq 'inherit') {
        $Combo.SelectedIndex = 0
        return
    }

    for ($i = 0; $i -lt $Map.Count; $i++) {
        if ([string]$Map[$i] -eq $safe) {
            $Combo.SelectedIndex = $i
            break
        }
    }
}

function Show-AdaptiveLayerEncoderSettings {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [System.Windows.Forms.IWin32Window]$Owner
    )

    if (
        [string]$script:ControllerProtocol -ne 'adaptive' -or
        [int]$script:DetectedEncoderCount -le 0
    ) {
        return
    }

    Initialize-AdaptiveActions
    Initialize-AdaptiveProfiles

    $encoderLayerWorking = Copy-AdaptiveLayerConfig -Config $Config
    $encoderCount = [int]$script:DetectedEncoderCount

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = if ($script:Language -eq 'ru') { 'Энкодеры в слоях — Mugen Deej' } else { 'Layered encoders — Mugen Deej' }
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.ClientSize = [System.Drawing.Size]::new(720, 462)
    $dialog.MinimumSize = [System.Drawing.Size]::new(736, 501)
    $dialog.MaximumSize = [System.Drawing.Size]::new(736, 501)
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.Font = $form.Font
    Set-FormAppIcon -Form $dialog

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = if ($script:Language -eq 'ru') { 'Энкодер в слоях' } else { 'Encoder layer mappings' }
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $dialog.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = if ($script:Language -eq 'ru') {
        'Для каждого слоя можно отдельно задать вращение и нажатие. «Наследовать» оставляет обычное назначение энкодера из выбранного профиля.'
    }
    else {
        'Each layer can override rotation and push separately. Inherit keeps the normal encoder mapping from the selected profile.'
    }
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = [System.Drawing.Point]::new(25, 56)
    $hint.Size = [System.Drawing.Size]::new(670, 44)
    $dialog.Controls.Add($hint)

    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = if ($script:Language -eq 'ru') { 'Профиль:' } else { 'Profile:' }
    $profileLabel.Location = [System.Drawing.Point]::new(25, 111)
    $profileLabel.Size = [System.Drawing.Size]::new(80, 28)
    $profileLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $dialog.Controls.Add($profileLabel)

    $profileCombo = New-Object MugenDeejWindowing.MugenComboBox
    $profileCombo.DropDownStyle = 'DropDownList'
    $profileCombo.Location = [System.Drawing.Point]::new(105, 109)
    $profileCombo.Size = [System.Drawing.Size]::new(300, 30)
    $dialog.Controls.Add($profileCombo)

    $profileMap = New-Object System.Collections.ArrayList
    [void]$profileCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Общий' } else { 'Global' }))
    [void]$profileMap.Add('__global__')
    foreach ($profile in @($script:AdaptiveProfiles | Sort-Object name)) {
        $processName = Normalize-TargetName -Value ([string]$profile.process)
        if ([string]::IsNullOrWhiteSpace($processName)) { continue }
        [void]$profileCombo.Items.Add(('{0} ({1}.exe)' -f [string]$profile.name, $processName))
        [void]$profileMap.Add($processName.ToLowerInvariant())
    }
    $profileCombo.SelectedIndex = 0

    $layerCombo = New-Object MugenDeejWindowing.MugenComboBox
    $layerCombo.DropDownStyle = 'DropDownList'
    $layerCombo.Location = [System.Drawing.Point]::new(420, 109)
    $layerCombo.Size = [System.Drawing.Size]::new(130, 30)
    [void]$layerCombo.Items.Add('T1')
    [void]$layerCombo.Items.Add('T2')
    [void]$layerCombo.Items.Add('T1 + T2')
    $layerCombo.SelectedIndex = 0
    $dialog.Controls.Add($layerCombo)

    $encoderCombo = New-Object MugenDeejWindowing.MugenComboBox
    $encoderCombo.DropDownStyle = 'DropDownList'
    $encoderCombo.Location = [System.Drawing.Point]::new(565, 109)
    $encoderCombo.Size = [System.Drawing.Size]::new(130, 30)
    for ($i = 0; $i -lt $encoderCount; $i++) {
        [void]$encoderCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Энкодер ' + ($i + 1) } else { 'Encoder ' + ($i + 1) }))
    }
    $encoderCombo.SelectedIndex = 0
    $dialog.Controls.Add($encoderCombo)

    $baseLabel = New-Object System.Windows.Forms.Label
    $baseLabel.ForeColor = [System.Drawing.Color]::DimGray
    $baseLabel.Location = [System.Drawing.Point]::new(25, 154)
    $baseLabel.Size = [System.Drawing.Size]::new(670, 52)
    $dialog.Controls.Add($baseLabel)

    $labels = @()
    $combos = @()
    $maps = @()
    $kinds = @('cw','ccw','push')
    $kindTitlesRu = @('По часовой', 'Против часовой', 'Нажатие')
    $kindTitlesEn = @('Clockwise', 'Counter-clockwise', 'Push')

    for ($i = 0; $i -lt 3; $i++) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $(if ($script:Language -eq 'ru') { $kindTitlesRu[$i] } else { $kindTitlesEn[$i] })
        $label.Location = [System.Drawing.Point]::new(25, (217 + ($i * 58)))
        $label.Size = [System.Drawing.Size]::new(145, 26)
        $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $dialog.Controls.Add($label)
        $labels += $label

        $combo = New-Object MugenDeejWindowing.MugenComboBox
        $combo.Tag = $i
        $combo.DropDownStyle = 'DropDownList'
        $combo.Location = [System.Drawing.Point]::new(175, (215 + ($i * 58)))
        $combo.Size = [System.Drawing.Size]::new(520, 30)
        $dialog.Controls.Add($combo)
        $combos += $combo
        $maps += ,(New-Object System.Collections.ArrayList)
    }

    $state = [pscustomobject]@{ Suppress = $false }

    $getContextKey = {
        $index = [int]$profileCombo.SelectedIndex
        if ($index -lt 0 -or $index -ge $profileMap.Count) { return '__global__' }
        return [string]$profileMap[$index]
    }

    $refresh = {
        $contextKey = & $getContextKey
        $layer = [int]$layerCombo.SelectedIndex + 1
        $encoderIndex = [int]$encoderCombo.SelectedIndex
        if ($encoderIndex -lt 0) { $encoderIndex = 0 }

        $context = Get-AdaptiveLayerContextObject -Config $encoderLayerWorking -Key $contextKey -Create
        Ensure-AdaptiveLayerEncoderCapacity -Context $context -EncoderCount $encoderCount

        $baseCw = Get-AdaptiveLayerBaseEncoderAction -ContextKey $contextKey -EncoderIndex $encoderIndex -Kind 'cw'
        $baseCcw = Get-AdaptiveLayerBaseEncoderAction -ContextKey $contextKey -EncoderIndex $encoderIndex -Kind 'ccw'
        $basePush = Get-AdaptiveLayerBaseEncoderAction -ContextKey $contextKey -EncoderIndex $encoderIndex -Kind 'push'
        $baseLabel.Text = if ($script:Language -eq 'ru') {
            'Основное: ↻ {0} · ↺ {1} · нажатие {2}' -f (Get-AdaptiveActionDisplay -Action $baseCw), (Get-AdaptiveActionDisplay -Action $baseCcw), (Get-AdaptiveActionDisplay -Action $basePush)
        }
        else {
            'Base: ↻ {0} · ↺ {1} · push {2}' -f (Get-AdaptiveActionDisplay -Action $baseCw), (Get-AdaptiveActionDisplay -Action $baseCcw), (Get-AdaptiveActionDisplay -Action $basePush)
        }

        $state.Suppress = $true
        try {
            for ($i = 0; $i -lt 3; $i++) {
                $override = Get-AdaptiveLayerEncoderOverride -Config $encoderLayerWorking -ContextKey $contextKey -Layer $layer -EncoderIndex $encoderIndex -Kind $kinds[$i]
                Populate-AdaptiveLayerTypedActionCombo -Combo $combos[$i] -Map $maps[$i] -CurrentAction $override
            }
        }
        finally {
            $state.Suppress = $false
        }

        $hasPush = $false
        if (@($script:LatestEncoders).Count -gt $encoderIndex) {
            $hasPush = [bool]$script:LatestEncoders[$encoderIndex].HasPush
        }
        $labels[2].Visible = $hasPush
        $combos[2].Visible = $hasPush
    }

    for ($comboIndex = 0; $comboIndex -lt 3; $comboIndex++) {
        $combos[$comboIndex].Add_SelectedIndexChanged({
            param($sender, $eventArgs)

            if ($state.Suppress) { return }

            $slotIndex = [int]$sender.Tag
            $selectedIndex = [int]$sender.SelectedIndex
            if ($slotIndex -lt 0 -or $slotIndex -ge $maps.Count) { return }
            if ($selectedIndex -lt 0 -or $selectedIndex -ge $maps[$slotIndex].Count) { return }

            $contextKey = & $getContextKey
            $layer = [int]$layerCombo.SelectedIndex + 1
            $encoderIndex = [int]$encoderCombo.SelectedIndex
            $kind = [string]$kinds[$slotIndex]
            $chosen = [string]$maps[$slotIndex][$selectedIndex]
            $previous = Get-AdaptiveLayerEncoderOverride -Config $encoderLayerWorking -ContextKey $contextKey -Layer $layer -EncoderIndex $encoderIndex -Kind $kind

            $configured = if ($chosen -eq 'inherit') {
                'inherit'
            }
            else {
                Resolve-AdaptiveConfiguredAction -SelectedAction $chosen -PreviousAction $(if ($previous -eq 'inherit') { 'none' } else { $previous })
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$configured)) {
                Set-AdaptiveLayerEncoderOverride -Config $encoderLayerWorking -ContextKey $contextKey -Layer $layer -EncoderIndex $encoderIndex -Kind $kind -Action ([string]$configured) -EncoderCount $encoderCount
            }

            & $refresh
        })
    }

    $profileCombo.Add_SelectedIndexChanged({ if (-not $state.Suppress) { & $refresh } })
    $layerCombo.Add_SelectedIndexChanged({ if (-not $state.Suppress) { & $refresh } })
    $encoderCombo.Add_SelectedIndexChanged({ if (-not $state.Suppress) { & $refresh } })

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(486, 408)
    $cancel.Size = [System.Drawing.Size]::new(98, 36)
    $dialog.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(596, 408)
    $save.Size = [System.Drawing.Size]::new(99, 36)
    $dialog.Controls.Add($save)

    $save.Add_Click({
        $normalized = ConvertTo-NormalizedAdaptiveLayerConfig -Data $encoderLayerWorking
        $Config.contexts = @($normalized.contexts)
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Close()
    })

    Apply-ThemeToForm -Form $dialog
    & $refresh
    $dialog.AcceptButton = $save
    $dialog.CancelButton = $cancel
    [void]$dialog.ShowDialog($Owner)
    if (-not $dialog.IsDisposed) { $dialog.Dispose() }
}

function Get-AdaptiveLayerProfileKey {
    $profile = Get-ForegroundAdaptiveProfile
    if ($null -eq $profile) { return '__global__' }

    $processName = Normalize-TargetName -Value ([string]$profile.process)
    if ([string]::IsNullOrWhiteSpace($processName)) { return '__global__' }

    return $processName.ToLowerInvariant()
}

function Resolve-AdaptiveLayerButtonContext {
    param([Parameter(Mandatory = $true)]$BaseContext)

    if ([string]$script:ControllerProtocol -ne 'adaptive') {
        return $BaseContext
    }

    $layer = Get-AdaptiveLayerIndex
    if ($layer -le 0 -or -not (Test-AdaptiveLayersEnabled)) {
        return $BaseContext
    }

    Initialize-AdaptiveLayers
    $layerContextKey = Get-AdaptiveLayerProfileKey
    $context = Get-AdaptiveLayerContextObject -Config $script:AdaptiveLayerConfig -Key $layerContextKey

    $baseActions = @($BaseContext.Actions | ForEach-Object { [string]$_ })
    $count = [Math]::Max($baseActions.Count, [int]$script:DetectedButtonCount)
    $resolved = @()

    for ($i = 0; $i -lt $count; $i++) {
        $baseAction = if ($i -lt $baseActions.Count) {
            ConvertTo-SafeProfileButtonAction -Action ([string]$baseActions[$i])
        }
        else {
            'none'
        }

        $override = if ($null -eq $context) {
            'inherit'
        }
        else {
            Get-AdaptiveLayerButtonOverride -Config $script:AdaptiveLayerConfig -ContextKey $layerContextKey -Layer $layer -ButtonIndex $i
        }

        if ($override -eq 'inherit') {
            $resolved += $baseAction
        }
        else {
            $resolved += ConvertTo-SafeProfileButtonAction -Action $override
        }
    }

    $baseKey = [string]$BaseContext.Key
    if ([string]::IsNullOrWhiteSpace($baseKey)) { $baseKey = '__global__' }

    return [pscustomobject][ordered]@{
        Key = ('{0}|layer:{1}|layerProfile:{2}' -f $baseKey, $layer, $layerContextKey)
        Actions = @($resolved)
    }
}

function Get-AdaptiveLayerBaseButtonAction {
    param(
        [string]$ContextKey,
        [int]$ButtonIndex
    )

    Initialize-ButtonActions
    Initialize-AdaptiveProfiles

    if ($ButtonIndex -lt 0) { return 'none' }

    $key = Normalize-AdaptiveLayerContextKey -Key $ContextKey
    $actions = @($script:ButtonActions | ForEach-Object { [string]$_ })

    if ($key -ne '__global__') {
        foreach ($profile in @($script:AdaptiveProfiles)) {
            $processName = Normalize-TargetName -Value ([string]$profile.process)
            if ([string]::IsNullOrWhiteSpace($processName)) { continue }
            if ($processName.ToLowerInvariant() -ne $key) { continue }

            $profileButtons = @()
            if ($null -ne $profile.PSObject.Properties['buttons']) {
                $profileButtons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
            }
            if ($profileButtons.Count -gt 0) {
                $actions = @($profileButtons)
            }
            break
        }
    }

    if ($ButtonIndex -ge $actions.Count) { return 'none' }
    return ConvertTo-SafeProfileButtonAction -Action ([string]$actions[$ButtonIndex])
}

function Get-AdaptiveLayerOverrideDisplay {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'inherit') {
        return $(if ($script:Language -eq 'ru') { 'Наследовать основное действие' } else { 'Inherit base action' })
    }

    return Get-LargeButtonActionDisplay -Action $Action
}

function Populate-AdaptiveLayerButtonActionCombo {
    param(
        [Parameter(Mandatory = $true)]$Combo,
        [Parameter(Mandatory = $true)]$Map,
        [string]$CurrentAction = 'inherit'
    )

    $CurrentAction = ConvertTo-SafeAdaptiveLayerButtonOverride -Action $CurrentAction

    $Combo.BeginUpdate()
    try {
        $Combo.Items.Clear()
        $Map.Clear()

        [void]$Combo.Items.Add($(if ($script:Language -eq 'ru') { 'Наследовать основное действие' } else { 'Inherit base action' }))
        [void]$Map.Add('inherit')

        [void]$Combo.Items.Add((Get-ButtonFeatureText -Key 'None'))
        [void]$Map.Add('none')

        $sliderCount = [Math]::Min([int]$script:DetectedSliderCount, @($script:Config.sliders).Count)
        for ($sliderIndex = 0; $sliderIndex -lt $sliderCount; $sliderIndex++) {
            $name = [string]$script:Config.sliders[$sliderIndex].name
            if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]($sliderIndex + 1) }
            [void]$Combo.Items.Add((Get-ButtonFeatureText -Key 'MuteControl') + ' ' + ($sliderIndex + 1) + ' — ' + $name)
            [void]$Map.Add(('mute:' + $sliderIndex))
        }

        foreach ($fixedAction in @(
            @('PlayPause', 'media:playpause'),
            @('PreviousTrack', 'media:previous'),
            @('NextTrack', 'media:next'),
            @('StopPlayback', 'media:stop'),
            @('VolumeUp', 'system:volumeup'),
            @('VolumeDown', 'system:volumedown'),
            @('VolumeMute', 'system:volumemute')
        )) {
            [void]$Combo.Items.Add((Get-ButtonFeatureText -Key $fixedAction[0]))
            [void]$Map.Add([string]$fixedAction[1])
        }

        if (
            $script:VirtualGamepadFeatureAvailable -and
            (Test-MugenVirtualGamepadAction -Action $CurrentAction)
        ) {
            [void]$Combo.Items.Add((Get-MugenVirtualGamepadActionDisplay -Action $CurrentAction))
            [void]$Map.Add($CurrentAction)
        }

        if (
            $script:VirtualGamepadFeatureAvailable -and
            [string]$script:ControllerProtocol -eq 'adaptive'
        ) {
            [void]$Combo.Items.Add($(if ($script:Language -eq 'ru') { 'Виртуальный Xbox…' } else { 'Virtual Xbox…' }))
            [void]$Map.Add('virtual:xbox:configure')
        }

        if ($CurrentAction -match '^(hotkey:|launch64:|folder64:|command64:|url64:)') {
            [void]$Combo.Items.Add((Get-LargeButtonActionDisplay -Action $CurrentAction))
            [void]$Map.Add($CurrentAction)
        }

        [void]$Combo.Items.Add((Get-ButtonFeatureText -Key 'HotkeyConfigure'))
        [void]$Map.Add('hotkey:configure')

        if ($script:Language -eq 'ru') {
            [void]$Combo.Items.Add('Запустить программу / файл…')
            [void]$Combo.Items.Add('Открыть папку…')
            [void]$Combo.Items.Add('Выполнить команду…')
            [void]$Combo.Items.Add('Открыть URL…')
        }
        else {
            [void]$Combo.Items.Add('Launch program / file…')
            [void]$Combo.Items.Add('Open folder…')
            [void]$Combo.Items.Add('Run command…')
            [void]$Combo.Items.Add('Open URL…')
        }

        [void]$Map.Add('launch:configure')
        [void]$Map.Add('folder:configure')
        [void]$Map.Add('command:configure')
        [void]$Map.Add('url:configure')

        $selected = 0
        for ($i = 0; $i -lt $Map.Count; $i++) {
            if ([string]$Map[$i] -eq $CurrentAction) {
                $selected = $i
                break
            }
        }
        $Combo.SelectedIndex = $selected
    }
    finally {
        $Combo.EndUpdate()
    }
}

function Resolve-AdaptiveLayerConfiguredButtonAction {
    param(
        [string]$SelectedAction,
        [string]$PreviousAction,
        [System.Windows.Forms.IWin32Window]$Owner
    )

    switch ($SelectedAction) {
        'virtual:xbox:configure' {
            return Show-MugenVirtualGamepadButtonPicker -ExistingAction $PreviousAction -Owner $Owner
        }
        'hotkey:configure' { return Show-HotkeyEditor -ExistingAction $PreviousAction }
        'launch:configure' { return Select-LaunchTargetAction -ExistingAction $PreviousAction }
        'folder:configure' { return Select-FolderTargetAction -ExistingAction $PreviousAction }
        'command:configure' { return Show-CommandActionEditor -ExistingAction $PreviousAction }
        'url:configure' { return Show-UrlActionEditor -ExistingAction $PreviousAction }
        default { return $SelectedAction }
    }
}

function Show-AdaptiveLayerSettings {
    if (
        -not $script:IsConnected -or
        [string]$script:ControllerProtocol -ne 'adaptive' -or
        [int]$script:DetectedButtonCount -le 0 -or
        [int]$script:DetectedToggleCount -le 0
    ) {
        return
    }

    Initialize-AdaptiveLayers
    Initialize-AdaptiveActions
    Initialize-AdaptiveProfiles
    Initialize-ButtonActions

    $working = Copy-AdaptiveLayerConfig -Config $script:AdaptiveLayerConfig
    $buttonCount = [int]$script:DetectedButtonCount

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = if ($script:Language -eq 'ru') { 'Слои управления — Mugen Deej' } else { 'Control layers — Mugen Deej' }
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.ClientSize = [System.Drawing.Size]::new(860, 704)
    $dialog.MinimumSize = [System.Drawing.Size]::new(876, 743)
    $dialog.MaximumSize = [System.Drawing.Size]::new(876, 743)
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.Font = $form.Font
    Set-FormAppIcon -Form $dialog

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = if ($script:Language -eq 'ru') { 'Слои управления' } else { 'Control layers' }
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $dialog.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = if ($script:Language -eq 'ru') {
        'Тумблеры T1 и T2 могут работать как модификаторы. Здесь задаются отличия кнопок и энкодера для T1, T2 и T1 + T2; пустые назначения наследуют основной профиль.'
    }
    else {
        'Toggles T1 and T2 can act as modifiers. Define button and encoder overrides for T1, T2, and T1 + T2 here; empty overrides inherit the base profile.'
    }
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = [System.Drawing.Point]::new(25, 56)
    $hint.Size = [System.Drawing.Size]::new(810, 45)
    $dialog.Controls.Add($hint)

    $modifierGroup = New-Object MugenDeejWindowing.MugenGroupBox
    $modifierGroup.Text = if ($script:Language -eq 'ru') { 'Тумблеры-модификаторы' } else { 'Modifier toggles' }
    $modifierGroup.Location = [System.Drawing.Point]::new(22, 108)
    $modifierGroup.Size = [System.Drawing.Size]::new(816, 94)
    $dialog.Controls.Add($modifierGroup)

    $t1Check = New-Object System.Windows.Forms.CheckBox
    $t1Check.Text = if ($script:Language -eq 'ru') { 'Тумблер 1 = слой T1' } else { 'Toggle 1 = T1 layer' }
    $t1Check.AutoSize = $true
    $t1Check.Location = [System.Drawing.Point]::new(18, 31)
    $t1Check.Checked = [bool]$working.modifierToggles[0]
    $modifierGroup.Controls.Add($t1Check)

    $t2Check = New-Object System.Windows.Forms.CheckBox
    $t2Check.Text = if ($script:Language -eq 'ru') { 'Тумблер 2 = слой T2' } else { 'Toggle 2 = T2 layer' }
    $t2Check.AutoSize = $true
    $t2Check.Location = [System.Drawing.Point]::new(310, 31)
    $t2Check.Checked = ([int]$script:DetectedToggleCount -gt 1 -and [bool]$working.modifierToggles[1])
    $t2Check.Enabled = ([int]$script:DetectedToggleCount -gt 1)
    $modifierGroup.Controls.Add($t2Check)

    $modifierHint = New-Object System.Windows.Forms.Label
    $modifierHint.Text = if ($script:Language -eq 'ru') {
        'Когда тумблер используется как модификатор, его обычные действия ВКЛ/ВЫКЛ временно не выполняются.'
    }
    else {
        'While a toggle is used as a modifier, its normal ON/OFF actions are suppressed.'
    }
    $modifierHint.ForeColor = [System.Drawing.Color]::DimGray
    $modifierHint.Location = [System.Drawing.Point]::new(18, 58)
    $modifierHint.Size = [System.Drawing.Size]::new(570, 25)
    $modifierGroup.Controls.Add($modifierHint)

    $encoderLayerButton = New-Object MugenDeejWindowing.MugenButton
    $encoderLayerButton.Text = if ($script:Language -eq 'ru') { 'Энкодер в слоях…' } else { 'Layered encoder…' }
    $encoderLayerButton.Location = [System.Drawing.Point]::new(604, 52)
    $encoderLayerButton.Size = [System.Drawing.Size]::new(185, 30)
    $encoderLayerButton.Enabled = ([int]$script:DetectedEncoderCount -gt 0)
    $encoderLayerButton.Add_Click({
        Show-AdaptiveLayerEncoderSettings -Config $working -Owner $dialog
    })
    $modifierGroup.Controls.Add($encoderLayerButton)

    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = if ($script:Language -eq 'ru') { 'Профиль:' } else { 'Profile:' }
    $profileLabel.Location = [System.Drawing.Point]::new(25, 218)
    $profileLabel.Size = [System.Drawing.Size]::new(100, 28)
    $profileLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $dialog.Controls.Add($profileLabel)

    $profileCombo = New-Object MugenDeejWindowing.MugenComboBox
    $profileCombo.DropDownStyle = 'DropDownList'
    $profileCombo.Location = [System.Drawing.Point]::new(125, 216)
    $profileCombo.Size = [System.Drawing.Size]::new(410, 30)
    $dialog.Controls.Add($profileCombo)

    $profileMap = New-Object System.Collections.ArrayList
    [void]$profileCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Общий — для всех остальных приложений' } else { 'Global — all other applications' }))
    [void]$profileMap.Add('__global__')
    foreach ($profile in @($script:AdaptiveProfiles | Sort-Object name)) {
        $processName = Normalize-TargetName -Value ([string]$profile.process)
        if ([string]::IsNullOrWhiteSpace($processName)) { continue }
        [void]$profileCombo.Items.Add(('{0}  ({1}.exe)' -f [string]$profile.name, $processName))
        [void]$profileMap.Add($processName.ToLowerInvariant())
    }
    $profileCombo.SelectedIndex = 0

    $layerLabel = New-Object System.Windows.Forms.Label
    $layerLabel.Text = if ($script:Language -eq 'ru') { 'Слой:' } else { 'Layer:' }
    $layerLabel.Location = [System.Drawing.Point]::new(558, 218)
    $layerLabel.Size = [System.Drawing.Size]::new(70, 28)
    $layerLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $dialog.Controls.Add($layerLabel)

    $layerCombo = New-Object MugenDeejWindowing.MugenComboBox
    $layerCombo.DropDownStyle = 'DropDownList'
    $layerCombo.Location = [System.Drawing.Point]::new(625, 216)
    $layerCombo.Size = [System.Drawing.Size]::new(210, 30)
    [void]$layerCombo.Items.Add('T1')
    [void]$layerCombo.Items.Add('T2')
    [void]$layerCombo.Items.Add('T1 + T2')
    $layerCombo.SelectedIndex = 0
    $dialog.Controls.Add($layerCombo)

    $editorGroup = New-Object MugenDeejWindowing.MugenGroupBox
    $editorGroup.Text = if ($script:Language -eq 'ru') { 'Переопределения кнопок' } else { 'Button overrides' }
    $editorGroup.Location = [System.Drawing.Point]::new(22, 260)
    $editorGroup.Size = [System.Drawing.Size]::new(816, 360)
    $dialog.Controls.Add($editorGroup)

    $selectorFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $selectorFlow.Location = [System.Drawing.Point]::new(14, 30)
    $selectorFlow.Size = [System.Drawing.Size]::new(286, 312)
    $selectorFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $selectorFlow.WrapContents = $true
    $selectorFlow.AutoScroll = $true
    $editorGroup.Controls.Add($selectorFlow)

    $selectors = @()
    for ($i = 0; $i -lt $buttonCount; $i++) {
        $selector = New-Object MugenDeejWindowing.MugenButtonTile
        $selector.Text = [string]($i + 1)
        $selector.Tag = $i
        $selector.Size = [System.Drawing.Size]::new(42, 28)
        $selector.Margin = New-Object System.Windows.Forms.Padding(3, 2, 3, 2)
        $selector.TextAlign = 'MiddleCenter'
        $selector.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
        $selectorFlow.Controls.Add($selector)
        $selectors += $selector
    }

    $selectedHeading = New-Object System.Windows.Forms.Label
    $selectedHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    $selectedHeading.Location = [System.Drawing.Point]::new(320, 35)
    $selectedHeading.Size = [System.Drawing.Size]::new(472, 30)
    $editorGroup.Controls.Add($selectedHeading)

    $baseLabel = New-Object System.Windows.Forms.Label
    $baseLabel.ForeColor = [System.Drawing.Color]::DimGray
    $baseLabel.Location = [System.Drawing.Point]::new(320, 72)
    $baseLabel.Size = [System.Drawing.Size]::new(472, 54)
    $editorGroup.Controls.Add($baseLabel)

    $overrideLabel = New-Object System.Windows.Forms.Label
    $overrideLabel.Text = if ($script:Language -eq 'ru') { 'Действие в этом слое:' } else { 'Action in this layer:' }
    $overrideLabel.Location = [System.Drawing.Point]::new(320, 138)
    $overrideLabel.Size = [System.Drawing.Size]::new(220, 26)
    $editorGroup.Controls.Add($overrideLabel)

    $actionCombo = New-Object MugenDeejWindowing.MugenComboBox
    $actionCombo.DropDownStyle = 'DropDownList'
    $actionCombo.Location = [System.Drawing.Point]::new(320, 168)
    $actionCombo.Size = [System.Drawing.Size]::new(472, 30)
    $editorGroup.Controls.Add($actionCombo)

    $editorHint = New-Object System.Windows.Forms.Label
    $editorHint.Text = if ($script:Language -eq 'ru') {
        '«Наследовать» использует основное назначение выбранного профиля. «Не использовать» специально отключает кнопку только в этом слое.'
    }
    else {
        'Inherit uses the selected profile base mapping. Do nothing explicitly disables the button only in this layer.'
    }
    $editorHint.ForeColor = [System.Drawing.Color]::DimGray
    $editorHint.Location = [System.Drawing.Point]::new(320, 211)
    $editorHint.Size = [System.Drawing.Size]::new(472, 70)
    $editorGroup.Controls.Add($editorHint)

    $activePreview = New-Object System.Windows.Forms.Label
    $activePreview.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $activePreview.Location = [System.Drawing.Point]::new(320, 294)
    $activePreview.Size = [System.Drawing.Size]::new(472, 28)
    $editorGroup.Controls.Add($activePreview)

    $state = [pscustomobject]@{
        Selected = 0
        Suppress = $false
        ActionMap = New-Object System.Collections.ArrayList
        LastButtons = @($script:LatestButtons)
    }

    $getContextKey = {
        $index = [int]$profileCombo.SelectedIndex
        if ($index -lt 0 -or $index -ge $profileMap.Count) { return '__global__' }
        return [string]$profileMap[$index]
    }

    $getLayer = {
        return ([int]$layerCombo.SelectedIndex + 1)
    }

    $refreshEditor = {
        $index = [int]$state.Selected
        $contextKey = & $getContextKey
        $layer = & $getLayer

        $context = Get-AdaptiveLayerContextObject -Config $working -Key $contextKey -Create
        Ensure-AdaptiveLayerContextCapacity -Context $context -ButtonCount $buttonCount

        $baseAction = Get-AdaptiveLayerBaseButtonAction -ContextKey $contextKey -ButtonIndex $index
        $override = Get-AdaptiveLayerButtonOverride -Config $working -ContextKey $contextKey -Layer $layer -ButtonIndex $index

        $selectedHeading.Text = if ($script:Language -eq 'ru') {
            'Кнопка {0} · слой {1}' -f ($index + 1), (Get-AdaptiveLayerDisplayName -Layer $layer)
        }
        else {
            'Button {0} · layer {1}' -f ($index + 1), (Get-AdaptiveLayerDisplayName -Layer $layer)
        }

        $baseLabel.Text = if ($script:Language -eq 'ru') {
            'Основное действие: ' + (Get-LargeButtonActionDisplay -Action $baseAction)
        }
        else {
            'Base action: ' + (Get-LargeButtonActionDisplay -Action $baseAction)
        }

        $state.Suppress = $true
        try {
            Populate-AdaptiveLayerButtonActionCombo -Combo $actionCombo -Map $state.ActionMap -CurrentAction $override
        }
        finally {
            $state.Suppress = $false
        }

        $currentLayer = Get-AdaptiveLayerIndex
        $activePreview.Text = if ($script:Language -eq 'ru') {
            'Сейчас на контроллере: слой ' + (Get-AdaptiveLayerDisplayName -Layer $currentLayer)
        }
        else {
            'Controller now: layer ' + (Get-AdaptiveLayerDisplayName -Layer $currentLayer)
        }
    }

    $selectButton = {
        param([int]$Index)

        if ($Index -lt 0 -or $Index -ge $buttonCount) { return }
        $state.Selected = $Index
        & $refreshEditor
    }

    foreach ($selector in $selectors) {
        $selector.Add_Click({
            param($sender, $eventArgs)
            & $selectButton -Index ([int]$sender.Tag)
        })
    }

    $profileCombo.Add_SelectedIndexChanged({
        if (-not $state.Suppress) { & $refreshEditor }
    })
    $layerCombo.Add_SelectedIndexChanged({
        if (-not $state.Suppress) { & $refreshEditor }
    })

    $actionCombo.Add_SelectedIndexChanged({
        if ($state.Suppress) { return }

        $selectedIndex = [int]$actionCombo.SelectedIndex
        if ($selectedIndex -lt 0 -or $selectedIndex -ge $state.ActionMap.Count) { return }

        $selectedAction = [string]$state.ActionMap[$selectedIndex]
        $index = [int]$state.Selected
        $contextKey = & $getContextKey
        $layer = & $getLayer
        $previous = Get-AdaptiveLayerButtonOverride -Config $working -ContextKey $contextKey -Layer $layer -ButtonIndex $index

        $configure = @(
            'virtual:xbox:configure',
            'hotkey:configure',
            'launch:configure',
            'folder:configure',
            'command:configure',
            'url:configure'
        )

        $configured = if ($selectedAction -in $configure) {
            Resolve-AdaptiveLayerConfiguredButtonAction -SelectedAction $selectedAction -PreviousAction $previous -Owner $dialog
        }
        else {
            $selectedAction
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$configured)) {
            Set-AdaptiveLayerButtonOverride -Config $working -ContextKey $contextKey -Layer $layer -ButtonIndex $index -Action ([string]$configured) -ButtonCount $buttonCount
        }

        & $refreshEditor
    })

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(610, 650)
    $cancel.Size = [System.Drawing.Size]::new(105, 36)
    $dialog.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(727, 650)
    $save.Size = [System.Drawing.Size]::new(108, 36)
    $dialog.Controls.Add($save)

    $save.Add_Click({
        $working.modifierToggles = @(
            [bool]$t1Check.Checked,
            $(if ([int]$script:DetectedToggleCount -gt 1) { [bool]$t2Check.Checked } else { $false })
        )

        $script:AdaptiveLayerConfig = ConvertTo-NormalizedAdaptiveLayerConfig -Data $working
        $script:AdaptiveLayersLoaded = $true
        Save-AdaptiveLayers

        if (
            $script:VirtualGamepadFeatureAvailable -and
            $script:IsConnected -and
            [string]$script:ControllerProtocol -eq 'adaptive' -and
            @($script:LatestButtons).Count -gt 0
        ) {
            try {
                Update-MugenVirtualGamepadButtonStates -Values @($script:LatestButtons) -ForceProfileCheck
            }
            catch {}
        }

        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Close()
    })

    $liveTimer = New-Object System.Windows.Forms.Timer
    $liveTimer.Interval = 40
    $liveTimer.Add_Tick({
        $latest = @($script:LatestButtons)
        $compareCount = [Math]::Min($latest.Count, @($state.LastButtons).Count)
        for ($i = 0; $i -lt $compareCount; $i++) {
            if ([int]$latest[$i] -eq 0 -and [int]$state.LastButtons[$i] -ne 0) {
                & $selectButton -Index $i
                break
            }
        }
        $state.LastButtons = @($latest)

        $currentLayer = Get-AdaptiveLayerIndex
        $preview = if ($script:Language -eq 'ru') {
            'Сейчас на контроллере: слой ' + (Get-AdaptiveLayerDisplayName -Layer $currentLayer)
        }
        else {
            'Controller now: layer ' + (Get-AdaptiveLayerDisplayName -Layer $currentLayer)
        }
        if ($activePreview.Text -ne $preview) {
            $activePreview.Text = $preview
        }
    })

    Apply-ThemeToForm -Form $dialog
    & $refreshEditor

    $dialog.Add_Shown({
        Ensure-FormVisible -Form $dialog -CenterIfOffscreen
        $liveTimer.Start()
    })
    $dialog.Add_FormClosed({
        $liveTimer.Stop()
        $liveTimer.Dispose()
    })

    $dialog.AcceptButton = $save
    $dialog.CancelButton = $cancel
    [void]$dialog.ShowDialog($form)
    if (-not $dialog.IsDisposed) { $dialog.Dispose() }
}

'@

$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText 'function Show-AdaptiveControlSettings {' -NewText ($layerFunctions + 'function Show-AdaptiveControlSettings {') -Label 'insert Adaptive layer runtime and editor'

# Wrap the existing Global/application button context instead of modifying its
# compatibility behavior. The wrapper only resolves layers for Adaptive v3.
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText 'function Get-ProfiledButtonActionContext {' -NewText 'function Get-BaseProfiledButtonActionContext {' -Label 'rename base profiled button context'

$profileWrapper = @'
function Get-ProfiledButtonActionContext {
    $baseContext = Get-BaseProfiledButtonActionContext
    return Resolve-AdaptiveLayerButtonContext -BaseContext $baseContext
}

'@
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText 'function Get-ProfiledButtonAction {' -NewText ($profileWrapper + 'function Get-ProfiledButtonAction {') -Label 'add layer-aware profiled button context'

# Encoder mappings use the same active T1/T2 layer as buttons. Keep the
# existing profile-aware encoder resolver intact behind an Adaptive-only
# wrapper so Legacy/Extended behavior and base Adaptive mappings stay stable.
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText 'function Get-AdaptiveEncoderMappedAction {' -NewText 'function Get-BaseAdaptiveEncoderMappedAction {' -Label 'rename base Adaptive encoder action resolver'

$encoderLayerWrapper = @'
function Get-AdaptiveEncoderMappedAction {
    param([int]$Index, [ValidateSet('cw','ccw','push')][string]$Kind)

    $baseAction = Get-BaseAdaptiveEncoderMappedAction -Index $Index -Kind $Kind

    if ([string]$script:ControllerProtocol -ne 'adaptive') {
        return $baseAction
    }

    $layer = Get-AdaptiveLayerIndex
    if ($layer -le 0 -or -not (Test-AdaptiveLayersEnabled)) {
        return $baseAction
    }

    Initialize-AdaptiveLayers
    $contextKey = Get-AdaptiveLayerProfileKey
    $override = Get-AdaptiveLayerEncoderOverride -Config $script:AdaptiveLayerConfig -ContextKey $contextKey -Layer $layer -EncoderIndex $Index -Kind $Kind

    if ($override -eq 'inherit') {
        return $baseAction
    }

    return ConvertTo-SafeAdaptiveAction -Action $override
}

'@
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText 'function Invoke-AdaptiveMappedAction {' -NewText ($encoderLayerWrapper + 'function Invoke-AdaptiveMappedAction {') -Label 'add layer-aware Adaptive encoder resolver'

# Modifier toggles select a layer and no longer fire their ordinary ON/OFF
# command at the same time. Non-modifier toggles retain the exact existing path.
$toggleActionOld = @'
            $action = Get-AdaptiveToggleMappedAction -Index $i -State $newState
            Invoke-AdaptiveMappedAction -Action $action -Source ('Toggle {0} {1}' -f ($i + 1), $stateText)
'@
$toggleActionNew = @'
            if (Test-AdaptiveToggleIsLayerModifier -Index $i) {
                Write-Log ('Toggle {0} is a layer modifier; ordinary {1} action suppressed' -f ($i + 1), $stateText) 'DEBUG'
            }
            else {
                $action = Get-AdaptiveToggleMappedAction -Index $i -State $newState
                Invoke-AdaptiveMappedAction -Action $action -Source ('Toggle {0} {1}' -f ($i + 1), $stateText)
            }
'@
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText $toggleActionOld -NewText $toggleActionNew -Label 'suppress ordinary actions for modifier toggles'

$oldTogglesOld = @'
    $oldToggles = @($script:LatestToggles)
    for ($i = 0; $i -lt $newToggles.Count; $i++) {
'@
$oldTogglesNew = @'
    $oldToggles = @($script:LatestToggles)
    $oldLayer = Get-AdaptiveLayerIndexFromValues -Values $oldToggles
    $newLayer = Get-AdaptiveLayerIndexFromValues -Values $newToggles

    for ($i = 0; $i -lt $newToggles.Count; $i++) {
'@
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText $oldTogglesOld -NewText $oldTogglesNew -Label 'capture Adaptive layer transition'

$encoderLayerOrderOld = @'
    $oldEncoders = @($script:LatestEncoders)
'@
$encoderLayerOrderNew = @'
    # From this point onward encoder edges in this same Adaptive packet use
    # the newly selected T1/T2 layer.
    $script:LatestToggles = @($newToggles)

    $oldEncoders = @($script:LatestEncoders)
'@
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText $encoderLayerOrderOld -NewText $encoderLayerOrderNew -Label 'apply new Adaptive layer before encoder edges'

$latestTogglesOld = @'
    $script:LatestToggles = @($newToggles)
    $script:LatestEncoders = @($newEncoders)
'@
$latestTogglesNew = @'
    if ($oldLayer -ne $newLayer) {
        Write-Log (
            'Adaptive layer changed: {0} -> {1}' -f
            (Get-AdaptiveLayerDisplayName -Layer $oldLayer),
            (Get-AdaptiveLayerDisplayName -Layer $newLayer)
        ) 'INFO'

        # The virtual-controller profile context includes the active layer.
        # Force a boundary check so a held XInput mapping is neutralized and
        # suppressed until release instead of morphing into another layer.
        if (
            $script:VirtualGamepadFeatureAvailable -and
            $script:IsConnected -and
            @($script:LatestButtons).Count -gt 0
        ) {
            try {
                Update-MugenVirtualGamepadButtonStates -Values @($script:LatestButtons) -ForceProfileCheck
            }
            catch {}
        }
    }

    $script:LatestEncoders = @($newEncoders)
'@
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText $latestTogglesOld -NewText $latestTogglesNew -Label 'apply Adaptive layer transition before virtual output refresh'

# Adaptive packets must update toggle state before button edges so a packet
# that changes a toggle and presses a button uses the new layer immediately.
# Legacy/Extended preserve the historical button-first order byte-for-byte.
$packetOrderOld = @'
                    Update-ButtonStates -Values @($parsed.Buttons)
                    Update-AdaptiveControlStates -Packet $parsed
'@
$packetOrderNew = @'
                    if ([string]$parsed.Protocol -eq 'adaptive') {
                        Update-AdaptiveControlStates -Packet $parsed
                        Update-ButtonStates -Values @($parsed.Buttons)
                    }
                    else {
                        Update-ButtonStates -Values @($parsed.Buttons)
                        Update-AdaptiveControlStates -Packet $parsed
                    }
'@
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText $packetOrderOld -NewText $packetOrderNew -Label 'use layer state before Adaptive button edges while preserving older protocols'

# Show the active layer directly beside the live toggle heading, but only when
# the Adaptive modifier feature is enabled.
$toggleHeadingOld = @'
    if ($null -ne $script:ToggleStateLabel -and -not $script:ToggleStateLabel.IsDisposed) {
        $script:ToggleStateLabel.Text = Get-AdaptiveInputUiText -Key 'Toggles'
        $script:ToggleStateLabel.Visible = ($metrics.ToggleCount -gt 0)
    }
'@
$toggleHeadingNew = @'
    if ($null -ne $script:ToggleStateLabel -and -not $script:ToggleStateLabel.IsDisposed) {
        $toggleHeading = Get-AdaptiveInputUiText -Key 'Toggles'
        if (Test-AdaptiveLayersEnabled) {
            $toggleHeading += $(if ($script:Language -eq 'ru') { ' · слой: ' } else { ' · layer: ' })
            $toggleHeading += Get-AdaptiveLayerDisplayName -Layer (Get-AdaptiveLayerIndex)
        }
        $script:ToggleStateLabel.Text = $toggleHeading
        $script:ToggleStateLabel.Visible = ($metrics.ToggleCount -gt 0)
    }
'@
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText $toggleHeadingOld -NewText $toggleHeadingNew -Label 'show active Adaptive layer in live status'

# Put the layer editor in the existing Adaptive settings dialog without
# changing the Legacy/Extended button editor.
$profileHintOld = @'
    $profileHint.ForeColor = [System.Drawing.Color]::DimGray
    $profileHint.Location = [System.Drawing.Point]::new(25, 173)
    $profileHint.Size = [System.Drawing.Size]::new(770, 28)
    $settingsForm.Controls.Add($profileHint)

    $selectorGroup = New-Object MugenDeejWindowing.MugenGroupBox
'@
$profileHintNew = @'
    $profileHint.ForeColor = [System.Drawing.Color]::DimGray
    $profileHint.Location = [System.Drawing.Point]::new(25, 173)
    $profileHint.Size = [System.Drawing.Size]::new(560, 28)
    $settingsForm.Controls.Add($profileHint)

    $layerSettingsButton = New-Object MugenDeejWindowing.MugenButton
    $layerSettingsButton.Text = if ($script:Language -eq 'ru') { 'Слои кнопок…' } else { 'Button layers…' }
    $layerSettingsButton.Location = [System.Drawing.Point]::new(600, 170)
    $layerSettingsButton.Size = [System.Drawing.Size]::new(198, 30)
    $layerSettingsButton.Enabled = ([string]$script:ControllerProtocol -eq 'adaptive' -and [int]$script:DetectedToggleCount -gt 0 -and [int]$script:DetectedButtonCount -gt 0)
    $layerSettingsButton.Add_Click({ Show-AdaptiveLayerSettings })
    $settingsForm.Controls.Add($layerSettingsButton)

    $selectorGroup = New-Object MugenDeejWindowing.MugenGroupBox
'@
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText $profileHintOld -NewText $profileHintNew -Label 'add layer editor entry point to Adaptive settings'

[System.IO.File]::WriteAllText($resolved, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Applied Adaptive toggle-layer mappings to staged runtime: $resolved"
