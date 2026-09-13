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

function Get-IsRussian {
    try {
        return ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ru')
    }
    catch { return $false }
}

$script:IsRussian = Get-IsRussian
function L {
    param([string]$Ru, [string]$En)
    if ($script:IsRussian) { return $Ru }
    return $En
}

function Get-IsDarkMode {
    try {
        $value = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop).AppsUseLightTheme
        return ([int]$value -eq 0)
    }
    catch { return $false }
}

$script:IsDark = Get-IsDarkMode
if ($script:IsDark) {
    $script:BackColor = [System.Drawing.Color]::FromArgb(18, 22, 29)
    $script:PanelColor = [System.Drawing.Color]::FromArgb(27, 33, 43)
    $script:TextColor = [System.Drawing.Color]::FromArgb(245, 247, 252)
    $script:MutedColor = [System.Drawing.Color]::FromArgb(175, 185, 202)
    $script:BorderColor = [System.Drawing.Color]::FromArgb(64, 76, 96)
    $script:InputColor = [System.Drawing.Color]::FromArgb(31, 38, 49)
    $script:PrimaryColor = [System.Drawing.Color]::FromArgb(78, 127, 246)
    $script:PrimaryHover = [System.Drawing.Color]::FromArgb(92, 140, 255)
    $script:WarningColor = [System.Drawing.Color]::FromArgb(235, 179, 74)
}
else {
    $script:BackColor = [System.Drawing.Color]::FromArgb(238, 243, 252)
    $script:PanelColor = [System.Drawing.Color]::FromArgb(249, 251, 255)
    $script:TextColor = [System.Drawing.Color]::FromArgb(26, 34, 49)
    $script:MutedColor = [System.Drawing.Color]::FromArgb(92, 105, 130)
    $script:BorderColor = [System.Drawing.Color]::FromArgb(195, 205, 224)
    $script:InputColor = [System.Drawing.Color]::White
    $script:PrimaryColor = [System.Drawing.Color]::FromArgb(68, 112, 240)
    $script:PrimaryHover = [System.Drawing.Color]::FromArgb(82, 126, 250)
    $script:WarningColor = [System.Drawing.Color]::FromArgb(157, 104, 0)
}

function New-SetupButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [bool]$Primary = $false
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, 38)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 1
    $button.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand

    if ($Primary) {
        $button.BackColor = $script:PrimaryColor
        $button.ForeColor = [System.Drawing.Color]::White
        $button.FlatAppearance.BorderColor = $script:PrimaryColor
        $button.FlatAppearance.MouseOverBackColor = $script:PrimaryHover
        $button.FlatAppearance.MouseDownBackColor = $script:PrimaryHover
    }
    else {
        $button.BackColor = $script:InputColor
        $button.ForeColor = $script:TextColor
        $button.FlatAppearance.BorderColor = $script:BorderColor
        $button.FlatAppearance.MouseOverBackColor = $script:PanelColor
        $button.FlatAppearance.MouseDownBackColor = $script:PanelColor
    }

    return $button
}

