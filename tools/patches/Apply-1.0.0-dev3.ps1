param(
    [Parameter(Mandatory = $true)][string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$dev2Patch = Join-Path $PSScriptRoot 'Apply-1.0.0-dev2.ps1'
if (-not (Test-Path -LiteralPath $dev2Patch -PathType Leaf)) {
    throw "Required dev2 patch was not found: $dev2Patch"
}

& $dev2Patch -Path $Path

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

function Replace-BlockBetween {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$StartMarker,
        [Parameter(Mandatory = $true)][string]$EndMarker,
        [Parameter(Mandatory = $true)][string]$Replacement,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) {
        throw "Block start marker was not found: $Label"
    }

    $startAgain = $Text.IndexOf($StartMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($startAgain -ge 0) {
        throw "Block start marker is not unique: $Label"
    }

    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($end -lt 0) {
        throw "Block end marker was not found: $Label"
    }

    return $Text.Substring(0, $start) + $Replacement + $Text.Substring($end)
}

$text = Replace-ExactOnce -Text $text -Old '# Mugen Deej 1.0.0-dev2' -New '# Mugen Deej 1.0.0-dev3' -Label 'header version'
$text = Replace-ExactOnce -Text $text -Old '$script:AppVersion = ''1.0.0-dev2''' -New '$script:AppVersion = ''1.0.0-dev3''' -Label 'runtime version'

$oldRu = @'
        BackupRestored = 'Настройки восстановлены. Перезапустите Mugen Deej, чтобы применить их полностью.'
        BackupInvalid = 'Не удалось прочитать резервную копию:'
        BackupRestoreFailed = 'Не удалось восстановить настройки:'
'@
$newRu = @'
        BackupRestored = 'Настройки восстановлены.'
        BackupEmergencyCopy = 'Аварийная копия текущих настроек сохранена:'
        BackupRestartPrompt = 'Для полного применения резервной копии необходимо перезапустить Mugen Deej. Перезапустить сейчас?'
        BackupInvalid = 'Не удалось прочитать резервную копию:'
        BackupRestoreFailed = 'Не удалось восстановить настройки:'
        DialogYes = 'Да'
        DialogNo = 'Нет'
        DialogOK = 'ОК'
'@
$text = Replace-ExactOnce -Text $text -Old ($oldRu.TrimEnd()) -New ($newRu.TrimEnd()) -Label 'RU restart dialog localization'

$oldEn = @'
        BackupRestored = 'Settings restored. Restart Mugen Deej to apply them completely.'
        BackupInvalid = 'Could not read the backup:'
        BackupRestoreFailed = 'Could not restore settings:'
'@
$newEn = @'
        BackupRestored = 'Settings restored.'
        BackupEmergencyCopy = 'An emergency copy of the current settings was saved:'
        BackupRestartPrompt = 'Mugen Deej must be restarted to apply the backup completely. Restart now?'
        BackupInvalid = 'Could not read the backup:'
        BackupRestoreFailed = 'Could not restore settings:'
        DialogYes = 'Yes'
        DialogNo = 'No'
        DialogOK = 'OK'
'@
$text = Replace-ExactOnce -Text $text -Old ($oldEn.TrimEnd()) -New ($newEn.TrimEnd()) -Label 'EN restart dialog localization'

$text = Replace-ExactOnce -Text $text -Old '$script:ShutdownFinalizing = $false' -New @'
$script:ShutdownFinalizing = $false
$script:RestartRequested = $false
'@.TrimEnd() -Label 'restart runtime state'

$dialogAndSaveFunctions = @'
function Show-MugenDeejStyledDialog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('OK','YesNo')][string]$Buttons = 'OK',
        [ValidateSet('Info','Warning','Error')][string]$Kind = 'Info'
    )

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Mugen Deej'
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.ClientSize = New-Object System.Drawing.Size(560, 250)
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $card = New-Object MugenDeejWindowing.MugenCardPanel
    $card.Location = New-Object System.Drawing.Point(18, 18)
    $card.Size = New-Object System.Drawing.Size(524, 158)
    $dialog.Controls.Add($card)

    $badge = New-Object System.Windows.Forms.Label
    $badge.AutoSize = $false
    $badge.Location = New-Object System.Drawing.Point(18, 22)
    $badge.Size = New-Object System.Drawing.Size(42, 42)
    $badge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $badge.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
    $badge.Text = if ($Kind -eq 'Info') { 'i' } else { '!' }
    $card.Controls.Add($badge)

    $messageLabel = New-Object System.Windows.Forms.Label
    $messageLabel.AutoSize = $false
    $messageLabel.Location = New-Object System.Drawing.Point(72, 16)
    $messageLabel.Size = New-Object System.Drawing.Size(432, 126)
    $messageLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $messageLabel.Text = $Message
    $card.Controls.Add($messageLabel)

    if ($Buttons -eq 'YesNo') {
        $yesButton = New-Object MugenDeejWindowing.MugenButton
        $yesButton.Tag = 'MugenPrimary'
        $yesButton.Text = (T -Key 'DialogYes')
        $yesButton.Location = New-Object System.Drawing.Point(342, 194)
        $yesButton.Size = New-Object System.Drawing.Size(92, 36)
        $yesButton.DialogResult = [System.Windows.Forms.DialogResult]::Yes
        $dialog.Controls.Add($yesButton)

        $noButton = New-Object MugenDeejWindowing.MugenButton
        $noButton.Text = (T -Key 'DialogNo')
        $noButton.Location = New-Object System.Drawing.Point(450, 194)
        $noButton.Size = New-Object System.Drawing.Size(92, 36)
        $noButton.DialogResult = [System.Windows.Forms.DialogResult]::No
        $dialog.Controls.Add($noButton)

        $dialog.AcceptButton = $yesButton
        $dialog.CancelButton = $noButton
    }
    else {
        $okButton = New-Object MugenDeejWindowing.MugenButton
        $okButton.Tag = 'MugenPrimary'
        $okButton.Text = (T -Key 'DialogOK')
        $okButton.Location = New-Object System.Drawing.Point(450, 194)
        $okButton.Size = New-Object System.Drawing.Size(92, 36)
        $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Controls.Add($okButton)

        $dialog.AcceptButton = $okButton
        $dialog.CancelButton = $okButton
    }

    Apply-ThemeToForm -Form $dialog -ThemeName (Get-EffectiveTheme)
    $dialog.Add_Shown({ Ensure-FormVisible -Form $dialog -CenterIfOffscreen })
    return $dialog.ShowDialog($form)
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

        [void](Show-MugenDeejStyledDialog `
            -Message ((T -Key 'BackupCreated') + "`r`n`r`n" + $dialog.FileName) `
            -Buttons 'OK' `
            -Kind 'Info')
    }
    catch {
        Write-Log ('Backup creation failed: {0}' -f $_.Exception.Message) 'ERROR'
        [void](Show-MugenDeejStyledDialog `
            -Message ((T -Key 'BackupRestoreFailed') + "`r`n`r`n" + $_.Exception.Message) `
            -Buttons 'OK' `
            -Kind 'Error')
    }
}

