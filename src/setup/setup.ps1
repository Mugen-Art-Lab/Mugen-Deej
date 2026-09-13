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

# Use the Windows UI language only as the initial/default choice. The setup
# always asks explicitly before showing the main installer window.
$script:IsRussian = $false
try {
    $script:IsRussian = ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ru')
}
catch { }

function L {
    param([string]$Ru, [string]$En)
    if ($script:IsRussian) { return $Ru }
    return $En
}

$script:IsDarkTheme = $false
try {
    $themeValue = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop).AppsUseLightTheme
    $script:IsDarkTheme = ([int]$themeValue -eq 0)
}
catch { }

# Keep all colours inside one uniquely named palette. Do not use generic
# script-scope names such as $script:Text or $script:Input: Windows PowerShell
# is case-insensitive and those names are unnecessarily easy to collide with.
if ($script:IsDarkTheme) {
    $script:SetupPalette = @{
        Back       = [System.Drawing.Color]::FromArgb(18, 22, 29)
        Surface    = [System.Drawing.Color]::FromArgb(27, 33, 43)
        InputBack  = [System.Drawing.Color]::FromArgb(31, 38, 49)
        TextColor  = [System.Drawing.Color]::FromArgb(245, 247, 252)
        MutedColor = [System.Drawing.Color]::FromArgb(175, 185, 202)
        Border     = [System.Drawing.Color]::FromArgb(64, 76, 96)
        Primary    = [System.Drawing.Color]::FromArgb(78, 127, 246)
        Warning    = [System.Drawing.Color]::FromArgb(235, 179, 74)
    }
}
else {
    $script:SetupPalette = @{
        Back       = [System.Drawing.Color]::FromArgb(238, 243, 252)
        Surface    = [System.Drawing.Color]::FromArgb(249, 251, 255)
        InputBack  = [System.Drawing.Color]::White
        TextColor  = [System.Drawing.Color]::FromArgb(26, 34, 49)
        MutedColor = [System.Drawing.Color]::FromArgb(92, 105, 130)
        Border     = [System.Drawing.Color]::FromArgb(195, 205, 224)
        Primary    = [System.Drawing.Color]::FromArgb(68, 112, 240)
        Warning    = [System.Drawing.Color]::FromArgb(157, 104, 0)
    }
}

function New-SetupButton {
    param(
        [string]$Caption,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [bool]$IsPrimary = $false
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Caption
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, 38)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 1
    $button.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand

    if ($IsPrimary) {
        $button.BackColor = $script:SetupPalette['Primary']
        $button.ForeColor = [System.Drawing.Color]::White
        $button.FlatAppearance.BorderColor = $script:SetupPalette['Primary']
        $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(92, 140, 255)
        $button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(72, 117, 229)
    }
    else {
        $button.BackColor = $script:SetupPalette['InputBack']
        $button.ForeColor = $script:SetupPalette['TextColor']
        $button.FlatAppearance.BorderColor = $script:SetupPalette['Border']
        $button.FlatAppearance.MouseOverBackColor = $script:SetupPalette['Surface']
        $button.FlatAppearance.MouseDownBackColor = $script:SetupPalette['Surface']
    }

    return $button
}

