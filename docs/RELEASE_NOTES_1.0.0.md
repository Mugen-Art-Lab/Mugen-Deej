# Mugen Deej 1.0.0

Mugen Deej 1.0.0 is the first public release of the Extended-controller architecture. It keeps classic deej slider-only controllers working while adding button-capable controllers, configurable button actions, backup/restore, and a self-contained Setup EXE.

## English

### Highlights

- **Legacy + Extended controllers** — classic numeric deej packets continue to work, while Extended `s...|b...` packets can expose both physical controls and buttons. Mugen Deej detects the protocol and control counts automatically.
- **Configurable physical buttons** — assign soft mute, media commands, Windows volume actions, hotkeys, program/file launch, folders, URLs, and commands.
- **Reference Extended firmware** — a tested 5-slider + 6-button Arduino/Nano-style profile is included under `arduino/MugenDeejController/`.
- **Backup & restore** — backups include the main configuration and button actions. Restore validates the backup first, creates an emergency pre-restore snapshot, and uses the existing verified config-write pipeline.
- **Setup EXE + portable ZIP** — use the bilingual Setup for the easiest installation/update path, or keep using the portable ZIP.
- **Safer setup/update flow** — Setup handles already-running Mugen Deej copies, warns about protected locations, can create a desktop shortcut, and preserves user configuration/logs/backups when updating an existing folder.
- **Bilingual Friendly UI** — Russian and English remain fully supported together with Auto, Light, and Dark themes.

### Controller compatibility

Legacy packet example:

```text
107|246|536|665|1020
```

Extended packet example:

```text
s512|s123|s900|s456|s777|b1|b1|b0|b1|b1|b1
```

In the Extended format, `sN` is a control value (`0..1023`), `b1` is button released, and `b0` is button pressed. Both formats use newline-terminated packets and the reference firmware keeps the classic `9600` baud rate.

### Which download should I use?

For most users: **`Mugen-Deej-1.0.0-Setup.exe`**.

For a fully portable/manual setup: **`Mugen-Deej-1.0.0-Portable.zip`**.

SHA-256 sidecar files are provided for both packages.

The Setup EXE performs a portable-style installation and intentionally does **not** register Mugen Deej in Windows Installed Apps or create a normal uninstall entry. Removal is manual; if Windows startup was enabled inside Mugen Deej, disable it before deleting the application folder.

> The 1.0.0 Setup EXE is not code-signed. Depending on how the file was downloaded and on Windows security settings, Windows may show an **Unknown publisher** / security warning. Verify the SHA-256 checksum if you want to confirm the downloaded file matches the release artifact.

### Upgrade notes

Existing Legacy controller firmware does not need to be changed. Internal development builds that used `button-actions.dev.json` are migrated safely to `button-actions.json`; the legacy file is retained as a rollback copy.

---

## Русский

Mugen Deej 1.0.0 — первый публичный релиз архитектуры Extended-контроллеров. При этом старые deej-контроллеры только с регуляторами продолжают работать без перепрошивки.

### Главное

- **Legacy + Extended контроллеры** — классические числовые пакеты deej по-прежнему поддерживаются, а Extended-пакеты `s...|b...` могут передавать и регуляторы, и кнопки. Протокол и количество элементов определяются автоматически.
- **Настраиваемые физические кнопки** — можно назначить мягкое отключение звука, медиакоманды, управление громкостью Windows, хоткеи, запуск программ/файлов, открытие папок и URL, а также команды.
- **Эталонная Extended-прошивка** — в `arduino/MugenDeejController/` лежит проверенный профиль для пяти регуляторов и шести кнопок на Nano-подобной плате.
- **Резервное копирование и восстановление** — backup включает основную конфигурацию и действия кнопок. Перед восстановлением файл проверяется, создаётся аварийная копия текущих настроек, а запись проходит через уже проверенный безопасный механизм конфигурации.
- **Setup EXE + portable ZIP** — для обычного использования удобнее двуязычный Setup, а portable ZIP остаётся для полностью переносимого сценария.
- **Безопасное обновление** — установщик умеет работать с уже запущенными копиями Mugen Deej, предупреждает о защищённых папках, создаёт ярлык по желанию и при обновлении существующей папки не трогает пользовательские конфиги, логи и backup-файлы.
- **Двуязычный Friendly UI** — русский и английский интерфейс, а также темы Авто, Светлая и Тёмная сохранены.

### Совместимость контроллеров

Пример Legacy-пакета:

```text
107|246|536|665|1020
```

Пример Extended-пакета:

```text
s512|s123|s900|s456|s777|b1|b1|b0|b1|b1|b1
```

В Extended-формате `sN` — значение регулятора (`0..1023`), `b1` — кнопка отпущена, `b0` — нажата. Оба формата передаются строками с переводом строки; эталонная прошивка сохраняет классическую скорость `9600` бод.

### Что скачивать?

Для большинства пользователей: **`Mugen-Deej-1.0.0-Setup.exe`**.

Для полностью portable-варианта: **`Mugen-Deej-1.0.0-Portable.zip`**.

Для обоих файлов публикуются SHA-256 контрольные суммы.

Setup выполняет portable-установку и намеренно **не** добавляет Mugen Deej в список установленных приложений Windows и не создаёт обычный деинсталлятор. Удаление выполняется вручную; если внутри Mugen Deej был включён автозапуск Windows, сначала отключите его в программе, а уже затем удаляйте папку.

> Setup EXE версии 1.0.0 не подписан цифровой подписью. В зависимости от способа загрузки и настроек безопасности Windows может показать **Неизвестный издатель / Unknown publisher** или другое предупреждение. При необходимости сверяйте SHA-256 с файлом контрольной суммы из релиза.

### Обновление со старых версий

Legacy-прошивку контроллера менять не требуется. Внутренние dev-сборки, где действия кнопок хранились в `button-actions.dev.json`, безопасно мигрируют на `button-actions.json`; старый файл остаётся как rollback-копия.
