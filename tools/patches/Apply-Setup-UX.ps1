param(
    [Parameter(Mandatory = $true)][string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$text = [System.IO.File]::ReadAllText($Path)

function Replace-ExactOnce {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][string]$New,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $first = $Text.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Setup patch marker was not found: $Label" }
    $second = $Text.IndexOf($Old, $first + $Old.Length, [System.StringComparison]::Ordinal)
    if ($second -ge 0) { throw "Setup patch marker is not unique: $Label" }
    return $Text.Substring(0, $first) + $New + $Text.Substring($first + $Old.Length)
}

$oldDialogFont = @'
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
'@
$newDialogFont = @'
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

    # Size confirmation dialogs from their actual localized text instead of a
    # fixed Russian/English guess. This keeps future longer translations from
    # being clipped while preserving the same compact 500 px width.
    $messageWidth = 394
    $measureFlags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::TextBoxControl
    $proposedSize = New-Object System.Drawing.Size -ArgumentList @($messageWidth, 1000)
    $measuredSize = [System.Windows.Forms.TextRenderer]::MeasureText($Message, $dialog.Font, $proposedSize, $measureFlags)
    $messageHeight = [Math]::Max(70, [Math]::Min(320, ($measuredSize.Height + 8)))
    $buttonY = 22 + $messageHeight + 18
    $dialog.ClientSize = New-Object System.Drawing.Size -ArgumentList @(500, ($buttonY + 54))
'@
$text = Replace-ExactOnce -Text $text -Old $oldDialogFont -New $newDialogFont -Label 'adaptive dialog measurement'

$text = Replace-ExactOnce -Text $text -Old '    $messageLabel.Size = New-Object System.Drawing.Size(394, 142)' -New '    $messageLabel.Size = New-Object System.Drawing.Size -ArgumentList @($messageWidth, $messageHeight)' -Label 'adaptive message label height'
$text = Replace-ExactOnce -Text $text -Old '    $yesButton = New-SetupButton -Caption $YesCaption -X 270 -Y 177 -Width 94 -IsPrimary $DefaultYes' -New '    $yesButton = New-SetupButton -Caption $YesCaption -X 270 -Y $buttonY -Width 94 -IsPrimary $DefaultYes' -Label 'adaptive yes button position'
$text = Replace-ExactOnce -Text $text -Old '    $noButton = New-SetupButton -Caption $NoCaption -X 378 -Y 177 -Width 94 -IsPrimary (-not $DefaultYes)' -New '    $noButton = New-SetupButton -Caption $NoCaption -X 378 -Y $buttonY -Width 94 -IsPrimary (-not $DefaultYes)' -Label 'adaptive no button position'

$oldState = @'
$script:InstallCompleted = $false
$script:InstalledPath = ''
$script:LaunchAfterFinish = $false
'@
$newState = @'
$script:InstallCompleted = $false
$script:InstalledPath = ''
$script:LaunchAfterFinish = $false
$script:LaunchSuppressedByOtherInstance = $false
'@
$text = Replace-ExactOnce -Text $text -Old $oldState -New $newState -Label 'launch suppression state'

$oldDisableLaunch = @'
        $launchCheck.Checked = $false
'@
$newDisableLaunch = @'
        $launchCheck.Checked = $false
        $script:LaunchSuppressedByOtherInstance = $true
'@
$text = Replace-ExactOnce -Text $text -Old $oldDisableLaunch -New $newDisableLaunch -Label 'remember suppressed launch'

$oldRemovalText = @'
        $warningBodyLabel.Text = (L -Ru "1. Если включена опция «Запускать Mugen Deej вместе с Windows», отключите её в самой программе.`r`n2. Закройте Mugen Deej.`r`n3. Если эта папка используется только для Mugen Deej — удалите её целиком.`r`n4. Если в папке есть другие ваши файлы — удалите только файлы и папки Mugen Deej.`r`n5. Ярлык на рабочем столе можно удалить отдельно." -En "1. If the 'Start Mugen Deej with Windows' option is enabled, turn it off in the app.`r`n2. Close Mugen Deej.`r`n3. If this folder is used only for Mugen Deej, delete the whole folder.`r`n4. If it also contains your own files, delete only Mugen Deej files and folders.`r`n5. The desktop shortcut can be deleted separately.")
'@
$newRemovalText = @'
        $warningBodyLabel.Text = (L -Ru "1. Если включена опция «Запускать Mugen Deej вместе с Windows», отключите её в самой программе.`r`n2. Закройте Mugen Deej.`r`n3. Если эта папка используется только для Mugen Deej — удалите её целиком.`r`n4. Если в папке есть другие ваши файлы — удалите только файлы и папки Mugen Deej.`r`n5. Ярлык на рабочем столе можно удалить отдельно." -En "1. If the 'Start Mugen Deej with Windows' option is enabled, turn it off in the app.`r`n2. Close Mugen Deej.`r`n3. If this folder is used only for Mugen Deej, delete the whole folder.`r`n4. If it also contains your own files, delete only Mugen Deej files and folders.`r`n5. The desktop shortcut can be deleted separately.")

        if ($script:LaunchSuppressedByOtherInstance) {
            $launchHintRu = if ($shortcutCheck.Checked) {
                'Закройте её, если она ещё запущена, затем запустите установленный Mugen Deej с ярлыка на рабочем столе.'
            }
            else {
                'Закройте её, если она ещё запущена, затем запустите MugenDeej.exe из установленной папки.'
            }
            $launchHintEn = if ($shortcutCheck.Checked) {
                'Close it if it is still running, then start the installed Mugen Deej from the desktop shortcut.'
            }
            else {
                'Close it if it is still running, then start MugenDeej.exe from the installed folder.'
            }

            $introTitleLabel.Text = (L -Ru 'Готово — Mugen Deej не запущен' -En 'Done — Mugen Deej was not launched')
            $introTitleLabel.ForeColor = $script:SetupPalette['Warning']
            $introBodyLabel.Size = New-Object System.Drawing.Size(620, 112)
            $introBodyLabel.Text = (L -Ru ("Mugen Deej установлен в выбранную папку.`r`nПрограмма не добавлена в список установленных приложений Windows.`r`n`r`nMugen Deej не был запущен автоматически: во время установки уже работала другая копия.`r`n" + $launchHintRu) -En ("Mugen Deej was installed in the selected folder.`r`nThe app was not added to Windows Installed Apps.`r`n`r`nMugen Deej was not launched automatically because another copy was already running during installation.`r`n" + $launchHintEn))

            $pathLabel.Location = New-Object System.Drawing.Point(20, 157)
            $pathBox.Location = New-Object System.Drawing.Point(20, 181)
            $pathHintLabel.Location = New-Object System.Drawing.Point(20, 211)
            $warningTitleLabel.Location = New-Object System.Drawing.Point(20, 246)
            $warningBodyLabel.Location = New-Object System.Drawing.Point(20, 272)
            $warningBodyLabel.Size = New-Object System.Drawing.Size(620, 112)
        }
'@
$text = Replace-ExactOnce -Text $text -Old $oldRemovalText -New $newRemovalText -Label 'completion launch explanation'

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Path, $text, $utf8NoBom)

Write-Host 'Applied staged Setup UX patch.'