function Test-PathInside {
    param([string]$Candidate, [string]$Root)
    if ([string]::IsNullOrWhiteSpace($Candidate) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }

    try {
        $candidateFull = [System.IO.Path]::GetFullPath($Candidate).TrimEnd('\')
        $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
        return (
            $candidateFull.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
            $candidateFull.StartsWith(($rootFull + '\'), [System.StringComparison]::OrdinalIgnoreCase)
        )
    }
    catch { return $false }
}

function Test-ProtectedInstallPath {
    param([string]$Path)

    $programFiles = [Environment]::GetFolderPath('ProgramFiles')
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    return ((Test-PathInside -Candidate $Path -Root $programFiles) -or (Test-PathInside -Candidate $Path -Root $programFilesX86))
}

function Expand-PortablePayload {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    [System.IO.Directory]::CreateDirectory($Destination) | Out-Null
    $root = [System.IO.Path]::GetFullPath($Destination).TrimEnd('\')
    $rootPrefix = $root + '\'

    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $archive.Entries) {
            $relative = $entry.FullName.Replace('/', '\')
            if ([string]::IsNullOrWhiteSpace($relative)) { continue }

            $destinationPath = [System.IO.Path]::GetFullPath((Join-Path $root $relative))
            if (-not $destinationPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw (L 'Архив содержит недопустимый путь.' 'The package contains an invalid path.')
            }

            if ([string]::IsNullOrEmpty($entry.Name)) {
                [System.IO.Directory]::CreateDirectory($destinationPath) | Out-Null
                continue
            }

            $parent = [System.IO.Path]::GetDirectoryName($destinationPath)
            if (-not [string]::IsNullOrWhiteSpace($parent)) {
                [System.IO.Directory]::CreateDirectory($parent) | Out-Null
            }

            $source = $entry.Open()
            try {
                $target = New-Object System.IO.FileStream(
                    $destinationPath,
                    [System.IO.FileMode]::Create,
                    [System.IO.FileAccess]::Write,
                    [System.IO.FileShare]::None
                )
                try { $source.CopyTo($target) }
                finally { $target.Dispose() }
            }
            finally { $source.Dispose() }
        }
    }
    finally { $archive.Dispose() }
}

function New-DesktopShortcut {
    param([Parameter(Mandatory = $true)][string]$InstallPath)

    $target = Join-Path $InstallPath 'MugenDeej.exe'
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        throw (L 'После распаковки не найден MugenDeej.exe.' 'MugenDeej.exe was not found after extraction.')
    }

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
        if ($null -ne $shell) {
            [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
        }
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = (L 'Mugen Deej — установка' 'Mugen Deej — Setup')
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ClientSize = New-Object System.Drawing.Size(720, 500)
$form.BackColor = $script:BackColor
$form.ForeColor = $script:TextColor
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

try {
    if (Test-Path -LiteralPath $SetupExePath -PathType Leaf) {
        $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($SetupExePath)
    }
}
catch { }

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Mugen Deej'
$title.Location = New-Object System.Drawing.Point(30, 24)
$title.Size = New-Object System.Drawing.Size(500, 38)
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 22)
$title.ForeColor = $script:TextColor
$form.Controls.Add($title)

$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.Text = ('v{0}' -f $Version)
$versionLabel.Location = New-Object System.Drawing.Point(566, 34)
$versionLabel.Size = New-Object System.Drawing.Size(120, 24)
$versionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$versionLabel.ForeColor = $script:MutedColor
$form.Controls.Add($versionLabel)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = (L 'Portable-установка без регистрации в Windows' 'Portable-style setup without Windows registration')
$subtitle.Location = New-Object System.Drawing.Point(33, 67)
$subtitle.Size = New-Object System.Drawing.Size(620, 26)
$subtitle.ForeColor = $script:MutedColor
$form.Controls.Add($subtitle)

$panel = New-Object System.Windows.Forms.Panel
$panel.Location = New-Object System.Drawing.Point(28, 108)
$panel.Size = New-Object System.Drawing.Size(664, 300)
$panel.BackColor = $script:PanelColor
$panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($panel)

$intro = New-Object System.Windows.Forms.Label
$intro.Text = (L \
    'Установщик просто распакует ту же portable-сборку Mugen Deej в выбранную папку. Сам установщик не добавляет программу в список установленных приложений и не создаёт записей удаления.' \
    'Setup simply extracts the same portable Mugen Deej build into the folder you choose. Setup itself does not register the app in Installed Apps and does not create an uninstall entry.')
$intro.Location = New-Object System.Drawing.Point(20, 18)
$intro.Size = New-Object System.Drawing.Size(620, 54)
$intro.ForeColor = $script:TextColor
$panel.Controls.Add($intro)

$pathLabel = New-Object System.Windows.Forms.Label
$pathLabel.Text = (L 'Папка:' 'Folder:')
$pathLabel.Location = New-Object System.Drawing.Point(20, 83)
$pathLabel.Size = New-Object System.Drawing.Size(90, 24)
$pathLabel.ForeColor = $script:TextColor
$panel.Controls.Add($pathLabel)

$pathBox = New-Object System.Windows.Forms.TextBox
$pathBox.Location = New-Object System.Drawing.Point(20, 108)
$pathBox.Size = New-Object System.Drawing.Size(490, 28)
$pathBox.BackColor = $script:InputColor
$pathBox.ForeColor = $script:TextColor
$pathBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pathBox.Text = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Mugen Deej'
$panel.Controls.Add($pathBox)

$browseButton = New-SetupButton -Text (L 'Обзор…' 'Browse…') -X 522 -Y 105 -Width 118
$panel.Controls.Add($browseButton)

$warning = New-Object System.Windows.Forms.Label
$warning.Location = New-Object System.Drawing.Point(20, 146)
$warning.Size = New-Object System.Drawing.Size(620, 46)
$warning.ForeColor = $script:WarningColor
$warning.Text = (L \
    'Не рекомендуется устанавливать Mugen Deej в Program Files: программа хранит пользовательские настройки рядом со своими файлами, и Windows может потребовать права администратора.' \
    'Installing Mugen Deej under Program Files is not recommended: the app stores user settings next to its files and Windows may require administrator rights.')
$panel.Controls.Add($warning)

$shortcutCheck = New-Object System.Windows.Forms.CheckBox
$shortcutCheck.Text = (L 'Создать ярлык на рабочем столе' 'Create a desktop shortcut')
$shortcutCheck.Location = New-Object System.Drawing.Point(20, 204)
$shortcutCheck.Size = New-Object System.Drawing.Size(310, 28)
$shortcutCheck.Checked = $true
$shortcutCheck.ForeColor = $script:TextColor
$shortcutCheck.BackColor = $script:PanelColor
$panel.Controls.Add($shortcutCheck)

$launchCheck = New-Object System.Windows.Forms.CheckBox
$launchCheck.Text = (L 'Запустить Mugen Deej после установки' 'Launch Mugen Deej after setup')
$launchCheck.Location = New-Object System.Drawing.Point(20, 238)
$launchCheck.Size = New-Object System.Drawing.Size(340, 28)
$launchCheck.Checked = $true
$launchCheck.ForeColor = $script:TextColor
$launchCheck.BackColor = $script:PanelColor
$panel.Controls.Add($launchCheck)

$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(30, 421)
$status.Size = New-Object System.Drawing.Size(420, 52)
$status.ForeColor = $script:MutedColor
$status.Text = (L 'Выберите папку и нажмите «Установить».' 'Choose a folder and click Install.')
$form.Controls.Add($status)

$cancelButton = New-SetupButton -Text (L 'Отмена' 'Cancel') -X 466 -Y 428 -Width 104
$form.Controls.Add($cancelButton)

$installButton = New-SetupButton -Text (L 'Установить' 'Install') -X 584 -Y 428 -Width 108 -Primary $true
$form.Controls.Add($installButton)
$form.AcceptButton = $installButton
$form.CancelButton = $cancelButton

$script:InstallCompleted = $false
$script:InstalledPath = ''
$script:LaunchAfterFinish = $false

$browseButton.Add_Click({
    $picker = New-Object System.Windows.Forms.FolderBrowserDialog
    $picker.Description = (L 'Выберите папку для Mugen Deej' 'Choose a folder for Mugen Deej')
    $picker.ShowNewFolderButton = $true
    try {
        if (Test-Path -LiteralPath $pathBox.Text -PathType Container) {
            $picker.SelectedPath = $pathBox.Text
        }
    }
    catch { }

    if ($picker.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $pathBox.Text = $picker.SelectedPath
    }
    $picker.Dispose()
})

$cancelButton.Add_Click({ $form.Close() })

$installButton.Add_Click({
    if ($script:InstallCompleted) {
        $launch = $script:LaunchAfterFinish
        $target = if ([string]::IsNullOrWhiteSpace($script:InstalledPath)) { '' } else { Join-Path $script:InstalledPath 'MugenDeej.exe' }
        $form.Close()
        if ($launch -and (Test-Path -LiteralPath $target -PathType Leaf)) {
            try { Start-Process -FilePath $target -WorkingDirectory $script:InstalledPath }
            catch {
                [System.Windows.Forms.MessageBox]::Show(
                    (L ('Не удалось запустить Mugen Deej:`r`n' + $_.Exception.Message) ('Could not launch Mugen Deej:`r`n' + $_.Exception.Message)),
                    'Mugen Deej Setup',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
            }
        }
        return
    }

    $installPath = $pathBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($installPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            (L 'Укажите папку для установки.' 'Choose an installation folder.'),
            'Mugen Deej Setup',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    try { $installPath = [System.IO.Path]::GetFullPath($installPath) }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            (L 'Указан некорректный путь.' 'The selected path is invalid.'),
            'Mugen Deej Setup',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    if (Test-ProtectedInstallPath -Path $installPath) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            (L \
                'Выбрана папка Program Files. Mugen Deej хранит настройки рядом с программой, поэтому запись конфигурации может потребовать повышенных прав. Продолжить всё равно?' \
                'A Program Files folder was selected. Mugen Deej stores settings next to the app, so saving configuration may require elevated rights. Continue anyway?'),
            'Mugen Deej Setup',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }

    $existingExe = Join-Path $installPath 'MugenDeej.exe'
    if (Test-Path -LiteralPath $existingExe -PathType Leaf) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            (L \
                'В выбранной папке уже найден Mugen Deej. Программные файлы будут обновлены. Пользовательские config-файлы, логи и резервные копии не входят в установочный payload и удаляться не будут. Продолжить?' \
                'Mugen Deej already exists in the selected folder. Application files will be updated. User config files, logs, and backups are not part of the setup payload and will not be removed. Continue?'),
            'Mugen Deej Setup',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button1
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }

    $installButton.Enabled = $false
    $cancelButton.Enabled = $false
    $browseButton.Enabled = $false
    $pathBox.Enabled = $false
    $shortcutCheck.Enabled = $false
    $launchCheck.Enabled = $false
    $status.Text = (L 'Распаковка файлов…' 'Extracting files…')
    $form.Refresh()

    try {
        Expand-PortablePayload -ZipPath $PayloadPath -Destination $installPath

        if ($shortcutCheck.Checked) {
            New-DesktopShortcut -InstallPath $installPath
        }

        $script:InstallCompleted = $true
        $script:InstalledPath = $installPath
        $script:LaunchAfterFinish = [bool]$launchCheck.Checked

        $intro.Text = (L \
            'Готово. Mugen Deej распакован в выбранную папку. Установщик не зарегистрировал программу в списке приложений Windows.' \
            'Done. Mugen Deej was extracted to the selected folder. Setup did not register the app in Windows Installed Apps.')

        $pathLabel.Text = (L 'Установлено в:' 'Installed to:')
        $pathBox.Text = $installPath
        $pathBox.Visible = $true
        $pathBox.Enabled = $false
        $browseButton.Visible = $false
        $warning.Location = New-Object System.Drawing.Point(20, 153)
        $warning.Size = New-Object System.Drawing.Size(620, 96)
        $warning.Text = (L \
            'Удаление: если в Mugen Deej включён «Запускать вместе с Windows», сначала отключите эту галочку в самой программе — автозапуск использует пользовательскую запись Windows. Затем закройте Mugen Deej и просто удалите папку программы. Ярлык на рабочем столе можно удалить отдельно.' \
            'Removal: if “Start Mugen Deej with Windows” is enabled, first turn that option off inside Mugen Deej — startup uses a per-user Windows startup entry. Then close Mugen Deej and simply delete its folder. The desktop shortcut can be deleted separately.')
        $shortcutCheck.Visible = $false
        $launchCheck.Visible = $false

        $status.Text = (L 'Установка завершена. Нажмите «Готово».' 'Setup is complete. Click Finish.')
        $cancelButton.Visible = $false
        $installButton.Text = (L 'Готово' 'Finish')
        $installButton.Enabled = $true
        $form.AcceptButton = $installButton
    }
    catch {
        $status.Text = (L 'Установка не завершена.' 'Setup did not complete.')
        [System.Windows.Forms.MessageBox]::Show(
            (L \
                ('Не удалось распаковать Mugen Deej. Если программа уже запущена из этой папки, закройте её и повторите попытку.`r`n`r`n' + $_.Exception.Message) \
                ('Could not extract Mugen Deej. If the app is already running from this folder, close it and try again.`r`n`r`n' + $_.Exception.Message)),
            'Mugen Deej Setup',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null

        $installButton.Enabled = $true
        $cancelButton.Enabled = $true
        $browseButton.Enabled = $true
        $pathBox.Enabled = $true
        $shortcutCheck.Enabled = $true
        $launchCheck.Enabled = $true
    }
})

[void]$form.ShowDialog()