function Select-SetupLanguage {
    $languageForm = New-Object System.Windows.Forms.Form
    $languageForm.Text = 'Mugen Deej — Language / Язык'
    $languageForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $languageForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $languageForm.MaximizeBox = $false
    $languageForm.MinimizeBox = $false
    $languageForm.ClientSize = New-Object System.Drawing.Size(430, 205)
    $languageForm.BackColor = $script:SetupPalette['Back']
    $languageForm.ForeColor = $script:SetupPalette['TextColor']
    $languageForm.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

    try {
        if (Test-Path -LiteralPath $SetupExePath -PathType Leaf) {
            $languageForm.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($SetupExePath)
        }
    }
    catch { }

    $languageTitle = New-Object System.Windows.Forms.Label
    $languageTitle.Text = 'Выберите язык / Choose language'
    $languageTitle.Location = New-Object System.Drawing.Point(28, 26)
    $languageTitle.Size = New-Object System.Drawing.Size(374, 34)
    $languageTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $languageTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $languageTitle.ForeColor = $script:SetupPalette['TextColor']
    $languageForm.Controls.Add($languageTitle)

    $languageHint = New-Object System.Windows.Forms.Label
    $languageHint.Text = 'Язык установщика можно выбрать независимо от языка Windows.`r`nSetup language can be selected independently of Windows.'
    $languageHint.Location = New-Object System.Drawing.Point(30, 68)
    $languageHint.Size = New-Object System.Drawing.Size(370, 48)
    $languageHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $languageHint.ForeColor = $script:SetupPalette['MutedColor']
    $languageForm.Controls.Add($languageHint)

    $russianButton = New-SetupButton -Caption 'Русский' -X 72 -Y 135 -Width 132 -IsPrimary $script:IsRussian
    $englishButton = New-SetupButton -Caption 'English' -X 226 -Y 135 -Width 132 -IsPrimary (-not $script:IsRussian)
    $languageForm.Controls.Add($russianButton)
    $languageForm.Controls.Add($englishButton)

    if ($script:IsRussian) {
        $languageForm.AcceptButton = $russianButton
        $russianButton.Select()
    }
    else {
        $languageForm.AcceptButton = $englishButton
        $englishButton.Select()
    }

    $russianButton.Add_Click({
        $script:IsRussian = $true
        $languageForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $languageForm.Close()
    })

    $englishButton.Add_Click({
        $script:IsRussian = $false
        $languageForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $languageForm.Close()
    })

    [void]$languageForm.ShowDialog()
    $languageForm.Dispose()
}

