param(
    [Parameter(Mandatory = $true)][string]$RuntimePath,
    [Parameter(Mandatory = $true)][string]$IntegrationModulePath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Replace-UiLiteral {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$OldText,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$NewText,
        [Parameter(Mandatory = $true)][string]$Label,
        [switch]$Optional
    )

    $count = 0
    $offset = 0
    while ($true) {
        $index = $Text.IndexOf($OldText, $offset, [System.StringComparison]::Ordinal)
        if ($index -lt 0) { break }
        $count++
        $offset = $index + [Math]::Max(1, $OldText.Length)
    }

    if ($count -eq 0) {
        if ($Optional) { return $Text }
        throw "UI language polish '$Label' did not find its expected source text."
    }

    Write-Host ("UI language polish: {0} replacement(s) for {1}" -f $count, $Label)
    return $Text.Replace($OldText, $NewText)
}

$runtimeResolved = (Resolve-Path -LiteralPath $RuntimePath).Path
$runtime = [System.IO.File]::ReadAllText($runtimeResolved, [System.Text.Encoding]::UTF8)

# ---------------------------------------------------------------------------
# Physical button settings
# ---------------------------------------------------------------------------
$runtime = Replace-UiLiteral $runtime 'Действия физических кнопок' 'Действия кнопок' 'button heading RU'
$runtime = Replace-UiLiteral $runtime 'Physical button actions' 'Button actions' 'button heading EN'
$runtime = Replace-UiLiteral $runtime 'Выберите кнопку в сетке или нажмите её на контроллере. Справа редактируется только выбранная кнопка; список ниже показывает сохранённую раскладку целиком.' 'Выберите кнопку в сетке или нажмите её на контроллере — она выберется здесь автоматически. Справа настраивается только выбранная кнопка, а список ниже показывает все назначения.' 'button editor guidance RU'
$runtime = Replace-UiLiteral $runtime 'Choose a button in the grid or press it on the controller. Only the selected button is edited on the right; the list below shows the whole pending layout.' 'Choose a button in the grid or press it on the controller — it will be selected here automatically. Only the selected button is edited on the right; the list below shows all assignments.' 'button editor guidance EN'
$runtime = Replace-UiLiteral $runtime 'Нажмите физическую кнопку — Mugen сам выберет её в сетке.' 'Нажмите кнопку на контроллере — Mugen выберет её автоматически.' 'button live-selection hint RU'
$runtime = Replace-UiLiteral $runtime 'Press a physical button and Mugen will select it in the grid.' 'Press a button on the controller and Mugen will select it automatically.' 'button live-selection hint EN'
$runtime = Replace-UiLiteral $runtime 'Профиль действий:' 'Профиль:' 'profile label RU'
$runtime = Replace-UiLiteral $runtime 'Action profile:' 'Profile:' 'profile label EN'
$runtime = Replace-UiLiteral $runtime 'Назначения: {0} из {1}' 'Назначено: {0} из {1}' 'assignment count RU'
$runtime = Replace-UiLiteral $runtime 'Assignments: {0} of {1}' 'Assigned: {0} of {1}' 'assignment count EN'
$runtime = Replace-UiLiteral $runtime 'Выбрать управление геймпада…' 'Виртуальный геймпад Xbox…' 'virtual picker action RU'
$runtime = Replace-UiLiteral $runtime 'Choose gamepad control…' 'Virtual Xbox gamepad…' 'virtual picker action EN'

