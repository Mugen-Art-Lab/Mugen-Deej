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
    $languageForm.Text = 'Mugen Deej — Setup language / Язык установки'
    $languageForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $languageForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $languageForm.MaximizeBox = $false
    $languageForm.MinimizeBox = $false
    $languageForm.ClientSize = New-Object System.Drawing.Size(430, 150)
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
    $languageTitle.Text = 'Выберите язык установки / Choose setup language'
    $languageTitle.Location = New-Object System.Drawing.Point(20, 24)
    $languageTitle.Size = New-Object System.Drawing.Size(390, 34)
    $languageTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $languageTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $languageTitle.ForeColor = $script:SetupPalette['TextColor']
    $languageForm.Controls.Add($languageTitle)

    $russianButton = New-SetupButton -Caption 'Русский' -X 72 -Y 82 -Width 132 -IsPrimary $script:IsRussian
    $englishButton = New-SetupButton -Caption 'English' -X 226 -Y 82 -Width 132 -IsPrimary (-not $script:IsRussian)
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

    $languageResult = $languageForm.ShowDialog()
    $languageForm.Dispose()
    return ($languageResult -eq [System.Windows.Forms.DialogResult]::OK)
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

function Resolve-InstallPath {
    param([Parameter(Mandatory = $true)][string]$SelectedPath)

    if ([string]::IsNullOrWhiteSpace($SelectedPath)) {
        throw 'Install path is empty.'
    }

    $selectedFull = [System.IO.Path]::GetFullPath($SelectedPath)
    $selectedRoot = [System.IO.Path]::GetPathRoot($selectedFull)
    if (-not $selectedFull.Equals($selectedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $selectedFull = $selectedFull.TrimEnd('\')
    }

    $selectedExe = Join-Path $selectedFull 'MugenDeej.exe'

    # An existing Mugen Deej folder is an update target even if the user has
    # renamed that folder.
    if (Test-Path -LiteralPath $selectedExe -PathType Leaf) {
        return $selectedFull
    }

    # If the user explicitly typed/selected the application folder name, use it
    # directly. Otherwise the selected path means "place the Mugen Deej folder
    # here" and Setup creates the dedicated subfolder automatically.
    $selectedLeaf = [System.IO.Path]::GetFileName($selectedFull.TrimEnd('\'))
    if (
        $selectedLeaf.Equals('Mugen Deej', [System.StringComparison]::OrdinalIgnoreCase) -or
        $selectedLeaf.Equals('MugenDeej', [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        return $selectedFull
    }

    return (Join-Path $selectedFull 'Mugen Deej')
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
# which button is highlighted/default in this small selector. Closing the
# selector cancels setup completely.
if (-not (Select-SetupLanguage)) {
    return
}

$form = New-Object System.Windows.Forms.Form
$form.Text = (L -Ru 'Mugen Deej — установка' -En 'Mugen Deej — Setup')
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ClientSize = New-Object System.Drawing.Size(720, 550)
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
$panel.Size = New-Object System.Drawing.Size(664, 328)
$panel.BackColor = $script:SetupPalette['Surface']
$panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($panel)

$introTitleLabel = New-Object System.Windows.Forms.Label
$introTitleLabel.Text = (L -Ru 'Простая portable-установка' -En 'Simple portable-style setup')
$introTitleLabel.Location = New-Object System.Drawing.Point(20, 15)
$introTitleLabel.Size = New-Object System.Drawing.Size(620, 25)
$introTitleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$introTitleLabel.ForeColor = $script:SetupPalette['TextColor']
$panel.Controls.Add($introTitleLabel)

$introBodyLabel = New-Object System.Windows.Forms.Label
$introBodyLabel.Text = (L -Ru "Выберите место, где должна находиться папка Mugen Deej.`r`nУстановщик не добавляет программу в список установленных приложений Windows." -En "Choose where the Mugen Deej folder should be placed.`r`nSetup does not add the app to Windows Installed Apps.")
$introBodyLabel.Location = New-Object System.Drawing.Point(20, 41)
$introBodyLabel.Size = New-Object System.Drawing.Size(620, 44)
$introBodyLabel.ForeColor = $script:SetupPalette['MutedColor']
$panel.Controls.Add($introBodyLabel)

$pathLabel = New-Object System.Windows.Forms.Label
$pathLabel.Text = (L -Ru 'Куда установить:' -En 'Install to:')
$pathLabel.Location = New-Object System.Drawing.Point(20, 92)
$pathLabel.Size = New-Object System.Drawing.Size(150, 23)
$pathLabel.ForeColor = $script:SetupPalette['TextColor']
$panel.Controls.Add($pathLabel)

$pathBox = New-Object System.Windows.Forms.TextBox
$pathBox.Location = New-Object System.Drawing.Point(20, 117)
$pathBox.Size = New-Object System.Drawing.Size(490, 28)
$pathBox.BackColor = $script:SetupPalette['InputBack']
$pathBox.ForeColor = $script:SetupPalette['TextColor']
$pathBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$panel.Controls.Add($pathBox)

$browseButton = New-SetupButton -Caption (L -Ru 'Обзор…' -En 'Browse…') -X 522 -Y 114 -Width 118
$panel.Controls.Add($browseButton)

$pathHintLabel = New-Object System.Windows.Forms.Label
$pathHintLabel.Location = New-Object System.Drawing.Point(20, 151)
$pathHintLabel.Size = New-Object System.Drawing.Size(620, 34)
$pathHintLabel.ForeColor = $script:SetupPalette['MutedColor']
$panel.Controls.Add($pathHintLabel)

$pathBox.Add_TextChanged({
    try {
        if ([string]::IsNullOrWhiteSpace($pathBox.Text)) {
            $pathHintLabel.Text = (L -Ru 'Выберите место установки.' -En 'Choose an installation location.')
        }
        else {
            $resolvedPreview = Resolve-InstallPath -SelectedPath $pathBox.Text.Trim()
            $pathHintLabel.Text = (L -Ru ('Папка программы: ' + $resolvedPreview) -En ('Program folder: ' + $resolvedPreview))
        }
    }
    catch {
        $pathHintLabel.Text = (L -Ru 'Путь пока выглядит некорректно.' -En 'The path does not look valid yet.')
    }
})

# The text box contains the location selected by the user, not necessarily the
# final application folder. Resolve-InstallPath is applied to both typed/pasted
# paths and paths chosen with Browse, so both input methods behave identically.
$pathBox.Text = [Environment]::GetFolderPath('LocalApplicationData')

$warningTitleLabel = New-Object System.Windows.Forms.Label
$warningTitleLabel.Text = (L -Ru 'Важно' -En 'Important')
$warningTitleLabel.Location = New-Object System.Drawing.Point(20, 191)
$warningTitleLabel.Size = New-Object System.Drawing.Size(620, 23)
$warningTitleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
$warningTitleLabel.ForeColor = $script:SetupPalette['Warning']
$panel.Controls.Add($warningTitleLabel)

$warningBodyLabel = New-Object System.Windows.Forms.Label
$warningBodyLabel.Text = (L -Ru "Не рекомендуется устанавливать в Program Files.`r`nMugen Deej хранит настройки рядом с программой, поэтому Windows может потребовать права администратора." -En "Installing under Program Files is not recommended.`r`nMugen Deej stores settings next to the app, so Windows may require administrator rights.")
$warningBodyLabel.Location = New-Object System.Drawing.Point(20, 214)
$warningBodyLabel.Size = New-Object System.Drawing.Size(620, 42)
$warningBodyLabel.ForeColor = $script:SetupPalette['MutedColor']
$panel.Controls.Add($warningBodyLabel)

$shortcutCheck = New-Object System.Windows.Forms.CheckBox
$shortcutCheck.Text = (L -Ru 'Создать ярлык на рабочем столе' -En 'Create a desktop shortcut')
$shortcutCheck.Location = New-Object System.Drawing.Point(20, 264)
$shortcutCheck.Size = New-Object System.Drawing.Size(310, 26)
$shortcutCheck.Checked = $true
$shortcutCheck.ForeColor = $script:SetupPalette['TextColor']
$shortcutCheck.BackColor = $script:SetupPalette['Surface']
$panel.Controls.Add($shortcutCheck)

$launchCheck = New-Object System.Windows.Forms.CheckBox
$launchCheck.Text = (L -Ru 'Запустить Mugen Deej после установки' -En 'Launch Mugen Deej after setup')
$launchCheck.Location = New-Object System.Drawing.Point(20, 296)
$launchCheck.Size = New-Object System.Drawing.Size(350, 26)
$launchCheck.Checked = $true
$launchCheck.ForeColor = $script:SetupPalette['TextColor']
$launchCheck.BackColor = $script:SetupPalette['Surface']
$panel.Controls.Add($launchCheck)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(30, 454)
$statusLabel.Size = New-Object System.Drawing.Size(420, 54)
$statusLabel.ForeColor = $script:SetupPalette['MutedColor']
$statusLabel.Text = (L -Ru 'Выберите место установки и нажмите «Установить».' -En 'Choose an installation location and click Install.')
$form.Controls.Add($statusLabel)

$cancelButton = New-SetupButton -Caption (L -Ru 'Отмена' -En 'Cancel') -X 466 -Y 477 -Width 104
$form.Controls.Add($cancelButton)

$installButton = New-SetupButton -Caption (L -Ru 'Установить' -En 'Install') -X 584 -Y 477 -Width 108 -IsPrimary $true
$form.Controls.Add($installButton)
$form.AcceptButton = $installButton
$form.CancelButton = $cancelButton

$script:InstallCompleted = $false
$script:InstalledPath = ''
$script:LaunchAfterFinish = $false

$browseButton.Add_Click({
    $picker = New-Object System.Windows.Forms.FolderBrowserDialog
    $picker.Description = (L -Ru 'Выберите место для папки Mugen Deej' -En 'Choose where the Mugen Deej folder should be placed')
    $picker.ShowNewFolderButton = $true

    try {
        $currentPath = $pathBox.Text.Trim()
        if (Test-Path -LiteralPath $currentPath -PathType Container) {
            $picker.SelectedPath = $currentPath
        }
        else {
            $currentParent = [System.IO.Path]::GetDirectoryName($currentPath)
            if (-not [string]::IsNullOrWhiteSpace($currentParent) -and (Test-Path -LiteralPath $currentParent -PathType Container)) {
                $picker.SelectedPath = $currentParent
            }
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
                $launchError = L -Ru ("Не удалось запустить Mugen Deej:`r`n" + $_.Exception.Message) -En ("Could not launch Mugen Deej:`r`n" + $_.Exception.Message)
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

    $selectedPath = $pathBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($selectedPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            (L -Ru 'Выберите место установки.' -En 'Choose an installation location.'),
            'Mugen Deej Setup',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    try {
        $installPath = Resolve-InstallPath -SelectedPath $selectedPath
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
        $protectedMessage = L -Ru "Папка программы окажется внутри Program Files.`r`n`r`nMugen Deej хранит настройки рядом с программой, поэтому запись конфигурации может потребовать повышенных прав.`r`n`r`nПродолжить всё равно?" -En "The program folder will be inside Program Files.`r`n`r`nMugen Deej stores settings next to the app, so saving configuration may require elevated rights.`r`n`r`nContinue anyway?"
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
        $updateMessage = L -Ru "В этой папке уже найден Mugen Deej.`r`n`r`nПрограммные файлы будут обновлены. Конфиги, логи и резервные копии установщик не удаляет.`r`n`r`nПродолжить?" -En "Mugen Deej already exists in this folder.`r`n`r`nApplication files will be updated. Setup does not remove configs, logs, or backups.`r`n`r`nContinue?"
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

        $introTitleLabel.Text = (L -Ru 'Готово' -En 'Done')
        $introBodyLabel.Text = (L -Ru "Mugen Deej распакован в отдельную папку программы.`r`nУстановщик не зарегистрировал программу в списке приложений Windows." -En "Mugen Deej was extracted into its program folder.`r`nSetup did not register the app in Windows Installed Apps.")
        $pathLabel.Text = (L -Ru 'Установлено в:' -En 'Installed to:')
        $pathBox.Text = $installPath
        $pathBox.Enabled = $false
        $browseButton.Visible = $false
        $pathHintLabel.Text = (L -Ru 'Все файлы Mugen Deej находятся в этой папке.' -En 'All Mugen Deej files are contained in this folder.')
        $shortcutCheck.Visible = $false
        $launchCheck.Visible = $false

        $warningTitleLabel.Text = (L -Ru 'Как удалить Mugen Deej' -En 'How to remove Mugen Deej')
        $warningTitleLabel.ForeColor = $script:SetupPalette['TextColor']
        $warningBodyLabel.Text = (L -Ru "Если включён «Запускать вместе с Windows», сначала отключите его в самой программе.`r`nЗатем закройте Mugen Deej и удалите папку программы. Ярлык можно удалить отдельно." -En "If Start with Windows is enabled, turn it off inside Mugen Deej first.`r`nThen close Mugen Deej and delete its folder. The desktop shortcut can be removed separately.")

        $statusLabel.Text = (L -Ru 'Установка завершена. Нажмите «Готово».' -En 'Setup is complete. Click Finish.')
        $cancelButton.Visible = $false
        $installButton.Text = (L -Ru 'Готово' -En 'Finish')
        $installButton.Enabled = $true
        $form.AcceptButton = $installButton
    }
    catch {
        $statusLabel.Text = (L -Ru 'Установка не завершена.' -En 'Setup did not complete.')
        $errorText = L -Ru ("Не удалось распаковать Mugen Deej.`r`n`r`n" + $_.Exception.Message) -En ("Could not extract Mugen Deej.`r`n`r`n" + $_.Exception.Message)
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
