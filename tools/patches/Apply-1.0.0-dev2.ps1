param(
    [Parameter(Mandatory = $true)][string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$dev1Patch = Join-Path $PSScriptRoot 'Apply-1.0.0-dev1.ps1'
if (-not (Test-Path -LiteralPath $dev1Patch -PathType Leaf)) {
    throw "Required dev1 patch was not found: $dev1Patch"
}

& $dev1Patch -Path $Path

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

$text = Replace-ExactOnce -Text $text -Old '# Mugen Deej 1.0.0-dev1' -New '# Mugen Deej 1.0.0-dev2' -Label 'header version'
$text = Replace-ExactOnce -Text $text -Old '$script:AppVersion = ''1.0.0-dev1''' -New '$script:AppVersion = ''1.0.0-dev2''' -Label 'runtime version'

$oldRu = @'
        DiagnosticsOpen = 'Подключение и диагностика ▲'
'@
$newRu = @'
        DiagnosticsOpen = 'Подключение и диагностика ▲'
        BackupMenu = 'Резервная копия ▼'
        BackupCreate = 'Создать резервную копию…'
        BackupRestore = 'Восстановить из резервной копии…'
        BackupSaveTitle = 'Создание резервной копии Mugen Deej'
        BackupOpenTitle = 'Восстановление резервной копии Mugen Deej'
        BackupCreated = 'Резервная копия создана:'
        BackupRestoreConfirm = 'Текущие настройки будут заменены настройками из резервной копии. Перед восстановлением Mugen Deej автоматически сохранит аварийную копию текущих настроек. Продолжить?'
        BackupRestored = 'Настройки восстановлены. Перезапустите Mugen Deej, чтобы применить их полностью.'
        BackupInvalid = 'Не удалось прочитать резервную копию:'
        BackupRestoreFailed = 'Не удалось восстановить настройки:'
'@
$text = Replace-ExactOnce -Text $text -Old ($oldRu.TrimEnd()) -New ($newRu.TrimEnd()) -Label 'RU backup localization'

$oldEn = @'
        DiagnosticsOpen = 'Connection and diagnostics ▲'
'@
$newEn = @'
        DiagnosticsOpen = 'Connection and diagnostics ▲'
        BackupMenu = 'Backup & restore ▼'
        BackupCreate = 'Create backup…'
        BackupRestore = 'Restore from backup…'
        BackupSaveTitle = 'Create Mugen Deej backup'
        BackupOpenTitle = 'Restore Mugen Deej backup'
        BackupCreated = 'Backup created:'
        BackupRestoreConfirm = 'Current settings will be replaced with settings from the backup. Before restoring, Mugen Deej will automatically save an emergency copy of the current settings. Continue?'
        BackupRestored = 'Settings restored. Restart Mugen Deej to apply them completely.'
        BackupInvalid = 'Could not read the backup:'
        BackupRestoreFailed = 'Could not restore settings:'
'@
$text = Replace-ExactOnce -Text $text -Old ($oldEn.TrimEnd()) -New ($newEn.TrimEnd()) -Label 'EN backup localization'

$text = Replace-ExactOnce -Text $text -Old '$script:ButtonSettingsButton = $null' -New @'
$script:ButtonSettingsButton = $null
$script:BackupMenuButton = $null
'@.TrimEnd() -Label 'backup menu runtime variable'

$backupFunctions = @'
function Get-MugenDeejBackupFileName {
    return ('MugenDeej_{0}.backup' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
}

function Read-MugenDeejBackupFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $data) {
        throw 'Backup file is empty.'
    }
    if ([string]$data.format -cne 'MugenDeejBackup') {
        throw 'This file is not a Mugen Deej backup.'
    }
    if ($null -eq $data.PSObject.Properties['schemaVersion']) {
        throw 'Backup schema version is missing.'
    }
    if ([int]$data.schemaVersion -ne 1) {
        throw ('Unsupported backup schema version: {0}' -f $data.schemaVersion)
    }
    if ($null -eq $data.PSObject.Properties['config'] -or $null -eq $data.config) {
        throw 'Backup does not contain the main configuration.'
    }
    if ($null -eq $data.PSObject.Properties['buttonActions'] -or $null -eq $data.buttonActions) {
        throw 'Backup does not contain button actions.'
    }
    if ($null -eq $data.buttonActions.PSObject.Properties['version'] -or [int]$data.buttonActions.version -ne 1) {
        throw 'Unsupported or missing button-action configuration version in backup.'
    }
    if ($null -eq $data.buttonActions.PSObject.Properties['actions']) {
        throw 'Backup button-action list is missing.'
    }

    foreach ($item in @($data.buttonActions.actions)) {
        if ($null -eq $item) {
            throw 'Backup button-action list contains a null item.'
        }
    }

    return $data
}

function New-MugenDeejBackupSnapshot {
    Initialize-ButtonActions

    $configClone = $script:Config | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $actions = @($script:ButtonActions | ForEach-Object { [string]$_ })

    return [pscustomobject][ordered]@{
        format = 'MugenDeejBackup'
        schemaVersion = 1
        createdAt = (Get-Date).ToString('o')
        createdBy = $script:AppVersion
        config = $configClone
        buttonActions = [pscustomobject][ordered]@{
            version = 1
            actions = @($actions)
        }
    }
}

function Write-MugenDeejBackupFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Snapshot
    )

    $tempPath = "$Path.tmp-$PID"
    try {
        $json = $Snapshot | ConvertTo-Json -Depth 16
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tempPath, $json, $utf8NoBom)

        [void](Read-MugenDeejBackupFile -Path $tempPath)

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

        [void](Read-MugenDeejBackupFile -Path $Path)
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Save-MugenDeejBackupInteractive {
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = (T -Key 'BackupSaveTitle')
    $dialog.Filter = 'Mugen Deej backup (*.backup)|*.backup|All files (*.*)|*.*'
    $dialog.DefaultExt = 'backup'
    $dialog.AddExtension = $true
    $dialog.OverwritePrompt = $true
    $dialog.FileName = Get-MugenDeejBackupFileName

    if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    try {
        $snapshot = New-MugenDeejBackupSnapshot
        Write-MugenDeejBackupFile -Path $dialog.FileName -Snapshot $snapshot
        Write-Log ('Portable backup created: {0}' -f $dialog.FileName) 'INFO'

        [System.Windows.Forms.MessageBox]::Show(
            $form,
            ((T -Key 'BackupCreated') + "`r`n`r`n" + $dialog.FileName),
            'Mugen Deej',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {
        Write-Log ('Backup creation failed: {0}' -f $_.Exception.Message) 'ERROR'
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            ((T -Key 'BackupRestoreFailed') + "`r`n`r`n" + $_.Exception.Message),
            'Mugen Deej',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

function Restore-MugenDeejBackupInteractive {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = (T -Key 'BackupOpenTitle')
    $dialog.Filter = 'Mugen Deej backup (*.backup)|*.backup|All files (*.*)|*.*'
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false

    if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    try {
        $backup = Read-MugenDeejBackupFile -Path $dialog.FileName
    }
    catch {
        Write-Log ('Backup validation failed: {0}' -f $_.Exception.Message) 'WARN'
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            ((T -Key 'BackupInvalid') + "`r`n`r`n" + $_.Exception.Message),
            'Mugen Deej',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    $confirmation = [System.Windows.Forms.MessageBox]::Show(
        $form,
        (T -Key 'BackupRestoreConfirm'),
        'Mugen Deej',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    Initialize-ButtonActions
    $preRestoreSnapshot = New-MugenDeejBackupSnapshot
    $preRestorePath = Join-Path $script:BaseDir ('MugenDeej_PreRestore_{0}.backup' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))

    try {
        Write-MugenDeejBackupFile -Path $preRestorePath -Snapshot $preRestoreSnapshot
    }
    catch {
        Write-Log ('Restore aborted because emergency backup could not be created: {0}' -f $_.Exception.Message) 'ERROR'
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            ((T -Key 'BackupRestoreFailed') + "`r`n`r`n" + $_.Exception.Message),
            'Mugen Deej',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    try {
        $configClone = $backup.config | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $restoredConfig = Ensure-ConfigShape -Config $configClone
        $restoredActions = @($backup.buttonActions.actions | ForEach-Object { [string]$_ })

        Save-Config -Config $restoredConfig
        Write-ButtonActionConfigFile -Path $script:ButtonActionConfigPath -Actions $restoredActions

        $script:Config = $restoredConfig
        $script:ButtonActions = @($restoredActions)
        $script:ButtonActionsLoaded = $true

        Write-Log ('Settings restored from backup: {0}; emergencyBackup={1}' -f $dialog.FileName, $preRestorePath) 'INFO'
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            ((T -Key 'BackupRestored') + "`r`n`r`n" + $preRestorePath),
            'Mugen Deej',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {
        $restoreError = $_.Exception.Message
        Write-Log ('Restore failed; attempting rollback from emergency backup: {0}' -f $restoreError) 'ERROR'

        try {
            $rollback = Read-MugenDeejBackupFile -Path $preRestorePath
            $rollbackConfigClone = $rollback.config | ConvertTo-Json -Depth 12 | ConvertFrom-Json
            $rollbackConfig = Ensure-ConfigShape -Config $rollbackConfigClone
            $rollbackActions = @($rollback.buttonActions.actions | ForEach-Object { [string]$_ })

            Save-Config -Config $rollbackConfig
            Write-ButtonActionConfigFile -Path $script:ButtonActionConfigPath -Actions $rollbackActions
            $script:Config = $rollbackConfig
            $script:ButtonActions = @($rollbackActions)
            $script:ButtonActionsLoaded = $true
            Write-Log 'Rollback after failed restore completed successfully.' 'WARN'
        }
        catch {
            Write-Log ('Rollback after failed restore also failed: {0}' -f $_.Exception.Message) 'ERROR'
        }

        [System.Windows.Forms.MessageBox]::Show(
            $form,
            ((T -Key 'BackupRestoreFailed') + "`r`n`r`n" + $restoreError),
            'Mugen Deej',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

function Show-MugenDeejBackupMenu {
    param([Parameter(Mandatory = $true)]$OwnerControl)

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $createItem = $menu.Items.Add((T -Key 'BackupCreate'))
    $restoreItem = $menu.Items.Add((T -Key 'BackupRestore'))

    $createItem.Add_Click({ Save-MugenDeejBackupInteractive })
    $restoreItem.Add_Click({ Restore-MugenDeejBackupInteractive })

    try {
        Apply-ToolStripTheme -ToolStrip $menu -ThemeName (Get-EffectiveTheme)
    }
    catch { }

    $menu.Show($OwnerControl, (New-Object System.Drawing.Point(0, $OwnerControl.Height)))
}

'@
$text = Replace-ExactOnce -Text $text -Old 'function Get-MuteStatusColor {' -New ($backupFunctions + 'function Get-MuteStatusColor {') -Label 'backup function insertion point'

$oldMainButton = @'
$form.Controls.Add($advancedToggle)

$advancedPanel = New-Object System.Windows.Forms.Panel
'@
$newMainButton = @'
$form.Controls.Add($advancedToggle)

$backupMenuButton = New-Object MugenDeejWindowing.MugenButton
$backupMenuButton.Tag = 'MugenSection'
$backupMenuButton.Text = (T -Key 'BackupMenu')
$backupMenuButton.Location = New-Object System.Drawing.Point(292, 516)
$backupMenuButton.Size = New-Object System.Drawing.Size(250, 32)
$form.Controls.Add($backupMenuButton)
$script:BackupMenuButton = $backupMenuButton

$advancedPanel = New-Object System.Windows.Forms.Panel
'@
$text = Replace-ExactOnce -Text $text -Old ($oldMainButton.TrimEnd()) -New ($newMainButton.TrimEnd()) -Label 'main backup button'

$oldLayout = '$advancedToggle.Location = [System.Drawing.Point]::new(24, (516 + $offset))'
$newLayout = @'
$advancedToggle.Location = [System.Drawing.Point]::new(24, (516 + $offset))
    if ($null -ne $script:BackupMenuButton -and -not $script:BackupMenuButton.IsDisposed) {
        $script:BackupMenuButton.Location = [System.Drawing.Point]::new(292, (516 + $offset))
    }
'@
$text = Replace-ExactOnce -Text $text -Old $oldLayout -New ($newLayout.TrimEnd()) -Label 'backup button responsive layout'

$oldLocalization = @'
    $trayExit.Text = (T -Key 'TrayExit')
    Set-AdvancedExpanded -Expanded $advancedPanel.Visible -Persist $false
'@
$newLocalization = @'
    $trayExit.Text = (T -Key 'TrayExit')
    if ($null -ne $script:BackupMenuButton -and -not $script:BackupMenuButton.IsDisposed) {
        $script:BackupMenuButton.Text = (T -Key 'BackupMenu')
    }
    Set-AdvancedExpanded -Expanded $advancedPanel.Visible -Persist $false
'@
$text = Replace-ExactOnce -Text $text -Old ($oldLocalization.TrimEnd()) -New ($newLocalization.TrimEnd()) -Label 'backup button localization refresh'

$oldClick = '$advancedToggle.Add_Click({ Set-AdvancedExpanded -Expanded (-not $advancedPanel.Visible) })'
$newClick = @'
$backupMenuButton.Add_Click({ Show-MugenDeejBackupMenu -OwnerControl $backupMenuButton })
$advancedToggle.Add_Click({ Set-AdvancedExpanded -Expanded (-not $advancedPanel.Visible) })
'@
$text = Replace-ExactOnce -Text $text -Old $oldClick -New ($newClick.TrimEnd()) -Label 'backup menu click handler'

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($Path, $text, $utf8Bom)

Write-Host 'Applied Mugen Deej 1.0.0-dev2 backup/restore patch.'