# ---------------------------------------------------------------------------
# Toggle / encoder settings
# ---------------------------------------------------------------------------
$runtime = Replace-UiLiteral $runtime 'Настройка тумблеров и энкодеров' 'Действия тумблеров и энкодеров' 'typed settings title RU'
$runtime = Replace-UiLiteral $runtime 'Toggle and encoder settings' 'Toggle and encoder actions' 'typed settings title EN'
$runtime = Replace-UiLiteral $runtime 'Выберите орган управления слева или используйте его на контроллере.' 'Выберите тумблер или энкодер слева либо используйте его на контроллере.' 'typed guidance line 1 RU'
$runtime = Replace-UiLiteral $runtime 'Choose a control on the left or use it on the controller.' 'Choose a toggle or encoder on the left, or use it on the controller.' 'typed guidance line 1 EN'
$runtime = Replace-UiLiteral $runtime 'Тумблер — ВКЛ/ВЫКЛ; модификатор — слой; энкодер — влево/вправо и нажатие.' 'Тумблеру можно назначить действия или переключение слоя; энкодеру — вращение и нажатие.' 'typed guidance line 2 RU'
$runtime = Replace-UiLiteral $runtime 'Toggle — ON/OFF; modifier — layer; encoder — left/right and push.' 'A toggle can run actions or switch layers; an encoder uses rotation and push.' 'typed guidance line 2 EN'
$runtime = Replace-UiLiteral $runtime 'Органы управления' 'Тумблеры и энкодеры' 'typed selector group RU'
$runtime = Replace-UiLiteral $runtime 'Physical controls' 'Toggles and encoders' 'typed selector group EN'
$runtime = Replace-UiLiteral $runtime 'Выбранный орган управления' 'Выбранный элемент' 'typed editor group RU'
$runtime = Replace-UiLiteral $runtime 'T1/T2 как модификаторы: отдельные назначения кнопок и энкодера.' 'Для T1 и T2 можно задать отдельные действия кнопок и энкодера.' 'typed layer settings hint RU'
$runtime = Replace-UiLiteral $runtime 'Use T1/T2 as modifiers for alternate button and encoder mappings.' 'T1 and T2 can have separate button and encoder actions.' 'typed layer settings hint EN'
$runtime = Replace-UiLiteral $runtime ' · с нажатием' ': с нажатием' 'encoder heading push RU'
$runtime = Replace-UiLiteral $runtime ' · только вращение' ': только вращение' 'encoder heading rotation RU'
$runtime = Replace-UiLiteral $runtime ' · push-capable' ': with push' 'encoder heading push EN'
$runtime = Replace-UiLiteral $runtime ' · rotation only' ': rotation only' 'encoder heading rotation EN'

