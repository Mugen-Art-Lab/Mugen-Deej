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
$script:LayerStateLabel = $null
$script:AdaptiveLayerPopupForm = $null
$script:AdaptiveLayerPopupTimer = $null
'@
$text = $text.Substring(0, $profileLineStart) + $stateNew + $text.Substring($profileLineEnd)

$layerPopupClass = @'
    public sealed class MugenLayerPopupForm : Form
    {
        protected override bool ShowWithoutActivation
        {
            get { return true; }
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                const int WS_EX_NOACTIVATE = 0x08000000;
                const int WS_EX_TOOLWINDOW = 0x00000080;
                cp.ExStyle |= WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
                return cp;
            }
        }
    }

'@

$text = Replace-LayerLiteralExactlyOnce `
    -Text $text `
    -OldText '    public sealed class ThemePreferenceBridge : IDisposable' `
    -NewText ($layerPopupClass + '    public sealed class ThemePreferenceBridge : IDisposable') `
    -Label 'add non-activating Adaptive layer popup form'

$layerFunctions = @'
function New-DefaultAdaptiveLayerConfig {
    return [pscustomobject][ordered]@{
        version = 1
        modifierToggles = @($false, $false)
        names = [pscustomobject][ordered]@{
            base = ''
            t1 = ''
            t2 = ''
            both = ''
        }
        notification = [pscustomobject][ordered]@{
            enabled = $false
            topMost = $true
            screen = ''
            position = 'topRight'
            durationMs = 2000
        }
        contexts = @()
    }
}