'@
$text = Replace-BlockBetween `
    -Text $text `
    -StartMarker 'function Save-MugenDeejBackupInteractive {' `
    -EndMarker 'function Restore-MugenDeejBackupInteractive {' `
    -Replacement $dialogAndSaveFunctions `
    -Label 'themed backup save dialog'

$restoreFunction = @'
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
        [void](Show-MugenDeejStyledDialog `
            -Message ((T -Key 'BackupInvalid') + "`r`n`r`n" + $_.Exception.Message) `
            -Buttons 'OK' `
            -Kind 'Warning')
        return
    }

    $confirmation = Show-MugenDeejStyledDialog `
        -Message (T -Key 'BackupRestoreConfirm') `
        -Buttons 'YesNo' `
        -Kind 'Warning'

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
        [void](Show-MugenDeejStyledDialog `
            -Message ((T -Key 'BackupRestoreFailed') + "`r`n`r`n" + $_.Exception.Message) `
            -Buttons 'OK' `
            -Kind 'Error')
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

        $restartMessage = (
            (T -Key 'BackupRestored') + "`r`n`r`n" +
            (T -Key 'BackupEmergencyCopy') + "`r`n" + $preRestorePath + "`r`n`r`n" +
            (T -Key 'BackupRestartPrompt')
        )

        $restartResult = Show-MugenDeejStyledDialog `
            -Message $restartMessage `
            -Buttons 'YesNo' `
            -Kind 'Info'

        if ($restartResult -eq [System.Windows.Forms.DialogResult]::Yes) {
            Write-Log 'Restart requested after backup restore.' 'INFO'
            $script:RestartRequested = $true
            $script:Closing = $true
            $script:ExitRequested = $true
            $script:ShutdownFinalizing = $true
            $form.Close()
        }
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

        [void](Show-MugenDeejStyledDialog `
            -Message ((T -Key 'BackupRestoreFailed') + "`r`n`r`n" + $restoreError) `
            -Buttons 'OK' `
            -Kind 'Error')
    }
}

'@
$text = Replace-BlockBetween `
    -Text $text `
    -StartMarker 'function Restore-MugenDeejBackupInteractive {' `
    -EndMarker 'function Show-MugenDeejBackupMenu {' `
    -Replacement $restoreFunction `
    -Label 'themed backup restore dialog and restart flow'

$oldRunLoop = '[System.Windows.Forms.Application]::Run($form)'
$newRunLoop = @'
[System.Windows.Forms.Application]::Run($form)

if ($script:RestartRequested) {
    try {
        Write-Log ('Restarting Mugen Deej via launcher: {0}' -f $script:ExecutablePath) 'INFO'
        Start-Process -FilePath $script:ExecutablePath -WorkingDirectory $script:BaseDir
    }
    catch {
        Write-Log ('Automatic restart failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
}
'@
$text = Replace-ExactOnce -Text $text -Old $oldRunLoop -New ($newRunLoop.TrimEnd()) -Label 'post-run automatic restart'

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($Path, $text, $utf8Bom)

Write-Host 'Applied Mugen Deej 1.0.0-dev3 themed backup dialogs and automatic restart patch.'