# ---------------------------------------------------------------------------
# Control layers
# ---------------------------------------------------------------------------
$runtime = Replace-UiLiteral $runtime 'Тумблеры T1 и T2 могут работать как модификаторы. Здесь задаются отличия кнопок и энкодера для T1, T2 и T1 + T2; пустые назначения наследуют основной профиль.' 'T1 и T2 могут переключать слои с отдельными действиями. Для каждого слоя можно изменить действия кнопок и энкодера. Всё, что не изменено, работает как в основном слое.' 'layer intro RU'
$runtime = Replace-UiLiteral $runtime 'Toggles T1 and T2 can act as modifiers. Define button and encoder overrides for T1, T2, and T1 + T2 here; empty overrides inherit the base profile.' 'T1 and T2 can switch layers with separate actions. Each layer can change button and encoder actions; anything unchanged works the same as the base layer.' 'layer intro EN'
$runtime = Replace-UiLiteral $runtime 'Тумблеры-модификаторы' 'Переключение слоёв' 'layer switch group RU'
$runtime = Replace-UiLiteral $runtime 'Modifier toggles' 'Layer switching' 'layer switch group EN'
$runtime = Replace-UiLiteral $runtime 'Когда тумблер используется как модификатор, его обычные действия ВКЛ/ВЫКЛ временно не выполняются.' 'Когда тумблер переключает слой, его обычные действия ВКЛ/ВЫКЛ не выполняются.' 'layer switch hint RU'
$runtime = Replace-UiLiteral $runtime 'While a toggle is used as a modifier, its normal ON/OFF actions are suppressed.' 'When a toggle switches layers, its normal ON/OFF actions do not run.' 'layer switch hint EN'
$runtime = Replace-UiLiteral $runtime 'Переопределения кнопок' 'Действия кнопок в этом слое' 'layer button editor group RU'
$runtime = Replace-UiLiteral $runtime 'Button overrides' 'Button actions in this layer' 'layer button editor group EN'
$runtime = Replace-UiLiteral $runtime 'Назначения слоя' 'Назначения в слое' 'layer assignment sidebar RU'
$runtime = Replace-UiLiteral $runtime 'Layer assignments' 'Assignments in this layer' 'layer assignment sidebar EN'
$runtime = Replace-UiLiteral $runtime 'Показываются отличия от основного профиля. Нажмите строку, чтобы перейти к кнопке.' 'Здесь только отдельные действия слоя. Нажмите строку, чтобы перейти к кнопке.' 'layer assignment hint RU'
$runtime = Replace-UiLiteral $runtime 'Shows differences from the base profile. Select a row to jump to that button.' 'Only separate actions for this layer are shown. Select a row to jump to that button.' 'layer assignment hint EN'
$runtime = Replace-UiLiteral $runtime '{0} · назначений: {1}' '{0} · назначено: {1}' 'layer assignment count RU'
$runtime = Replace-UiLiteral $runtime '{0} · assignments: {1}' '{0} · assigned: {1}' 'layer assignment count EN'
$runtime = Replace-UiLiteral $runtime 'Нет переопределений' 'Нет отдельных действий' 'empty layer assignment RU'
$runtime = Replace-UiLiteral $runtime 'No overrides' 'No separate actions' 'empty layer assignment EN'
$runtime = Replace-UiLiteral $runtime 'Наследовать основное действие' 'Как в основном слое' 'inherit action RU'
$runtime = Replace-UiLiteral $runtime 'Inherit base action' 'Same as base layer' 'inherit action EN'
$runtime = Replace-UiLiteral $runtime '«Наследовать» = основное назначение; «Не использовать» = отключить в этом слое.' '«Как в основном слое» — оставить обычное действие.'' + "`r`n" + ''«Не использовать» — отключить кнопку только в этом слое.' 'layer editor hint line 1 RU'
$runtime = Replace-UiLiteral $runtime 'Inherit = base mapping; Do nothing = disable only in this layer.' '“Same as base layer” keeps the normal action.'' + "`r`n" + ''“Do nothing” disables the button only in this layer.' 'layer editor hint line 1 EN'
$runtime = Replace-UiLiteral $runtime 'Обычные действия — один раз при нажатии; геймпад Xbox — пока удерживается кнопка.' 'Обычные действия выполняются один раз при нажатии.'' + "`r`n" + ''Виртуальный геймпад Xbox удерживает кнопку, пока вы держите кнопку на контроллере.' 'layer editor hint line 2 RU'
$runtime = Replace-UiLiteral $runtime 'Regular actions fire once per press; the Xbox gamepad stays held with the physical button.' 'Regular actions fire once per press.'' + "`r`n" + ''The virtual Xbox gamepad stays held while you hold the controller button.' 'layer editor hint line 2 EN'
$runtime = Replace-UiLiteral $runtime 'Для каждого слоя можно отдельно задать вращение и нажатие. «Наследовать» оставляет обычное назначение энкодера из выбранного профиля.' 'Для каждого слоя можно отдельно задать вращение и нажатие. «Как в основном слое» оставляет обычное назначение энкодера из выбранного профиля.' 'layered encoder inherit hint RU'
$runtime = Replace-UiLiteral $runtime 'Each layer can override rotation and push separately. Inherit keeps the normal encoder mapping from the selected profile.' 'Each layer can set rotation and push separately. “Same as base layer” keeps the normal encoder mapping from the selected profile.' 'layered encoder inherit hint EN'
$runtime = Replace-UiLiteral $runtime ' · модификатор «' ': переключает слой «' 'typed layer-toggle heading RU'
$runtime = Replace-UiLiteral $runtime ' · layer modifier ' ': switches to layer ' 'typed layer-toggle heading EN'
$runtime = Replace-UiLiteral $runtime ' · роль: модификатор слоя' '' 'typed layer-toggle live role RU'
$runtime = Replace-UiLiteral $runtime ' · layer modifier' '' 'typed layer-toggle live role EN'
$runtime = Replace-UiLiteral $runtime 'Обычные действия ВКЛ/ВЫКЛ отключены. Роль меняется в' 'Обычные действия ВКЛ/ВЫКЛ для него недоступны. Изменить это можно в' 'typed layer-toggle explanation RU'
$runtime = Replace-UiLiteral $runtime 'Its normal ON/OFF actions are suppressed. Change its role in' 'Its normal ON/OFF actions are unavailable. Change this in' 'typed layer-toggle explanation EN'
$runtime = Replace-UiLiteral $runtime 'Сейчас на контроллере: слой ' 'Сейчас активен слой: ' 'active layer preview RU'
$runtime = Replace-UiLiteral $runtime 'Controller now: layer ' 'Active layer: ' 'active layer preview EN'

