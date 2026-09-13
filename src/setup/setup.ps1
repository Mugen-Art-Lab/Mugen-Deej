param(
    [Parameter(Mandatory = $true)][string]$PayloadPath,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$SetupExePath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:IsRussian = $false
try { $script:IsRussian = ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ru') } catch { }

function L {
    param([string]$Ru, [string]$En)
    if ($script:IsRussian) { return $Ru }
    return $En
}

$script:IsDark = $false
try {
    $themeValue = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop).AppsUseLightTheme
    $script:IsDark = ([int]$themeValue -eq 0)
}
catch { }

if ($script:IsDark) {
    $script:Back = [System.Drawing.Color]::FromArgb(18, 22, 29)
    $script:Surface = [System.Drawing.Color]::FromArgb(27, 33, 43)
    $script:Input = [System.Drawing.Color]::FromArgb(31, 38, 49)
    $script:Text = [System.Drawing.Color]::FromArgb(245, 247, 252)
    $script:Muted = [System.Drawing.Color]::FromArgb(175, 185, 202)
    $script:Border = [System.Drawing.Color]::FromArgb(64, 76, 96)
    $script:Primary = [System.Drawing.Color]::FromArgb(78, 127, 246)
    $script:Warning = [System.Drawing.Color]::FromArgb(235, 179, 74)
}
else {
    $script:Back = [System.Drawing.Color]::FromArgb(238, 243, 252)
    $script:Surface = [System.Drawing.Color]::FromArgb(249, 251, 255)
    $script:Input = [System.Drawing.Color]::White
    $script:Text = [System.Drawing.Color]::FromArgb(26, 34, 49)
    $script:Muted = [System.Drawing.Color]::FromArgb(92, 105, 130)
    $script:Border = [System.Drawing.Color]::FromArgb(195, 205, 224)
    $script:Primary = [System.Drawing.Color]::FromArgb(68, 112, 240)
    $script:Warning = [System.Drawing.Color]::FromArgb(157, 104, 0)
}

function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [bool]$Primary = $false)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, 38)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 1
    $button.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    if ($Primary) {
        $button.BackColor = $script:Primary
        $button.ForeColor = [System.Drawing.Color]::White
        $button.FlatAppearance.BorderColor = $script:Primary
    }
    else {
        $button.BackColor = $script:Input
        $button.ForeColor = $script:Text
        $button.FlatAppearance.BorderColor = $script:Border
    }
    return $button
}