function Test-PathInside {
    param([string]$Candidate, [string]$Root)

    if ([string]::IsNullOrWhiteSpace($Candidate) -or [string]::IsNullOrWhiteSpace($Root)) {
        return $false
    }

    try {
        $candidateFull = [System.IO.Path]::GetFullPath($Candidate).TrimEnd('\')
        $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
        return (
            $candidateFull.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
            $candidateFull.StartsWith(($rootFull + '\'), [System.StringComparison]::OrdinalIgnoreCase)
        )
    }
    catch {
        return $false
    }
}

function Test-ProtectedInstallPath {
    param([string]$Path)

    $programFiles = [Environment]::GetFolderPath('ProgramFiles')
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')

    return (
        (Test-PathInside -Candidate $Path -Root $programFiles) -or
        (Test-PathInside -Candidate $Path -Root $programFilesX86)
    )
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
                throw (L -Ru 'Архив содержит недопустимый путь.' -En 'The package contains an invalid path.')
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
                try {
                    $source.CopyTo($target)
                }
                finally {
                    $target.Dispose()
                }
            }
            finally {
                $source.Dispose()
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

function New-DesktopShortcut {
    param([Parameter(Mandatory = $true)][string]$InstallPath)

    $targetExe = Join-Path $InstallPath 'MugenDeej.exe'
    if (-not (Test-Path -LiteralPath $targetExe -PathType Leaf)) {
        throw (L -Ru 'После распаковки не найден MugenDeej.exe.' -En 'MugenDeej.exe was not found after extraction.')
    }

    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    $shortcutPath = Join-Path $desktop 'Mugen Deej.lnk'
    $shell = New-Object -ComObject WScript.Shell
    try {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $targetExe
        $shortcut.WorkingDirectory = $InstallPath
        $shortcut.Description = 'Mugen Deej'
        $shortcut.IconLocation = ('{0},0' -f $targetExe)
        $shortcut.Save()
    }
    finally {
        if ($null -ne $shell) {
            [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
        }
    }
}

# Ask explicitly every time the setup starts. Windows UI culture only chooses
# which button is highlighted/default in this small selector.
Select-SetupLanguage

$form = New-Object System.Windows.Forms.Form
$form.Text = (L -Ru 'Mugen Deej — установка' -En 'Mugen Deej — Setup')
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ClientSize = New-Object System.Drawing.Size(720, 500)
$form.BackColor = $script:SetupPalette['Back']
$form.ForeColor = $script:SetupPalette['TextColor']
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

try {
    if (Test-Path -LiteralPath $SetupExePath -PathType Leaf) {
        $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($SetupExePath)
    }
}
catch { }

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'Mugen Deej'
$titleLabel.Location = New-Object System.Drawing.Point(30, 24)
$titleLabel.Size = New-Object System.Drawing.Size(500, 38)
$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 22)
$titleLabel.ForeColor = $script:SetupPalette['TextColor']
$form.Controls.Add($titleLabel)

$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.Text = ('v{0}' -f $Version)
$versionLabel.Location = New-Object System.Drawing.Point(566, 34)
$versionLabel.Size = New-Object System.Drawing.Size(120, 24)
$versionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$versionLabel.ForeColor = $script:SetupPalette['MutedColor']
$form.Controls.Add($versionLabel)

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = (L -Ru 'Portable-установка без регистрации в Windows' -En 'Portable-style setup without Windows registration')
$subtitleLabel.Location = New-Object System.Drawing.Point(33, 67)
$subtitleLabel.Size = New-Object System.Drawing.Size(620, 26)
$subtitleLabel.ForeColor = $script:SetupPalette['MutedColor']
$form.Controls.Add($subtitleLabel)

$panel = New-Object System.Windows.Forms.Panel
$panel.Location = New-Object System.Drawing.Point(28, 108)
$panel.Size = New-Object System.Drawing.Size(664, 300)
$panel.BackColor = $script:SetupPalette['Surface']
$panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($panel)

$introLabel = New-Object System.Windows.Forms.Label
$introLabel.Text = (L -Ru 'Установщик просто распакует ту же portable-сборку Mugen Deej в выбранную папку. Сам установщик не добавляет программу в список установленных приложений и не создаёт запись удаления.' -En 'Setup simply extracts the same portable Mugen Deej build into the folder you choose. Setup itself does not register the app in Installed Apps and does not create an uninstall entry.')
$introLabel.Location = New-Object System.Drawing.Point(20, 18)
$introLabel.Size = New-Object System.Drawing.Size(620, 54)
$introLabel.ForeColor = $script:SetupPalette['TextColor']
$panel.Controls.Add($introLabel)

$pathLabel = New-Object System.Windows.Forms.Label
$pathLabel.Text = (L -Ru 'Папка:' -En 'Folder:')
$pathLabel.Location = New-Object System.Drawing.Point(20, 83)
$pathLabel.Size = New-Object System.Drawing.Size(100, 24)
$pathLabel.ForeColor = $script:SetupPalette['TextColor']
$panel.Controls.Add($pathLabel)

$pathBox = New-Object System.Windows.Forms.TextBox
$pathBox.Location = New-Object System.Drawing.Point(20, 108)
$pathBox.Size = New-Object System.Drawing.Size(490, 28)
$pathBox.BackColor = $script:SetupPalette['InputBack']
$pathBox.ForeColor = $script:SetupPalette['TextColor']
$pathBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pathBox.Text = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Mugen Deej'
$panel.Controls.Add($pathBox)

$browseButton = New-SetupButton -Caption (L -Ru 'Обзор…' -En 'Browse…') -X 522 -Y 105 -Width 118
$panel.Controls.Add($browseButton)

$warningLabel = New-Object System.Windows.Forms.Label
$warningLabel.Location = New-Object System.Drawing.Point(20, 146)
$warningLabel.Size = New-Object System.Drawing.Size(620, 48)
$warningLabel.ForeColor = $script:SetupPalette['Warning']
$warningLabel.Text = (L -Ru 'Не рекомендуется устанавливать Mugen Deej в Program Files: программа хранит настройки рядом со своими файлами, и Windows может потребовать права администратора.' -En 'Installing Mugen Deej under Program Files is not recommended: the app stores settings next to its files and Windows may require administrator rights.')
$panel.Controls.Add($warningLabel)

$shortcutCheck = New-Object System.Windows.Forms.CheckBox
$shortcutCheck.Text = (L -Ru 'Создать ярлык на рабочем столе' -En 'Create a desktop shortcut')
$shortcutCheck.Location = New-Object System.Drawing.Point(20, 204)
$shortcutCheck.Size = New-Object System.Drawing.Size(310, 28)
$shortcutCheck.Checked = $true
$shortcutCheck.ForeColor = $script:SetupPalette['TextColor']
$shortcutCheck.BackColor = $script:SetupPalette['Surface']
$panel.Controls.Add($shortcutCheck)

$launchCheck = New-Object System.Windows.Forms.CheckBox
$launchCheck.Text = (L -Ru 'Запустить Mugen Deej после установки' -En 'Launch Mugen Deej after setup')
$launchCheck.Location = New-Object System.Drawing.Point(20, 238)
$launchCheck.Size = New-Object System.Drawing.Size(350, 28)
$launchCheck.Checked = $true
$launchCheck.ForeColor = $script:SetupPalette['TextColor']
$launchCheck.BackColor = $script:SetupPalette['Surface']
$panel.Controls.Add($launchCheck)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(30, 421)
$statusLabel.Size = New-Object System.Drawing.Size(420, 52)
$statusLabel.ForeColor = $script:SetupPalette['MutedColor']
$statusLabel.Text = (L -Ru 'Выберите папку и нажмите «Установить».' -En 'Choose a folder and click Install.')
$form.Controls.Add($statusLabel)

$cancelButton = New-SetupButton -Caption (L -Ru 'Отмена' -En 'Cancel') -X 466 -Y 428 -Width 104
$form.Controls.Add($cancelButton)

$installButton = New-SetupButton -Caption (L -Ru 'Установить' -En 'Install') -X 584 -Y 428 -Width 108 -IsPrimary $true
$form.Controls.Add($installButton)
$form.AcceptButton = $installButton
$form.CancelButton = $cancelButton

$script:InstallCompleted = $false
$script:InstalledPath = ''
$script:LaunchAfterFinish = $false

$browseButton.Add_Click({
    $picker = New-Object System.Windows.Forms.FolderBrowserDialog
    $picker.Description = (L -Ru 'Выберите папку для Mugen Deej' -En 'Choose a folder for Mugen Deej')
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

$cancelButton.Add_Click({
    $form.Close()
})

$installButton.Add_Click({
    if ($script:InstallCompleted) {
        $targetExe = ''
        if (-not [string]::IsNullOrWhiteSpace($script:InstalledPath)) {
            $targetExe = Join-Path $script:InstalledPath 'MugenDeej.exe'
        }
        $launchAfterFinish = $script:LaunchAfterFinish
        $form.Close()

        if ($launchAfterFinish -and (Test-Path -LiteralPath $targetExe -PathType Leaf)) {
            try {
                Start-Process -FilePath $targetExe -WorkingDirectory $script:InstalledPath
            }
            catch {
                $launchError = L -Ru ('Не удалось запустить Mugen Deej:`r`n' + $_.Exception.Message) -En ('Could not launch Mugen Deej:`r`n' + $_.Exception.Message)
                [System.Windows.Forms.MessageBox]::Show(
                    $launchError,
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
            (L -Ru 'Укажите папку для установки.' -En 'Choose an installation folder.'),
            'Mugen Deej Setup',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    try {
        $installPath = [System.IO.Path]::GetFullPath($installPath)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            (L -Ru 'Указан некорректный путь.' -En 'The selected path is invalid.'),
            'Mugen Deej Setup',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    if (Test-ProtectedInstallPath -Path $installPath) {
        $protectedMessage = L -Ru 'Выбрана папка Program Files. Mugen Deej хранит настройки рядом с программой, поэтому запись конфигурации может потребовать повышенных прав. Продолжить всё равно?' -En 'A Program Files folder was selected. Mugen Deej stores settings next to the app, so saving configuration may require elevated rights. Continue anyway?'
        $answer = [System.Windows.Forms.MessageBox]::Show(
            $protectedMessage,
            'Mugen Deej Setup',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
    }

    $existingExe = Join-Path $installPath 'MugenDeej.exe'
    if (Test-Path -LiteralPath $existingExe -PathType Leaf) {
        $updateMessage = L -Ru 'В выбранной папке уже найден Mugen Deej. Программные файлы будут обновлены. Пользовательские конфиги, логи и резервные копии не входят в установочный пакет и удаляться не будут. Продолжить?' -En 'Mugen Deej already exists in the selected folder. Application files will be updated. User config files, logs, and backups are not part of the setup payload and will not be removed. Continue?'
        $answer = [System.Windows.Forms.MessageBox]::Show(
            $updateMessage,
            'Mugen Deej Setup',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button1
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
    }

    $installButton.Enabled = $false
    $cancelButton.Enabled = $false
    $browseButton.Enabled = $false
    $pathBox.Enabled = $false
    $shortcutCheck.Enabled = $false
    $launchCheck.Enabled = $false
    $statusLabel.Text = (L -Ru 'Распаковка файлов…' -En 'Extracting files…')
    $form.Refresh()

    try {
        Expand-PortablePayload -ZipPath $PayloadPath -Destination $installPath

        if ($shortcutCheck.Checked) {
            New-DesktopShortcut -InstallPath $installPath
        }

        $script:InstallCompleted = $true
        $script:InstalledPath = $installPath
        $script:LaunchAfterFinish = [bool]$launchCheck.Checked

        $introLabel.Text = (L -Ru 'Готово. Mugen Deej распакован в выбранную папку. Установщик не зарегистрировал программу в списке приложений Windows.' -En 'Done. Mugen Deej was extracted to the selected folder. Setup did not register the app in Windows Installed Apps.')
        $pathLabel.Text = (L -Ru 'Установлено в:' -En 'Installed to:')
        $pathBox.Text = $installPath
        $pathBox.Enabled = $false
        $browseButton.Visible = $false
        $shortcutCheck.Visible = $false
        $launchCheck.Visible = $false

        $warningLabel.Location = New-Object System.Drawing.Point(20, 153)
        $warningLabel.Size = New-Object System.Drawing.Size(620, 100)
        $warningLabel.Text = (L -Ru 'Удаление: если в Mugen Deej включён «Запускать вместе с Windows», сначала отключите эту галочку в самой программе — автозапуск использует пользовательскую запись Windows. Затем закройте Mugen Deej и просто удалите папку программы. Ярлык на рабочем столе можно удалить отдельно.' -En 'Removal: if “Start Mugen Deej with Windows” is enabled, first turn that option off inside Mugen Deej — startup uses a per-user Windows startup entry. Then close Mugen Deej and simply delete its folder. The desktop shortcut can be deleted separately.')

        $statusLabel.Text = (L -Ru 'Установка завершена. Нажмите «Готово».' -En 'Setup is complete. Click Finish.')
        $cancelButton.Visible = $false
        $installButton.Text = (L -Ru 'Готово' -En 'Finish')
        $installButton.Enabled = $true
        $form.AcceptButton = $installButton
    }
    catch {
        $statusLabel.Text = (L -Ru 'Установка не завершена.' -En 'Setup did not complete.')
        $errorText = L -Ru ('Не удалось распаковать Mugen Deej.`r`n`r`n' + $_.Exception.Message) -En ('Could not extract Mugen Deej.`r`n`r`n' + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show(
            $errorText,
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