# ---------------------------------------------------------------------------
# Virtual Xbox gamepad picker
# ---------------------------------------------------------------------------
$runtime = Replace-UiLiteral $runtime 'Управление виртуального геймпада' 'Настройка виртуального геймпада Xbox' 'gamepad picker window title RU'
$runtime = Replace-UiLiteral $runtime 'Virtual gamepad control' 'Virtual Xbox gamepad' 'gamepad picker window title EN'
$runtime = Replace-UiLiteral $runtime 'Выберите элемент геймпада Xbox' 'Выберите элемент виртуального геймпада Xbox' 'gamepad picker heading RU'
$runtime = Replace-UiLiteral $runtime 'Choose an Xbox gamepad control' 'Choose a virtual Xbox gamepad control' 'gamepad picker heading EN'
$runtime = Replace-UiLiteral $runtime 'Выберите, что будет делать выбранная кнопка на виртуальном геймпаде Xbox. LT/RT нажимаются полностью.' 'Выберите, что будет делать эта кнопка на виртуальном геймпаде Xbox. Для LT и RT кнопка работает как полное нажатие.' 'gamepad picker hint RU'
$runtime = Replace-UiLiteral $runtime 'Choose what the selected button should do on the virtual Xbox gamepad. LT/RT are full-press.' 'Choose what this button does on the virtual Xbox gamepad. LT and RT act as a full trigger press.' 'gamepad picker hint EN'
$runtime = Replace-UiLiteral $runtime 'Выберите, что будет делать эта кнопка на виртуальном геймпаде Xbox. Для LT и RT кнопка работает как полное нажатие.' 'Выберите, что будет делать эта кнопка на виртуальном геймпаде Xbox.'' + "`r`n" + ''Для LT и RT кнопка работает как полное нажатие.' 'gamepad picker balanced hint RU'
$runtime = Replace-UiLiteral $runtime 'Choose what this button does on the virtual Xbox gamepad. LT and RT act as a full trigger press.' 'Choose what this button does on the virtual Xbox gamepad.'' + "`r`n" + ''LT and RT act as a full trigger press.' 'gamepad picker balanced hint EN'
$runtime = Replace-UiLiteral $runtime 'Противоположные направления одной оси взаимно гасятся и оставляют её в центре.' 'Если нажать противоположные направления одновременно, стик вернётся в центр.' 'gamepad opposite-axis hint RU'
$runtime = Replace-UiLiteral $runtime 'Opposite directions on the same axis cancel each other and leave that axis centered.' 'Pressing opposite directions at the same time returns the stick to center.' 'gamepad opposite-axis hint EN'