function Test-UnderPath {
    param([string]$Candidate, [string]$Root)
    if ([string]::IsNullOrWhiteSpace($Candidate) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    try {
        $candidateFull = [System.IO.Path]::GetFullPath($Candidate).TrimEnd('\')
        $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
        return ($candidateFull.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or $candidateFull.StartsWith(($rootFull + '\'), [System.StringComparison]::OrdinalIgnoreCase))
    }
    catch { return $false }
}

function Test-ProtectedPath {
    param([string]$Path)
    $pf = [Environment]::GetFolderPath('ProgramFiles')
    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    return ((Test-UnderPath -Candidate $Path -Root $pf) -or (Test-UnderPath -Candidate $Path -Root $pf86))
}

function Expand-Payload {
    param([string]$ZipPath, [string]$Destination)
    [System.IO.Directory]::CreateDirectory($Destination) | Out-Null
    $root = [System.IO.Path]::GetFullPath($Destination).TrimEnd('\')
    $prefix = $root + '\'
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $archive.Entries) {
            $relative = $entry.FullName.Replace('/', '\')
            if ([string]::IsNullOrWhiteSpace($relative)) { continue }
            $targetPath = [System.IO.Path]::GetFullPath((Join-Path $root $relative))
            if (-not $targetPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw (L -Ru 'Архив содержит недопустимый путь.' -En 'The package contains an invalid path.')
            }
            if ([string]::IsNullOrEmpty($entry.Name)) {
                [System.IO.Directory]::CreateDirectory($targetPath) | Out-Null
                continue
            }
            $parent = [System.IO.Path]::GetDirectoryName($targetPath)
            if (-not [string]::IsNullOrWhiteSpace($parent)) { [System.IO.Directory]::CreateDirectory($parent) | Out-Null }
            $source = $entry.Open()
            try {
                $target = New-Object System.IO.FileStream($targetPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                try { $source.CopyTo($target) } finally { $target.Dispose() }
            }
            finally { $source.Dispose() }
        }
    }
    finally { $archive.Dispose() }
}

function New-DesktopShortcut {
    param([string]$InstallPath)
    $target = Join-Path $InstallPath 'MugenDeej.exe'
    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    $shortcutPath = Join-Path $desktop 'Mugen Deej.lnk'
    $shell = New-Object -ComObject WScript.Shell
    try {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $target
        $shortcut.WorkingDirectory = $InstallPath
        $shortcut.Description = 'Mugen Deej'
        $shortcut.IconLocation = ('{0},0' -f $target)
        $shortcut.Save()
    }
    finally {
        if ($null -ne $shell) { [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = (L -Ru 'Mugen Deej — установка' -En 'Mugen Deej — Setup')
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ClientSize = New-Object System.Drawing.Size(720, 500)
$form.BackColor = $script:Back
$form.ForeColor = $script:Text
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
try { if (Test-Path -LiteralPath $SetupExePath -PathType Leaf) { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($SetupExePath) } } catch { }

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Mugen Deej'
$title.Location = New-Object System.Drawing.Point(30, 24)
$title.Size = New-Object System.Drawing.Size(500, 38)
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 22)
$title.ForeColor = $script:Text
$form.Controls.Add($title)

$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.Text = ('v{0}' -f $Version)
$versionLabel.Location = New-Object System.Drawing.Point(566, 34)
$versionLabel.Size = New-Object System.Drawing.Size(120, 24)
$versionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$versionLabel.ForeColor = $script:Muted
$form.Controls.Add($versionLabel)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = (L -Ru 'Portable-установка без регистрации в Windows' -En 'Portable-style setup without Windows registration')
$subtitle.Location = New-Object System.Drawing.Point(33, 67)
$subtitle.Size = New-Object System.Drawing.Size(620, 26)
$subtitle.ForeColor = $script:Muted
$form.Controls.Add($subtitle)

$panel = New-Object System.Windows.Forms.Panel
$panel.Location = New-Object System.Drawing.Point(28, 108)
$panel.Size = New-Object System.Drawing.Size(664, 300)
$panel.BackColor = $script:Surface
$panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($panel)

$intro = New-Object System.Windows.Forms.Label
$intro.Text = (L -Ru 'Установщик просто распакует ту же portable-сборку Mugen Deej в выбранную папку. Сам установщик не добавляет программу в список установленных приложений и не создаёт запись удаления.' -En 'Setup simply extracts the same portable Mugen Deej build into the folder you choose. Setup itself does not register the app in Installed Apps and does not create an uninstall entry.')
$intro.Location = New-Object System.Drawing.Point(20, 18)
$intro.Size = New-Object System.Drawing.Size(620, 54)
$intro.ForeColor = $script:Text
$panel.Controls.Add($intro)

$pathLabel = New-Object System.Windows.Forms.Label
$pathLabel.Text = (L -Ru 'Папка:' -En 'Folder:')
$pathLabel.Location = New-Object System.Drawing.Point(20, 83)
$pathLabel.Size = New-Object System.Drawing.Size(100, 24)
$pathLabel.ForeColor = $script:Text
$panel.Controls.Add($pathLabel)

$pathBox = New-Object System.Windows.Forms.TextBox
$pathBox.Location = New-Object System.Drawing.Point(20, 108)
$pathBox.Size = New-Object System.Drawing.Size(490, 28)
$pathBox.BackColor = $script:Input
$pathBox.ForeColor = $script:Text
$pathBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pathBox.Text = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Mugen Deej'
$panel.Controls.Add($pathBox)

$browseButton = New-Button -Text (L -Ru 'Обзор…' -En 'Browse…') -X 522 -Y 105 -Width 118
$panel.Controls.Add($browseButton)

$warning = New-Object System.Windows.Forms.Label
$warning.Location = New-Object System.Drawing.Point(20, 146)
$warning.Size = New-Object System.Drawing.Size(620, 48)
$warning.ForeColor = $script:Warning
$warning.Text = (L -Ru 'Не рекомендуется устанавливать Mugen Deej в Program Files: программа хранит настройки рядом со своими файлами, и Windows может потребовать права администратора.' -En 'Installing Mugen Deej under Program Files is not recommended: the app stores settings next to its files and Windows may require administrator rights.')
$panel.Controls.Add($warning)

$shortcutCheck = New-Object System.Windows.Forms.CheckBox
$shortcutCheck.Text = (L -Ru 'Создать ярлык на рабочем столе' -En 'Create a desktop shortcut')
$shortcutCheck.Location = New-Object System.Drawing.Point(20, 204)
$shortcutCheck.Size = New-Object System.Drawing.Size(310, 28)
$shortcutCheck.Checked = $true
$shortcutCheck.ForeColor = $script:Text
$shortcutCheck.BackColor = $script:Surface
$panel.Controls.Add($shortcutCheck)

$launchCheck = New-Object System.Windows.Forms.CheckBox
$launchCheck.Text = (L -Ru 'Запустить Mugen Deej после установки' -En 'Launch Mugen Deej after setup')
$launchCheck.Location = New-Object System.Drawing.Point(20, 238)
$launchCheck.Size = New-Object System.Drawing.Size(350, 28)
$launchCheck.Checked = $true
$launchCheck.ForeColor = $script:Text
$launchCheck.BackColor = $script:Surface
$panel.Controls.Add($launchCheck)

$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(30, 421)
$status.Size = New-Object System.Drawing.Size(420, 52)
$status.ForeColor = $script:Muted
$status.Text = (L -Ru 'Выберите папку и нажмите «Установить».' -En 'Choose a folder and click Install.')
$form.Controls.Add($status)

$cancelButton = New-Button -Text (L -Ru 'Отмена' -En 'Cancel') -X 466 -Y 428 -Width 104
$form.Controls.Add($cancelButton)
$installButton = New-Button -Text (L -Ru 'Установить' -En 'Install') -X 584 -Y 428 -Width 108 -Primary $true
$form.Controls.Add($installButton)
$form.AcceptButton = $installButton
$form.CancelButton = $cancelButton

$script:Completed = $false
$script:InstalledPath = ''
$script:LaunchAfter = $false

$browseButton.Add_Click({
    $picker = New-Object System.Windows.Forms.FolderBrowserDialog
    $picker.Description = (L -Ru 'Выберите папку для Mugen Deej' -En 'Choose a folder for Mugen Deej')
    $picker.ShowNewFolderButton = $true
    try { if (Test-Path -LiteralPath $pathBox.Text -PathType Container) { $picker.SelectedPath = $pathBox.Text } } catch { }
    if ($picker.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) { $pathBox.Text = $picker.SelectedPath }
    $picker.Dispose()
})

$cancelButton.Add_Click({ $form.Close() })

$installButton.Add_Click({
    if ($script:Completed) {
        $target = if ([string]::IsNullOrWhiteSpace($script:InstalledPath)) { '' } else { Join-Path $script:InstalledPath 'MugenDeej.exe' }
        $launch = $script:LaunchAfter
        $form.Close()
        if ($launch -and (Test-Path -LiteralPath $target -PathType Leaf)) {
            try { Start-Process -FilePath $target -WorkingDirectory $script:InstalledPath } catch { }
        }
        return
    }

    $installPath = $pathBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($installPath)) {
        [System.Windows.Forms.MessageBox]::Show((L -Ru 'Укажите папку для установки.' -En 'Choose an installation folder.'), 'Mugen Deej Setup', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    try { $installPath = [System.IO.Path]::GetFullPath($installPath) }
    catch {
        [System.Windows.Forms.MessageBox]::Show((L -Ru 'Указан некорректный путь.' -En 'The selected path is invalid.'), 'Mugen Deej Setup', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    if (Test-ProtectedPath -Path $installPath) {
        $programFilesText = L -Ru 'Выбрана папка Program Files. Mugen Deej хранит настройки рядом с программой, поэтому запись конфигурации может потребовать повышенных прав. Продолжить всё равно?' -En 'A Program Files folder was selected. Mugen Deej stores settings next to the app, so saving configuration may require elevated rights. Continue anyway?'
        $answer = [System.Windows.Forms.MessageBox]::Show($programFilesText, 'Mugen Deej Setup', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning, [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }

    $existingExe = Join-Path $installPath 'MugenDeej.exe'
    if (Test-Path -LiteralPath $existingExe -PathType Leaf) {
        $updateText = L -Ru 'В выбранной папке уже найден Mugen Deej. Программные файлы будут обновлены. Пользовательские конфиги, логи и резервные копии не входят в установочный payload и удаляться не будут. Продолжить?' -En 'Mugen Deej already exists in the selected folder. Application files will be updated. User config files, logs, and backups are not part of the setup payload and will not be removed. Continue?'
        $answer = [System.Windows.Forms.MessageBox]::Show($updateText, 'Mugen Deej Setup', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }

    $installButton.Enabled = $false
    $cancelButton.Enabled = $false
    $status.Text = (L -Ru 'Распаковка файлов…' -En 'Extracting files…')
    $form.Refresh()

    try {
        Expand-Payload -ZipPath $PayloadPath -Destination $installPath
        if ($shortcutCheck.Checked) { New-DesktopShortcut -InstallPath $installPath }

        $script:Completed = $true
        $script:InstalledPath = $installPath
        $script:LaunchAfter = [bool]$launchCheck.Checked

        $intro.Text = (L -Ru 'Готово. Mugen Deej распакован в выбранную папку. Установщик не зарегистрировал программу в списке приложений Windows.' -En 'Done. Mugen Deej was extracted to the selected folder. Setup did not register the app in Windows Installed Apps.')
        $pathLabel.Text = (L -Ru 'Установлено в:' -En 'Installed to:')
        $pathBox.Text = $installPath
        $pathBox.Enabled = $false
        $browseButton.Visible = $false
        $shortcutCheck.Visible = $false
        $launchCheck.Visible = $false
        $warning.Location = New-Object System.Drawing.Point(20, 153)
        $warning.Size = New-Object System.Drawing.Size(620, 100)
        $warning.Text = (L -Ru 'Удаление: если в Mugen Deej включён «Запускать вместе с Windows», сначала отключите эту галочку в самой программе — автозапуск использует пользовательскую запись Windows. Затем закройте Mugen Deej и просто удалите папку программы. Ярлык на рабочем столе можно удалить отдельно.' -En 'Removal: if “Start Mugen Deej with Windows” is enabled, first turn that option off inside Mugen Deej — startup uses a per-user Windows startup entry. Then close Mugen Deej and simply delete its folder. The desktop shortcut can be deleted separately.')
        $status.Text = (L -Ru 'Установка завершена. Нажмите «Готово».' -En 'Setup is complete. Click Finish.')
        $cancelButton.Visible = $false
        $installButton.Text = (L -Ru 'Готово' -En 'Finish')
        $installButton.Enabled = $true
    }
    catch {
        $installButton.Enabled = $true
        $cancelButton.Enabled = $true
        $status.Text = (L -Ru 'Установка не завершена.' -En 'Setup did not complete.')
        $errorText = L -Ru ('Не удалось распаковать Mugen Deej. Если программа уже запущена из этой папки, закройте её и повторите попытку.`r`n`r`n' + $_.Exception.Message) -En ('Could not extract Mugen Deej. If the app is already running from this folder, close it and try again.`r`n`r`n' + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($errorText, 'Mugen Deej Setup', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

[void]$form.ShowDialog()