function ConvertTo-SafeAdaptiveLayerCustomName {
    param([string]$Value)

    if ($null -eq $Value) { return '' }

    $safe = ([string]$Value) -replace '[\r\n\t]+', ' '
    $safe = $safe.Trim()
    if ($safe.Length -gt 24) {
        $safe = $safe.Substring(0, 24).TrimEnd()
    }

    return $safe
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

    if ($null -ne $Data.PSObject.Properties['names'] -and $null -ne $Data.names) {
        foreach ($nameKey in @('base','t1','t2','both')) {
            $nameProperty = $Data.names.PSObject.Properties[$nameKey]
            if ($null -ne $nameProperty) {
                $result.names.$nameKey = ConvertTo-SafeAdaptiveLayerCustomName -Value ([string]$nameProperty.Value)
            }
        }
    }

    if ($null -ne $Data.PSObject.Properties['notification'] -and $null -ne $Data.notification) {
        $notification = $Data.notification

        if ($null -ne $notification.PSObject.Properties['enabled']) {
            $result.notification.enabled = [bool]$notification.enabled
        }
        if ($null -ne $notification.PSObject.Properties['topMost']) {
            $result.notification.topMost = [bool]$notification.topMost
        }
        if ($null -ne $notification.PSObject.Properties['screen']) {
            $result.notification.screen = ([string]$notification.screen).Trim()
        }

        $validPositions = @(
            'topLeft','topCenter','topRight',
            'middleLeft','center','middleRight',
            'bottomLeft','bottomCenter','bottomRight'
        )
        if ($null -ne $notification.PSObject.Properties['position']) {
            $candidatePosition = [string]$notification.position
            if ($candidatePosition -in $validPositions) {
                $result.notification.position = $candidatePosition
            }
        }

        if ($null -ne $notification.PSObject.Properties['durationMs']) {
            $duration = [int]$notification.durationMs
            if ($duration -lt 500) { $duration = 500 }
            if ($duration -gt 10000) { $duration = 10000 }
            $result.notification.durationMs = $duration
        }
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

function Get-AdaptiveLayerDefaultDisplayName {
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

function Get-AdaptiveLayerCustomNameKey {
    param([int]$Layer)

    switch ($Layer) {
        1 { return 't1' }
        2 { return 't2' }
        3 { return 'both' }
        default { return 'base' }
    }
}

function Get-AdaptiveLayerDisplayNameFromConfig {
    param(
        $Config,
        [int]$Layer
    )

    $fallback = Get-AdaptiveLayerDefaultDisplayName -Layer $Layer
    if ($null -eq $Config -or $null -eq $Config.PSObject.Properties['names'] -or $null -eq $Config.names) {
        return $fallback
    }

    $key = Get-AdaptiveLayerCustomNameKey -Layer $Layer
    $property = $Config.names.PSObject.Properties[$key]
    if ($null -eq $property) { return $fallback }

    $custom = ConvertTo-SafeAdaptiveLayerCustomName -Value ([string]$property.Value)
    if ([string]::IsNullOrWhiteSpace($custom)) { return $fallback }

    return $custom
}

function Get-AdaptiveLayerDisplayName {
    param([int]$Layer)

    Initialize-AdaptiveLayers
    return Get-AdaptiveLayerDisplayNameFromConfig -Config $script:AdaptiveLayerConfig -Layer $Layer
}

function Set-AdaptiveLayerComboDisplayItems {
    param(
        [Parameter(Mandatory = $true)]$Combo,
        [Parameter(Mandatory = $true)]$Config
    )

    $selected = [int]$Combo.SelectedIndex
    if ($selected -lt 0 -or $selected -gt 2) { $selected = 0 }

    $Combo.BeginUpdate()
    try {
        $Combo.Items.Clear()
        for ($layer = 1; $layer -le 3; $layer++) {
            [void]$Combo.Items.Add((Get-AdaptiveLayerDisplayNameFromConfig -Config $Config -Layer $layer))
        }
        $Combo.SelectedIndex = $selected
    }
    finally {
        $Combo.EndUpdate()
    }
}

function Get-AdaptiveLayerNotificationScreen {
    param($Config)

    $screens = @([System.Windows.Forms.Screen]::AllScreens)
    if ($screens.Count -le 0) { return $null }

    $deviceName = ''
    if (
        $null -ne $Config -and
        $null -ne $Config.PSObject.Properties['notification'] -and
        $null -ne $Config.notification
    ) {
        $deviceName = ([string]$Config.notification.screen).Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($deviceName)) {
        foreach ($screen in $screens) {
            if ([string]$screen.DeviceName -eq $deviceName) {
                return $screen
            }
        }
    }

    foreach ($screen in $screens) {
        if ($screen.Primary) { return $screen }
    }

    return $screens[0]
}

function Get-AdaptiveLayerPopupLocation {
    param(
        [Parameter(Mandatory = $true)]$Screen,
        [string]$Position,
        [int]$Width,
        [int]$Height
    )

    $area = $Screen.WorkingArea
    $margin = 24

    $leftX = $area.Left + $margin
    $centerX = $area.Left + [int](($area.Width - $Width) / 2)
    $rightX = $area.Right - $Width - $margin

    $topY = $area.Top + $margin
    $centerY = $area.Top + [int](($area.Height - $Height) / 2)
    $bottomY = $area.Bottom - $Height - $margin

    switch ($Position) {
        'topLeft'      { return [System.Drawing.Point]::new($leftX, $topY) }
        'topCenter'    { return [System.Drawing.Point]::new($centerX, $topY) }
        'middleLeft'   { return [System.Drawing.Point]::new($leftX, $centerY) }
        'center'       { return [System.Drawing.Point]::new($centerX, $centerY) }
        'middleRight'  { return [System.Drawing.Point]::new($rightX, $centerY) }
        'bottomLeft'   { return [System.Drawing.Point]::new($leftX, $bottomY) }
        'bottomCenter' { return [System.Drawing.Point]::new($centerX, $bottomY) }
        'bottomRight'  { return [System.Drawing.Point]::new($rightX, $bottomY) }
        default        { return [System.Drawing.Point]::new($rightX, $topY) }
    }
}

function Close-AdaptiveLayerNotification {
    if ($null -ne $script:AdaptiveLayerPopupTimer) {
        try {
            $script:AdaptiveLayerPopupTimer.Stop()
            $script:AdaptiveLayerPopupTimer.Dispose()
        }
        catch {}
        $script:AdaptiveLayerPopupTimer = $null
    }

    if ($null -ne $script:AdaptiveLayerPopupForm) {
        try {
            if (-not $script:AdaptiveLayerPopupForm.IsDisposed) {
                $script:AdaptiveLayerPopupForm.Close()
                $script:AdaptiveLayerPopupForm.Dispose()
            }
        }
        catch {}
        $script:AdaptiveLayerPopupForm = $null
    }
}

function Show-AdaptiveLayerNotification {
    param(
        [int]$Layer,
        $Config = $null,
        [switch]$Force
    )

    if ($null -eq $Config) {
        Initialize-AdaptiveLayers
        $Config = $script:AdaptiveLayerConfig
    }

    if (
        $null -eq $Config -or
        $null -eq $Config.PSObject.Properties['notification'] -or
        $null -eq $Config.notification
    ) {
        return
    }

    if (-not $Force -and -not [bool]$Config.notification.enabled) {
        return
    }

    $screen = Get-AdaptiveLayerNotificationScreen -Config $Config
    if ($null -eq $screen) { return }

    Close-AdaptiveLayerNotification

    $displayName = Get-AdaptiveLayerDisplayNameFromConfig -Config $Config -Layer $Layer
    $nameFont = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
    $measuredName = [System.Windows.Forms.TextRenderer]::MeasureText(
        $displayName,
        $nameFont,
        [System.Drawing.Size]::new(2000, 80),
        [System.Windows.Forms.TextFormatFlags]::SingleLine -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
    )
    $availablePopupWidth = [Math]::Max(260, ([int]$screen.WorkingArea.Width - 48))
    $maximumPopupWidth = [Math]::Min(620, $availablePopupWidth)
    $minimumPopupWidth = [Math]::Min(340, $maximumPopupWidth)
    $popupWidth = [Math]::Max(
        $minimumPopupWidth,
        [Math]::Min($maximumPopupWidth, ([int]$measuredName.Width + 48))
    )

    $popup = New-Object MugenDeejWindowing.MugenLayerPopupForm
    $popup.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $popup.ShowInTaskbar = $false
    $popup.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $popup.TopMost = [bool]$Config.notification.topMost
    $popup.ClientSize = [System.Drawing.Size]::new($popupWidth, 104)
    $popup.MinimumSize = $popup.Size
    $popup.MaximumSize = $popup.Size
    $popup.Padding = New-Object System.Windows.Forms.Padding(0)

    $card = New-Object MugenDeejWindowing.MugenCardPanel
    $card.Dock = [System.Windows.Forms.DockStyle]::Fill
    $card.CornerRadius = 14
    $popup.Controls.Add($card)

    $caption = New-Object System.Windows.Forms.Label
    $caption.Text = if ($script:Language -eq 'ru') { 'Активный слой' } else { 'Active layer' }
    $caption.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $caption.Location = [System.Drawing.Point]::new(18, 14)
    $caption.Size = [System.Drawing.Size]::new(300, 20)
    $caption.ForeColor = [System.Drawing.Color]::DimGray
    $card.Controls.Add($caption)

    $name = New-Object System.Windows.Forms.Label
    $name.Text = $displayName
    $name.Font = $nameFont
    $name.Location = [System.Drawing.Point]::new(17, 38)
    $name.Size = [System.Drawing.Size]::new(($popupWidth - 34), 43)
    $name.AutoEllipsis = $true
    $name.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $card.Controls.Add($name)

    Apply-ThemeToForm -Form $popup
    Set-RoundedControlRegion -Control $popup -Radius 14

    $position = [string]$Config.notification.position
    $popup.Location = Get-AdaptiveLayerPopupLocation -Screen $screen -Position $position -Width $popup.Width -Height $popup.Height

    $duration = [int]$Config.notification.durationMs
    if ($duration -lt 500) { $duration = 500 }
    if ($duration -gt 10000) { $duration = 10000 }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $duration
    $timer.Add_Tick({
        Close-AdaptiveLayerNotification
    })

    $script:AdaptiveLayerPopupForm = $popup
    $script:AdaptiveLayerPopupTimer = $timer

    $popup.Show()
    $timer.Start()
}

function Get-AdaptiveLayerNotificationPositionDisplay {
    param([string]$Position)

    if ($script:Language -eq 'ru') {
        switch ($Position) {
            'topLeft'      { return 'Слева сверху' }
            'topCenter'    { return 'По центру сверху' }
            'topRight'     { return 'Справа сверху' }
            'middleLeft'   { return 'Слева по центру' }
            'center'       { return 'По центру' }
            'middleRight'  { return 'Справа по центру' }
            'bottomLeft'   { return 'Слева снизу' }
            'bottomCenter' { return 'По центру снизу' }
            'bottomRight'  { return 'Справа снизу' }
        }
    }

    switch ($Position) {
        'topLeft'      { return 'Top left' }
        'topCenter'    { return 'Top center' }
        'topRight'     { return 'Top right' }
        'middleLeft'   { return 'Middle left' }
        'center'       { return 'Center' }
        'middleRight'  { return 'Middle right' }
        'bottomLeft'   { return 'Bottom left' }
        'bottomCenter' { return 'Bottom center' }
        'bottomRight'  { return 'Bottom right' }
        default        { return $Position }
    }
}

function Show-AdaptiveLayerNotificationSettings {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [System.Windows.Forms.IWin32Window]$Owner
    )

    $workingNotification = ConvertTo-NormalizedAdaptiveLayerConfig -Data $Config
    $workingNotification = $workingNotification.notification

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = if ($script:Language -eq 'ru') { 'Уведомление о смене слоя — Mugen Deej' } else { 'Layer-change notification — Mugen Deej' }
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.ClientSize = [System.Drawing.Size]::new(700, 392)
    $dialog.MinimumSize = [System.Drawing.Size]::new(716, 431)
    $dialog.MaximumSize = [System.Drawing.Size]::new(716, 431)
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.Font = $form.Font
    Set-FormAppIcon -Form $dialog

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = if ($script:Language -eq 'ru') { 'Всплывающее уведомление' } else { 'Popup notification' }
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $dialog.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = if ($script:Language -eq 'ru') {
        'Показывает имя активного слоя при переключении T1/T2. Экран и позиция выбираются отдельно для многомониторной системы.'
    }
    else {
        'Shows the active layer name when T1/T2 changes. Choose a specific display and anchor for multi-monitor setups.'
    }
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = [System.Drawing.Point]::new(25, 57)
    $hint.Size = [System.Drawing.Size]::new(650, 42)
    $dialog.Controls.Add($hint)

    $card = New-Object MugenDeejWindowing.MugenGroupBox
    $card.Text = if ($script:Language -eq 'ru') { 'Параметры' } else { 'Options' }
    $card.Location = [System.Drawing.Point]::new(22, 110)
    $card.Size = [System.Drawing.Size]::new(656, 210)
    $dialog.Controls.Add($card)

    $enabledCheck = New-Object System.Windows.Forms.CheckBox
    $enabledCheck.Text = if ($script:Language -eq 'ru') { 'Показывать уведомление при смене слоя' } else { 'Show a notification when the layer changes' }
    $enabledCheck.AutoSize = $true
    $enabledCheck.Location = [System.Drawing.Point]::new(16, 30)
    $enabledCheck.Checked = [bool]$workingNotification.enabled
    $card.Controls.Add($enabledCheck)

    $topMostCheck = New-Object System.Windows.Forms.CheckBox
    $topMostCheck.Text = if ($script:Language -eq 'ru') { 'Показывать поверх окон' } else { 'Show above other windows' }
    $topMostCheck.AutoSize = $true
    $topMostCheck.Location = [System.Drawing.Point]::new(350, 30)
    $topMostCheck.Checked = [bool]$workingNotification.topMost
    $card.Controls.Add($topMostCheck)

    $screenLabel = New-Object System.Windows.Forms.Label
    $screenLabel.Text = if ($script:Language -eq 'ru') { 'Экран' } else { 'Display' }
    $screenLabel.Location = [System.Drawing.Point]::new(16, 72)
    $screenLabel.Size = [System.Drawing.Size]::new(90, 25)
    $screenLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $card.Controls.Add($screenLabel)

    $screenCombo = New-Object MugenDeejWindowing.MugenComboBox
    $screenCombo.DropDownStyle = 'DropDownList'
    $screenCombo.Location = [System.Drawing.Point]::new(105, 70)
    $screenCombo.Size = [System.Drawing.Size]::new(525, 30)
    $card.Controls.Add($screenCombo)

    $screenMap = New-Object System.Collections.ArrayList
    $screens = @([System.Windows.Forms.Screen]::AllScreens)
    $screenSelected = 0
    for ($i = 0; $i -lt $screens.Count; $i++) {
        $screen = $screens[$i]
        $bounds = $screen.Bounds
        $primarySuffix = if ($screen.Primary) {
            $(if ($script:Language -eq 'ru') { ' · основной' } else { ' · primary' })
        }
        else { '' }

        $label = '{0}. {1} · {2}x{3}{4}' -f ($i + 1), $screen.DeviceName, $bounds.Width, $bounds.Height, $primarySuffix
        [void]$screenCombo.Items.Add($label)
        [void]$screenMap.Add([string]$screen.DeviceName)

        if (
            -not [string]::IsNullOrWhiteSpace([string]$workingNotification.screen) -and
            [string]$workingNotification.screen -eq [string]$screen.DeviceName
        ) {
            $screenSelected = $i
        }
        elseif ([string]::IsNullOrWhiteSpace([string]$workingNotification.screen) -and $screen.Primary) {
            $screenSelected = $i
        }
    }
    if ($screenCombo.Items.Count -gt 0) { $screenCombo.SelectedIndex = $screenSelected }

    $positionLabel = New-Object System.Windows.Forms.Label
    $positionLabel.Text = if ($script:Language -eq 'ru') { 'Положение' } else { 'Position' }
    $positionLabel.Location = [System.Drawing.Point]::new(16, 116)
    $positionLabel.Size = [System.Drawing.Size]::new(90, 25)
    $positionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $card.Controls.Add($positionLabel)

    $positionCombo = New-Object MugenDeejWindowing.MugenComboBox
    $positionCombo.DropDownStyle = 'DropDownList'
    $positionCombo.Location = [System.Drawing.Point]::new(105, 114)
    $positionCombo.Size = [System.Drawing.Size]::new(220, 30)
    $card.Controls.Add($positionCombo)

    $positionMap = New-Object System.Collections.ArrayList
    foreach ($position in @(
        'topLeft','topCenter','topRight',
        'middleLeft','center','middleRight',
        'bottomLeft','bottomCenter','bottomRight'
    )) {
        [void]$positionCombo.Items.Add((Get-AdaptiveLayerNotificationPositionDisplay -Position $position))
        [void]$positionMap.Add($position)
    }
    $positionSelected = $positionMap.IndexOf([string]$workingNotification.position)
    if ($positionSelected -lt 0) { $positionSelected = 2 }
    $positionCombo.SelectedIndex = $positionSelected

    $durationLabel = New-Object System.Windows.Forms.Label
    $durationLabel.Text = if ($script:Language -eq 'ru') { 'Показывать, сек' } else { 'Duration, sec' }
    $durationLabel.Location = [System.Drawing.Point]::new(350, 116)
    $durationLabel.Size = [System.Drawing.Size]::new(120, 25)
    $durationLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $card.Controls.Add($durationLabel)

    $durationBox = New-Object System.Windows.Forms.NumericUpDown
    $durationBox.DecimalPlaces = 1
    $durationBox.Increment = [decimal]0.5
    $durationBox.Minimum = [decimal]0.5
    $durationBox.Maximum = [decimal]10.0
    $durationBox.Location = [System.Drawing.Point]::new(480, 115)
    $durationBox.Size = [System.Drawing.Size]::new(100, 26)
    $durationBox.Value = [decimal]([double]$workingNotification.durationMs / 1000.0)
    $card.Controls.Add($durationBox)

    $testButton = New-Object MugenDeejWindowing.MugenButton
    $testButton.Text = if ($script:Language -eq 'ru') { 'Тест уведомления' } else { 'Test notification' }
    $testButton.Location = [System.Drawing.Point]::new(440, 160)
    $testButton.Size = [System.Drawing.Size]::new(190, 34)
    $card.Controls.Add($testButton)

    $readControls = {
        $workingNotification.enabled = [bool]$enabledCheck.Checked
        $workingNotification.topMost = [bool]$topMostCheck.Checked

        $screenIndex = [int]$screenCombo.SelectedIndex
        if ($screenIndex -ge 0 -and $screenIndex -lt $screenMap.Count) {
            $workingNotification.screen = [string]$screenMap[$screenIndex]
        }

        $positionIndex = [int]$positionCombo.SelectedIndex
        if ($positionIndex -ge 0 -and $positionIndex -lt $positionMap.Count) {
            $workingNotification.position = [string]$positionMap[$positionIndex]
        }

        $workingNotification.durationMs = [int]([decimal]$durationBox.Value * 1000)
    }

    $testButton.Add_Click({
        & $readControls
        $previewConfig = ConvertTo-NormalizedAdaptiveLayerConfig -Data $Config
        $previewConfig.notification = $workingNotification
        $previewLayer = Get-AdaptiveLayerIndex
        Show-AdaptiveLayerNotification -Layer $previewLayer -Config $previewConfig -Force
    })

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(450, 340)
    $cancel.Size = [System.Drawing.Size]::new(105, 36)
    $dialog.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(568, 340)
    $save.Size = [System.Drawing.Size]::new(108, 36)
    $dialog.Controls.Add($save)

    $save.Add_Click({
        & $readControls
        $Config.notification = $workingNotification
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Close()
    })

    Apply-ThemeToForm -Form $dialog
    $dialog.AcceptButton = $save
    $dialog.CancelButton = $cancel

    $dialog.Add_Shown({
        Ensure-FormVisible -Form $dialog -CenterIfOffscreen
    })

    if ($null -eq $Owner) {
        [void]$dialog.ShowDialog($form)
    }
    else {
        [void]$dialog.ShowDialog($Owner)
    }

    if (-not $dialog.IsDisposed) { $dialog.Dispose() }
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

    $encoderLayerDialog = New-Object System.Windows.Forms.Form
    $encoderLayerDialog.Text = if ($script:Language -eq 'ru') { 'Энкодеры в слоях — Mugen Deej' } else { 'Layered encoders — Mugen Deej' }
    $encoderLayerDialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $encoderLayerDialog.ClientSize = [System.Drawing.Size]::new(720, 462)
    $encoderLayerDialog.MinimumSize = [System.Drawing.Size]::new(736, 501)
    $encoderLayerDialog.MaximumSize = [System.Drawing.Size]::new(736, 501)
    $encoderLayerDialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $encoderLayerDialog.MaximizeBox = $false
    $encoderLayerDialog.MinimizeBox = $false
    $encoderLayerDialog.Font = $form.Font
    Set-FormAppIcon -Form $encoderLayerDialog

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = if ($script:Language -eq 'ru') { 'Энкодер в слоях' } else { 'Encoder layer mappings' }
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $encoderLayerDialog.Controls.Add($heading)

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
    $encoderLayerDialog.Controls.Add($hint)

    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = if ($script:Language -eq 'ru') { 'Профиль:' } else { 'Profile:' }
    $profileLabel.Location = [System.Drawing.Point]::new(25, 111)
    $profileLabel.Size = [System.Drawing.Size]::new(80, 28)
    $profileLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $encoderLayerDialog.Controls.Add($profileLabel)

    $encoderLayerProfileCombo = New-Object MugenDeejWindowing.MugenComboBox
    $encoderLayerProfileCombo.DropDownStyle = 'DropDownList'
    $encoderLayerProfileCombo.Location = [System.Drawing.Point]::new(105, 109)
    $encoderLayerProfileCombo.Size = [System.Drawing.Size]::new(300, 30)
    $encoderLayerDialog.Controls.Add($encoderLayerProfileCombo)

    $encoderLayerProfileMap = New-Object System.Collections.ArrayList
    [void]$encoderLayerProfileCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Общий' } else { 'Global' }))
    [void]$encoderLayerProfileMap.Add('__global__')
    foreach ($profile in @($script:AdaptiveProfiles | Sort-Object name)) {
        $processName = Normalize-TargetName -Value ([string]$profile.process)
        if ([string]::IsNullOrWhiteSpace($processName)) { continue }
        [void]$encoderLayerProfileCombo.Items.Add(('{0} ({1}.exe)' -f [string]$profile.name, $processName))
        [void]$encoderLayerProfileMap.Add($processName.ToLowerInvariant())
    }
    $encoderLayerProfileCombo.SelectedIndex = 0

    $encoderLayerLayerCombo = New-Object MugenDeejWindowing.MugenComboBox
    $encoderLayerLayerCombo.DropDownStyle = 'DropDownList'
    $encoderLayerLayerCombo.Location = [System.Drawing.Point]::new(420, 109)
    $encoderLayerLayerCombo.Size = [System.Drawing.Size]::new(130, 30)
    Set-AdaptiveLayerComboDisplayItems -Combo $encoderLayerLayerCombo -Config $encoderLayerWorking
    $encoderLayerDialog.Controls.Add($encoderLayerLayerCombo)

    $encoderLayerEncoderCombo = New-Object MugenDeejWindowing.MugenComboBox
    $encoderLayerEncoderCombo.DropDownStyle = 'DropDownList'
    $encoderLayerEncoderCombo.Location = [System.Drawing.Point]::new(565, 109)
    $encoderLayerEncoderCombo.Size = [System.Drawing.Size]::new(130, 30)
    for ($i = 0; $i -lt $encoderCount; $i++) {
        [void]$encoderLayerEncoderCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Энкодер ' + ($i + 1) } else { 'Encoder ' + ($i + 1) }))
    }
    $encoderLayerEncoderCombo.SelectedIndex = 0
    $encoderLayerDialog.Controls.Add($encoderLayerEncoderCombo)

    $encoderLayerBaseLabel = New-Object System.Windows.Forms.Label
    $encoderLayerBaseLabel.ForeColor = [System.Drawing.Color]::DimGray
    $encoderLayerBaseLabel.Location = [System.Drawing.Point]::new(25, 154)
    $encoderLayerBaseLabel.Size = [System.Drawing.Size]::new(670, 52)
    $encoderLayerDialog.Controls.Add($encoderLayerBaseLabel)

    $encoderLayerLabels = @()
    $encoderLayerCombos = @()
    $encoderLayerMaps = @()
    $encoderLayerKinds = @('cw','ccw','push')
    $kindTitlesRu = @('По часовой', 'Против часовой', 'Нажатие')
    $kindTitlesEn = @('Clockwise', 'Counter-clockwise', 'Push')

    for ($i = 0; $i -lt 3; $i++) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $(if ($script:Language -eq 'ru') { $kindTitlesRu[$i] } else { $kindTitlesEn[$i] })
        $label.Location = [System.Drawing.Point]::new(25, (217 + ($i * 58)))
        $label.Size = [System.Drawing.Size]::new(145, 26)
        $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $encoderLayerDialog.Controls.Add($label)
        $encoderLayerLabels += $label

        $combo = New-Object MugenDeejWindowing.MugenComboBox
        $combo.Tag = $i
        $combo.DropDownStyle = 'DropDownList'
        $combo.Location = [System.Drawing.Point]::new(175, (215 + ($i * 58)))
        $combo.Size = [System.Drawing.Size]::new(520, 30)
        $encoderLayerDialog.Controls.Add($combo)
        $encoderLayerCombos += $combo
        $encoderLayerMaps += ,(New-Object System.Collections.ArrayList)
    }

    $encoderLayerState = [pscustomobject]@{ Suppress = $false }
    $encoderLayerDialog.Tag = [pscustomobject]@{
        TargetConfig = $Config
        WorkingConfig = $encoderLayerWorking
    }

    $encoderLayerGetContextKey = {
        $index = [int]$encoderLayerProfileCombo.SelectedIndex
        if ($index -lt 0 -or $index -ge $encoderLayerProfileMap.Count) { return '__global__' }
        return [string]$encoderLayerProfileMap[$index]
    }

    $encoderLayerRefresh = {
        $contextKey = & $encoderLayerGetContextKey
        $layer = [int]$encoderLayerLayerCombo.SelectedIndex + 1
        $encoderIndex = [int]$encoderLayerEncoderCombo.SelectedIndex
        if ($encoderIndex -lt 0) { $encoderIndex = 0 }

        $context = Get-AdaptiveLayerContextObject -Config $encoderLayerWorking -Key $contextKey -Create
        Ensure-AdaptiveLayerEncoderCapacity -Context $context -EncoderCount $encoderCount

        $baseCw = Get-AdaptiveLayerBaseEncoderAction -ContextKey $contextKey -EncoderIndex $encoderIndex -Kind 'cw'
        $baseCcw = Get-AdaptiveLayerBaseEncoderAction -ContextKey $contextKey -EncoderIndex $encoderIndex -Kind 'ccw'
        $basePush = Get-AdaptiveLayerBaseEncoderAction -ContextKey $contextKey -EncoderIndex $encoderIndex -Kind 'push'
        $encoderLayerBaseLabel.Text = if ($script:Language -eq 'ru') {
            'Основное: ↻ {0} · ↺ {1} · нажатие {2}' -f (Get-AdaptiveActionDisplay -Action $baseCw), (Get-AdaptiveActionDisplay -Action $baseCcw), (Get-AdaptiveActionDisplay -Action $basePush)
        }
        else {
            'Base: ↻ {0} · ↺ {1} · push {2}' -f (Get-AdaptiveActionDisplay -Action $baseCw), (Get-AdaptiveActionDisplay -Action $baseCcw), (Get-AdaptiveActionDisplay -Action $basePush)
        }

        $encoderLayerState.Suppress = $true
        try {
            for ($i = 0; $i -lt 3; $i++) {
                $override = Get-AdaptiveLayerEncoderOverride -Config $encoderLayerWorking -ContextKey $contextKey -Layer $layer -EncoderIndex $encoderIndex -Kind $encoderLayerKinds[$i]
                Populate-AdaptiveLayerTypedActionCombo -Combo $encoderLayerCombos[$i] -Map $encoderLayerMaps[$i] -CurrentAction $override
            }
        }
        finally {
            $encoderLayerState.Suppress = $false
        }

        $hasPush = $false
        if (@($script:LatestEncoders).Count -gt $encoderIndex) {
            $hasPush = [bool]$script:LatestEncoders[$encoderIndex].HasPush
        }
        $encoderLayerLabels[2].Visible = $hasPush
        $encoderLayerCombos[2].Visible = $hasPush
    }

    for ($comboIndex = 0; $comboIndex -lt 3; $comboIndex++) {
        $encoderLayerCombos[$comboIndex].Add_SelectedIndexChanged({
            param($sender, $eventArgs)

            if ($encoderLayerState.Suppress) { return }

            $slotIndex = [int]$sender.Tag
            $selectedIndex = [int]$sender.SelectedIndex
            if ($slotIndex -lt 0 -or $slotIndex -ge $encoderLayerMaps.Count) { return }
            if ($selectedIndex -lt 0 -or $selectedIndex -ge $encoderLayerMaps[$slotIndex].Count) { return }

            $contextKey = & $encoderLayerGetContextKey
            $layer = [int]$encoderLayerLayerCombo.SelectedIndex + 1
            $encoderIndex = [int]$encoderLayerEncoderCombo.SelectedIndex
            $kind = [string]$encoderLayerKinds[$slotIndex]
            $chosen = [string]$encoderLayerMaps[$slotIndex][$selectedIndex]
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

            & $encoderLayerRefresh
        })
    }

    $encoderLayerProfileCombo.Add_SelectedIndexChanged({ if (-not $encoderLayerState.Suppress) { & $encoderLayerRefresh } })
    $encoderLayerLayerCombo.Add_SelectedIndexChanged({ if (-not $encoderLayerState.Suppress) { & $encoderLayerRefresh } })
    $encoderLayerEncoderCombo.Add_SelectedIndexChanged({ if (-not $encoderLayerState.Suppress) { & $encoderLayerRefresh } })

    $encoderLayerCancel = New-Object MugenDeejWindowing.MugenButton
    $encoderLayerCancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $encoderLayerCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $encoderLayerCancel.Location = [System.Drawing.Point]::new(486, 408)
    $encoderLayerCancel.Size = [System.Drawing.Size]::new(98, 36)
    $encoderLayerDialog.Controls.Add($encoderLayerCancel)

    $encoderLayerSave = New-Object MugenDeejWindowing.MugenButton
    $encoderLayerSave.Text = Get-ButtonFeatureText -Key 'Save'
    $encoderLayerSave.Tag = 'MugenPrimary'
    $encoderLayerSave.Location = [System.Drawing.Point]::new(596, 408)
    $encoderLayerSave.Size = [System.Drawing.Size]::new(99, 36)
    $encoderLayerDialog.Controls.Add($encoderLayerSave)

    $encoderLayerSave.Add_Click({
        param($sender, $eventArgs)

        $ownerForm = $sender.FindForm()
        $editorState = $ownerForm.Tag
        $normalized = ConvertTo-NormalizedAdaptiveLayerConfig -Data $editorState.WorkingConfig
        $editorState.TargetConfig.contexts = @($normalized.contexts)
        $ownerForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $ownerForm.Close()
    })

    Apply-ThemeToForm -Form $encoderLayerDialog
    & $encoderLayerRefresh
    $encoderLayerDialog.AcceptButton = $encoderLayerSave
    $encoderLayerDialog.CancelButton = $encoderLayerCancel
    [void]$encoderLayerDialog.ShowDialog($Owner)
    if (-not $encoderLayerDialog.IsDisposed) { $encoderLayerDialog.Dispose() }
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
    $dialog.ClientSize = [System.Drawing.Size]::new(860, 814)
    $dialog.MinimumSize = [System.Drawing.Size]::new(876, 853)
    $dialog.MaximumSize = [System.Drawing.Size]::new(876, 853)
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

    $notificationSettingsButton = New-Object MugenDeejWindowing.MugenButton
    $notificationSettingsButton.Text = if ($script:Language -eq 'ru') { 'Уведомления…' } else { 'Notifications…' }
    $notificationSettingsButton.Location = [System.Drawing.Point]::new(650, 18)
    $notificationSettingsButton.Size = [System.Drawing.Size]::new(185, 32)
    $notificationSettingsButton.Add_Click({
        & $syncLayerNamesToWorking
        Show-AdaptiveLayerNotificationSettings -Config $working -Owner $dialog
    })
    $dialog.Controls.Add($notificationSettingsButton)

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
        & $syncLayerNamesToWorking
        Show-AdaptiveLayerEncoderSettings -Config $working -Owner $dialog
    })
    $modifierGroup.Controls.Add($encoderLayerButton)

    $namesGroup = New-Object MugenDeejWindowing.MugenGroupBox
    $namesGroup.Text = if ($script:Language -eq 'ru') { 'Имена слоёв' } else { 'Layer names' }
    $namesGroup.Location = [System.Drawing.Point]::new(22, 210)
    $namesGroup.Size = [System.Drawing.Size]::new(816, 94)
    $dialog.Controls.Add($namesGroup)

    $nameLabelsRu = @('Основной', 'T1', 'T2', 'T1 + T2')
    $nameLabelsEn = @('Base', 'T1', 'T2', 'T1 + T2')
    $layerNameBoxes = @()

    for ($layerNameIndex = 0; $layerNameIndex -lt 4; $layerNameIndex++) {
        $columnX = 16 + ($layerNameIndex * 198)

        $nameLabel = New-Object System.Windows.Forms.Label
        $nameLabel.Text = if ($script:Language -eq 'ru') { $nameLabelsRu[$layerNameIndex] } else { $nameLabelsEn[$layerNameIndex] }
        $nameLabel.Location = [System.Drawing.Point]::new($columnX, 24)
        $nameLabel.Size = [System.Drawing.Size]::new(178, 20)
        $namesGroup.Controls.Add($nameLabel)

        $nameBox = New-Object System.Windows.Forms.TextBox
        $nameBox.Tag = $layerNameIndex
        $nameBox.MaxLength = 24
        $nameBox.Location = [System.Drawing.Point]::new($columnX, 48)
        $nameBox.Size = [System.Drawing.Size]::new(178, 25)
        $nameBox.Text = Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer $layerNameIndex
        $namesGroup.Controls.Add($nameBox)
        $layerNameBoxes += $nameBox
    }

    $syncLayerNamesToWorking = {
        foreach ($nameBox in $layerNameBoxes) {
            $layerIndex = [int]$nameBox.Tag
            $key = Get-AdaptiveLayerCustomNameKey -Layer $layerIndex
            $value = ConvertTo-SafeAdaptiveLayerCustomName -Value ([string]$nameBox.Text)
            $defaultValue = Get-AdaptiveLayerDefaultDisplayName -Layer $layerIndex

            if ($value -eq $defaultValue) {
                $working.names.$key = ''
            }
            else {
                $working.names.$key = $value
            }
        }
    }

    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = if ($script:Language -eq 'ru') { 'Профиль:' } else { 'Profile:' }
    $profileLabel.Location = [System.Drawing.Point]::new(25, 328)
    $profileLabel.Size = [System.Drawing.Size]::new(100, 28)
    $profileLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $dialog.Controls.Add($profileLabel)

    $profileCombo = New-Object MugenDeejWindowing.MugenComboBox
    $profileCombo.DropDownStyle = 'DropDownList'
    $profileCombo.Location = [System.Drawing.Point]::new(125, 326)
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
    $layerLabel.Location = [System.Drawing.Point]::new(558, 328)
    $layerLabel.Size = [System.Drawing.Size]::new(70, 28)
    $layerLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $dialog.Controls.Add($layerLabel)

    $layerCombo = New-Object MugenDeejWindowing.MugenComboBox
    $layerCombo.DropDownStyle = 'DropDownList'
    $layerCombo.Location = [System.Drawing.Point]::new(625, 326)
    $layerCombo.Size = [System.Drawing.Size]::new(210, 30)
    Set-AdaptiveLayerComboDisplayItems -Combo $layerCombo -Config $working
    $dialog.Controls.Add($layerCombo)

    $editorGroup = New-Object MugenDeejWindowing.MugenGroupBox
    $editorGroup.Text = if ($script:Language -eq 'ru') { 'Переопределения кнопок' } else { 'Button overrides' }
    $editorGroup.Location = [System.Drawing.Point]::new(22, 370)
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
        '«Наследовать» = основное назначение; «Не использовать» = отключить в этом слое.' + "`r`n" +
        'Обычные действия — один раз при нажатии; Xbox — удерживается вместе с кнопкой.'
    }
    else {
        'Inherit = base mapping; Do nothing = disable only in this layer.' + "`r`n" +
        'Regular actions fire once per press; Xbox stays held with the physical button.'
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

    $layerButtonState = [pscustomobject]@{
        Selected = 0
        Suppress = $false
        ActionMap = New-Object System.Collections.ArrayList
        LastButtons = @($script:LatestButtons)
    }
    $refreshSelectorTiles = {
        $palette = $script:ThemePalettes[[string](Get-EffectiveTheme)]
        $latest = @($script:LatestButtons)

        for ($tileIndex = 0; $tileIndex -lt $selectors.Count; $tileIndex++) {
            $tile = $selectors[$tileIndex]
            if ($null -eq $tile -or $tile.IsDisposed) { continue }

            $isPressed = (
                $tileIndex -lt $latest.Count -and
                [int]$latest[$tileIndex] -eq 0
            )
            $isSelected = ($tileIndex -eq [int]$layerButtonState.Selected)

            # MugenButtonTile owns the semantic selected/pressed state and paints
            # it internally. External invalidations can no longer temporarily
            # restore normal BackColor/BorderColor between 40 ms timer ticks.
            $tile.ApplySemanticStateTheme(
                $palette.Control,
                $palette.Text,
                $palette.Border,
                $palette.Accent,
                $palette.AccentText,
                $palette.Accent,
                $isSelected,
                $isPressed
            )
        }
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
        $index = [int]$layerButtonState.Selected
        $contextKey = & $getContextKey
        $layer = & $getLayer

        $context = Get-AdaptiveLayerContextObject -Config $working -Key $contextKey -Create
        Ensure-AdaptiveLayerContextCapacity -Context $context -ButtonCount $buttonCount

        $baseAction = Get-AdaptiveLayerBaseButtonAction -ContextKey $contextKey -ButtonIndex $index
        $override = Get-AdaptiveLayerButtonOverride -Config $working -ContextKey $contextKey -Layer $layer -ButtonIndex $index

        $selectedHeading.Text = if ($script:Language -eq 'ru') {
            'Кнопка {0} · слой {1}' -f ($index + 1), (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer $layer)
        }
        else {
            'Button {0} · layer {1}' -f ($index + 1), (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer $layer)
        }

        $baseLabel.Text = if ($script:Language -eq 'ru') {
            'Основное действие: ' + (Get-LargeButtonActionDisplay -Action $baseAction)
        }
        else {
            'Base action: ' + (Get-LargeButtonActionDisplay -Action $baseAction)
        }

        $layerButtonState.Suppress = $true
        try {
            Populate-AdaptiveLayerButtonActionCombo -Combo $actionCombo -Map $layerButtonState.ActionMap -CurrentAction $override
        }
        finally {
            $layerButtonState.Suppress = $false
        }

        $currentLayer = Get-AdaptiveLayerIndex
        $activePreview.Text = if ($script:Language -eq 'ru') {
            'Сейчас на контроллере: слой ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer $currentLayer)
        }
        else {
            'Controller now: layer ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer $currentLayer)
        }
    }

    $selectButton = {
        param([int]$Index)

        if ($Index -lt 0 -or $Index -ge $buttonCount) { return }
        $layerButtonState.Selected = $Index
        & $refreshEditor
        & $refreshSelectorTiles
    }

    foreach ($selector in $selectors) {
        $selector.Add_Click({
            param($sender, $eventArgs)
            & $selectButton -Index ([int]$sender.Tag)
        })
    }

    $refreshLayerNames = {
        & $syncLayerNamesToWorking

        Set-AdaptiveLayerComboDisplayItems -Combo $layerCombo -Config $working

        $t1Check.Text = if ($script:Language -eq 'ru') {
            'Тумблер 1 = слой ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer 1)
        }
        else {
            'Toggle 1 = layer ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer 1)
        }

        $t2Check.Text = if ($script:Language -eq 'ru') {
            'Тумблер 2 = слой ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer 2)
        }
        else {
            'Toggle 2 = layer ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer 2)
        }

        & $refreshEditor
    }

    foreach ($nameBox in $layerNameBoxes) {
        $nameBox.Add_TextChanged({
            if (-not $layerButtonState.Suppress) {
                & $refreshLayerNames
            }
        })
    }

    $profileCombo.Add_SelectedIndexChanged({
        if (-not $layerButtonState.Suppress) { & $refreshEditor }
    })
    $layerCombo.Add_SelectedIndexChanged({
        if (-not $layerButtonState.Suppress) { & $refreshEditor }
    })

    $actionCombo.Add_SelectedIndexChanged({
        if ($layerButtonState.Suppress) { return }

        $selectedIndex = [int]$actionCombo.SelectedIndex
        if ($selectedIndex -lt 0 -or $selectedIndex -ge $layerButtonState.ActionMap.Count) { return }

        $selectedAction = [string]$layerButtonState.ActionMap[$selectedIndex]
        $index = [int]$layerButtonState.Selected
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
    $cancel.Location = [System.Drawing.Point]::new(610, 760)
    $cancel.Size = [System.Drawing.Size]::new(105, 36)
    $dialog.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(727, 760)
    $save.Size = [System.Drawing.Size]::new(108, 36)
    $dialog.Controls.Add($save)

    $save.Add_Click({
        & $syncLayerNamesToWorking

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
        $compareCount = [Math]::Min($latest.Count, @($layerButtonState.LastButtons).Count)
        for ($i = 0; $i -lt $compareCount; $i++) {
            if ([int]$latest[$i] -eq 0 -and [int]$layerButtonState.LastButtons[$i] -ne 0) {
                & $selectButton -Index $i
                break
            }
        }
        $layerButtonState.LastButtons = @($latest)
        & $refreshSelectorTiles

        $currentLayer = Get-AdaptiveLayerIndex
        $preview = if ($script:Language -eq 'ru') {
            'Сейчас на контроллере: слой ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer $currentLayer)
        }
        else {
            'Controller now: layer ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer $currentLayer)
        }
        if ($activePreview.Text -ne $preview) {
            $activePreview.Text = $preview
        }
    })

    Apply-ThemeToForm -Form $dialog
    & $refreshLayerNames
    & $refreshSelectorTiles

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

        Show-AdaptiveLayerNotification -Layer $newLayer

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
        $script:ToggleStateLabel.Text = Get-AdaptiveInputUiText -Key 'Toggles'
        $script:ToggleStateLabel.Visible = ($metrics.ToggleCount -gt 0)
    }

    if (
        ($null -eq $script:LayerStateLabel -or $script:LayerStateLabel.IsDisposed) -and
        $null -ne $script:ButtonStateGroup -and
        -not $script:ButtonStateGroup.IsDisposed
    ) {
        $script:LayerStateLabel = New-Object System.Windows.Forms.Label
        $script:LayerStateLabel.Name = 'AdaptiveLayerStateLabel'
        $script:LayerStateLabel.AutoSize = $false
        $script:LayerStateLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
        $script:LayerStateLabel.Size = [System.Drawing.Size]::new(606, 22)
        $script:ButtonStateGroup.Controls.Add($script:LayerStateLabel)
    }

    if ($null -ne $script:LayerStateLabel -and -not $script:LayerStateLabel.IsDisposed) {
        $layersEnabled = Test-AdaptiveLayersEnabled
        $script:LayerStateLabel.Visible = $layersEnabled
        if ($layersEnabled) {
            $layerName = Get-AdaptiveLayerDisplayName -Layer (Get-AdaptiveLayerIndex)
            $script:LayerStateLabel.Text = if ($script:Language -eq 'ru') {
                'Активный слой: ' + $layerName
            }
            else {
                'Active layer: ' + $layerName
            }
            $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
            $script:LayerStateLabel.ForeColor = $palette.Accent
            $script:LayerStateLabel.BackColor = $script:ButtonStateGroup.BackColor
        }
    }
'@
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText $toggleHeadingOld -NewText $toggleHeadingNew -Label 'show active Adaptive layer in live status'

$layerStatusLayoutOld = @'
    if ($adaptiveMetrics.HasControls) {
        $shareTypedRow = (
'@
$layerStatusLayoutNew = @'
    if (
        $null -ne $script:LayerStateLabel -and
        -not $script:LayerStateLabel.IsDisposed -and
        (Test-AdaptiveLayersEnabled)
    ) {
        $script:LayerStateLabel.Location = [System.Drawing.Point]::new(13, ($cursorY + 1))
        $script:LayerStateLabel.Size = [System.Drawing.Size]::new(606, 22)
        $cursorY += 24
    }

    if ($adaptiveMetrics.HasControls) {
        $shareTypedRow = (
'@
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText $layerStatusLayoutOld -NewText $layerStatusLayoutNew -Label 'reserve main status row for active Adaptive layer'

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
    $profileHint.Location = [System.Drawing.Point]::new(25, 176)
    $profileHint.Size = [System.Drawing.Size]::new(770, 30)
    $settingsForm.Controls.Add($profileHint)

    $layerSettingsButton = New-Object MugenDeejWindowing.MugenButton
    $layerSettingsButton.Text = if ($script:Language -eq 'ru') { 'Слои управления…' } else { 'Control layers…' }
    $layerSettingsButton.Location = [System.Drawing.Point]::new(25, 211)
    $layerSettingsButton.Size = [System.Drawing.Size]::new(220, 32)
    $layerSettingsButton.Enabled = ([string]$script:ControllerProtocol -eq 'adaptive' -and [int]$script:DetectedToggleCount -gt 0 -and [int]$script:DetectedButtonCount -gt 0)
    $layerSettingsButton.Add_Click({
        Show-AdaptiveLayerSettings

        # Control layers are saved directly into the live Adaptive layer config.
        # Refresh this parent editor immediately after the child dialog closes so
        # modifier roles and disabled ON/OFF actions never stay visually stale
        # until some later click/toggle/encoder event happens to refresh them.
        & $refreshEditor
        & $refreshAssignmentList
    })
    $settingsForm.Controls.Add($layerSettingsButton)

    $layerSettingsHint = New-Object System.Windows.Forms.Label
    $layerSettingsHint.Text = if ($script:Language -eq 'ru') {
        'T1/T2 как модификаторы: отдельные назначения кнопок и энкодера.'
    }
    else {
        'Use T1/T2 as modifiers for alternate button and encoder mappings.'
    }
    $layerSettingsHint.ForeColor = [System.Drawing.Color]::DimGray
    $layerSettingsHint.Location = [System.Drawing.Point]::new(260, 215)
    $layerSettingsHint.Size = [System.Drawing.Size]::new(535, 28)
    $settingsForm.Controls.Add($layerSettingsHint)

    $selectorGroup = New-Object MugenDeejWindowing.MugenGroupBox
'@
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText $profileHintOld -NewText $profileHintNew -Label 'add layer editor entry point to Adaptive settings'

# The new layer row is a first-class section, not a button glued to the profile
# Add button. Shift the editor body and action row down together.
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText @'
    $settingsForm.ClientSize = [System.Drawing.Size]::new(820, 796)
    $settingsForm.MinimumSize = [System.Drawing.Size]::new(836, 835)
    $settingsForm.MaximumSize = [System.Drawing.Size]::new(836, 835)
'@ -NewText @'
    $settingsForm.ClientSize = [System.Drawing.Size]::new(820, 846)
    $settingsForm.MinimumSize = [System.Drawing.Size]::new(836, 885)
    $settingsForm.MaximumSize = [System.Drawing.Size]::new(836, 885)
'@ -Label 'make room for Adaptive layer settings row'

$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText @'
    $selectorGroup.Location = [System.Drawing.Point]::new(22, 202)
'@ -NewText @'
    $selectorGroup.Location = [System.Drawing.Point]::new(22, 252)
'@ -Label 'move Adaptive selector group below layer row'

$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText @'
    $editorGroup.Location = [System.Drawing.Point]::new(282, 202)
'@ -NewText @'
    $editorGroup.Location = [System.Drawing.Point]::new(282, 252)
'@ -Label 'move Adaptive editor group below layer row'

$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText @'
    $cancel.Location = [System.Drawing.Point]::new(580, 744)
'@ -NewText @'
    $cancel.Location = [System.Drawing.Point]::new(580, 794)
'@ -Label 'move Adaptive cancel button below shifted editor'

$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText @'
    $save.Location = [System.Drawing.Point]::new(692, 744)
'@ -NewText @'
    $save.Location = [System.Drawing.Point]::new(692, 794)
'@ -Label 'move Adaptive save button below shifted editor'

$toggleEditorOld = @'
            if ($state.Kind -eq 't') {
                $selectedHeading.Text = if ($script:Language -eq 'ru') { 'Тумблер ' + ($index + 1) } else { 'Toggle ' + ($index + 1) }
                $row1Label.Text = if ($script:Language -eq 'ru') { 'При включении' } else { 'When switched ON' }
                $row2Label.Text = if ($script:Language -eq 'ru') { 'При выключении' } else { 'When switched OFF' }
                $row3Label.Visible = $false
                $row3Combo.Visible = $false
                Populate-AdaptiveActionCombo -Combo $row1Combo -Map $state.Map1 -CurrentAction (& $getCurrentAction '1')
                Populate-AdaptiveActionCombo -Combo $row2Combo -Map $state.Map2 -CurrentAction (& $getCurrentAction '2')
            }
            else {
'@
$toggleEditorNew = @'
            if ($state.Kind -eq 't') {
                $isLayerModifier = Test-AdaptiveToggleIsLayerModifier -Index $index
                $modifierLayer = if ($index -eq 0) { 1 } elseif ($index -eq 1) { 2 } else { 0 }
                $modifierLayerName = if ($modifierLayer -gt 0) {
                    Get-AdaptiveLayerDisplayName -Layer $modifierLayer
                }
                else { '' }

                $selectedHeading.Text = if ($script:Language -eq 'ru') {
                    'Тумблер ' + ($index + 1) + $(if ($isLayerModifier) { ' · модификатор «' + $modifierLayerName + '»' } else { '' })
                }
                else {
                    'Toggle ' + ($index + 1) + $(if ($isLayerModifier) { ' · layer modifier ' + $modifierLayerName } else { '' })
                }

                $row1Label.Text = if ($script:Language -eq 'ru') { 'При включении' } else { 'When switched ON' }
                $row2Label.Text = if ($script:Language -eq 'ru') { 'При выключении' } else { 'When switched OFF' }
                $row3Label.Visible = $false
                $row3Combo.Visible = $false

                Populate-AdaptiveActionCombo -Combo $row1Combo -Map $state.Map1 -CurrentAction (& $getCurrentAction '1')
                Populate-AdaptiveActionCombo -Combo $row2Combo -Map $state.Map2 -CurrentAction (& $getCurrentAction '2')

                $row1Combo.Enabled = (-not $isLayerModifier)
                $row2Combo.Enabled = (-not $isLayerModifier)

                $editorHint.Text = if ($isLayerModifier) {
                    if ($script:Language -eq 'ru') {
                        'Переключает слой «' + $modifierLayerName + '». Обычные действия ВКЛ/ВЫКЛ отключены. Роль меняется в «Слои управления…».'
                    }
                    else {
                        'This toggle selects the “' + $modifierLayerName + '” layer. Its normal ON/OFF actions are suppressed. Change its role in Control layers…'
                    }
                }
                else {
                    if ($script:Language -eq 'ru') {
                        'Для обычного тумблера можно отдельно назначить действие при включении и выключении.'
                    }
                    else {
                        'A normal toggle can have separate actions for ON and OFF.'
                    }
                }
            }
            else {
                $row1Combo.Enabled = $true
                $row2Combo.Enabled = $true
'@
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText $toggleEditorOld -NewText $toggleEditorNew -Label 'explain disabled ordinary actions for layer modifier toggles'

$encoderHintOld = @'
                $row3Label.Visible = $hasPush
                $row3Combo.Visible = $hasPush
                Populate-AdaptiveActionCombo -Combo $row1Combo -Map $state.Map1 -CurrentAction (& $getCurrentAction '1')
'@
$encoderHintNew = @'
                $row3Label.Visible = $hasPush
                $row3Combo.Visible = $hasPush
                $row3Combo.Enabled = $true
                $editorHint.Text = if ($script:Language -eq 'ru') {
                    'Поворот выполняет назначенное действие на каждом шаге. Точка • означает отдельное действие по нажатию.'
                }
                else {
                    'Each encoder step runs the assigned action once. A • means the encoder can also be pressed.'
                }
                Populate-AdaptiveActionCombo -Combo $row1Combo -Map $state.Map1 -CurrentAction (& $getCurrentAction '1')
'@
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText $encoderHintOld -NewText $encoderHintNew -Label 'restore encoder help after selecting a layer modifier toggle'

$liveToggleOld = @'
        if ($state.Kind -eq 't') {
            $isOn = (@($script:LatestToggles).Count -gt [int]$state.Index -and [int]$script:LatestToggles[[int]$state.Index] -eq 1)
            $liveState.Text = if ($script:Language -eq 'ru') { 'Сейчас: ' + $(if ($isOn) { 'ВКЛ' } else { 'ВЫКЛ' }) } else { 'Now: ' + $(if ($isOn) { 'ON' } else { 'OFF' }) }
        }
'@
$liveToggleNew = @'
        if ($state.Kind -eq 't') {
            $toggleIndex = [int]$state.Index
            $isOn = (@($script:LatestToggles).Count -gt $toggleIndex -and [int]$script:LatestToggles[$toggleIndex] -eq 1)
            $isLayerModifier = Test-AdaptiveToggleIsLayerModifier -Index $toggleIndex

            $liveState.Text = if ($script:Language -eq 'ru') {
                'Состояние: ' + $(if ($isOn) { 'ВКЛ' } else { 'ВЫКЛ' }) + $(if ($isLayerModifier) { ' · роль: модификатор слоя' } else { '' })
            }
            else {
                'Now: ' + $(if ($isOn) { 'ON' } else { 'OFF' }) + $(if ($isLayerModifier) { ' · layer modifier' } else { '' })
            }
        }
'@
$text = Replace-LayerLiteralExactlyOnce -Text $text -OldText $liveToggleOld -NewText $liveToggleNew -Label 'show layer-modifier role in toggle live status'

[System.IO.File]::WriteAllText($resolved, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Applied Adaptive toggle-layer mappings to staged runtime: $resolved"