# ---------------------------------------------------------------------------
# Main status and diagnostics
# ---------------------------------------------------------------------------
$runtime = Replace-UiLiteral $runtime 'Контроллер подключён — {0} · {1} регуляторов · {2} кнопок' 'Контроллер · {1} регуляторов · {2} кнопок' 'Legacy/Extended main status RU with buttons'
$runtime = Replace-UiLiteral $runtime 'Контроллер подключён — {0} · {1} регуляторов' 'Контроллер · {1} регуляторов' 'Legacy/Extended main status RU'
$runtime = Replace-UiLiteral $runtime 'Controller connected — {0} · {1} controls · {2} buttons' 'Controller · {1} controls · {2} buttons' 'Legacy/Extended main status EN with buttons'
$runtime = Replace-UiLiteral $runtime 'Controller connected — {0} · {1} controls' 'Controller · {1} controls' 'Legacy/Extended main status EN'

$adaptiveStatusOld = @'
return ('{0} · {1}' -f $PortName, ($parts -join ' · '))
'@.Trim()
$adaptiveStatusNew = @'
return ($(if ($script:Language -eq 'ru') { 'Контроллер · ' } else { 'Controller · ' }) + ($parts -join ' · '))
'@.Trim()
$runtime = Replace-UiLiteral $runtime $adaptiveStatusOld $adaptiveStatusNew 'Adaptive main status without COM port'

$diagnosticModeOld = @'
@('Mode', $(if ($script:Language -eq 'ru') { 'Подключение' } else { 'Connection mode' }), 18, 112),
'@.Trim()
$diagnosticModeNew = @'
@('Mode', $(if ($script:Language -eq 'ru') { 'Выбор порта' } else { 'Port selection' }), 18, 112),
'@.Trim()
$runtime = Replace-UiLiteral $runtime $diagnosticModeOld $diagnosticModeNew 'diagnostics port-selection label'
$runtime = Replace-UiLiteral $runtime '''Ручной'' } else { ''Manual''' '''Вручную'' } else { ''Manual''' 'diagnostics manual mode RU'
$runtime = Replace-UiLiteral $runtime '''Автоматический'' } else { ''Automatic''' '''Автоматически'' } else { ''Automatic''' 'diagnostics automatic mode RU'
$runtime = Replace-UiLiteral $runtime 'Драйвер контроллера работает — {0}' 'USB-драйвер работает — {0}' 'driver status RU'
$runtime = Replace-UiLiteral $runtime 'Controller driver is working — {0}' 'USB driver is working — {0}' 'driver status EN'

[System.IO.File]::WriteAllText(
    $runtimeResolved,
    $runtime,
    (New-Object System.Text.UTF8Encoding($true))
)

$integrationResolved = (Resolve-Path -LiteralPath $IntegrationModulePath).Path
$integration = [System.IO.File]::ReadAllText($integrationResolved, [System.Text.Encoding]::UTF8)

$integration = Replace-UiLiteral $integration 'XInput: Вкл' 'Выключить' 'main virtual toggle RU on'
$integration = Replace-UiLiteral $integration 'XInput: Выкл' 'Включить' 'main virtual toggle RU off'
$integration = Replace-UiLiteral $integration 'XInput: On' 'Disable' 'main virtual toggle EN on'
$integration = Replace-UiLiteral $integration 'XInput: Off' 'Enable' 'main virtual toggle EN off'
$integration = Replace-UiLiteral $integration 'Виртуальный геймпад ·' 'Виртуальный геймпад Xbox ·' 'main virtual status RU'
$integration = Replace-UiLiteral $integration 'Virtual gamepad ·' 'Virtual Xbox gamepad ·' 'main virtual status EN'

[System.IO.File]::WriteAllText(
    $integrationResolved,
    $integration,
    (New-Object System.Text.UTF8Encoding($true))
)

Write-Host 'Applied bilingual user-facing UI language polish to runtime and virtual-gamepad module.'
