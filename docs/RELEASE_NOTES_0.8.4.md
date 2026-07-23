# Mugen Deej 0.8.4

Mugen Deej 0.8.4 is a maintenance release that fixes configuration persistence on the very first launch of a clean portable installation.

## Fixed

- First-run language, control names, modes, and application assignments now persist immediately.
- A freshly created default configuration is reloaded from JSON before the onboarding interface begins.
- Configuration saving now uses a verified temporary file and atomic replacement.
- The saved file is read back after every write.
- `config.previous.json` and `config.last-good.json` provide automatic recovery.
- A completed last-good configuration is restored if the live file is missing, damaged, or unexpectedly reset.
- A final save is performed during a normal exit from the tray menu.
- Logs now include compact configuration summaries for easier diagnosis.

## Verification

The fix was tested from a clean portable folder through the complete first-run flow and four consecutive close-and-reopen cycles. The selected language, three configured targets, control names, and controller port remained intact.

## Installation

1. Download `Mugen-Deej-0.8.4-Portable.zip`.
2. Extract the complete archive to a normal writable folder.
3. Run `MugenDeej.exe`.
4. Keep `MugenDeej.exe`, `MugenDeej.ps1`, and `MugenDeej.ico` together.

---

# Русский

Mugen Deej 0.8.4 — технический выпуск, исправляющий сохранение настроек при самом первом запуске из чистой портативной папки.

## Исправлено

- Язык, названия регуляторов, режимы и назначения приложений теперь сохраняются уже после первого запуска.
- Новый конфиг сразу перечитывается из JSON до появления интерфейса первоначальной настройки.
- Запись конфига выполняется через проверенный временный файл с безопасной заменой.
- После сохранения файл повторно читается и проверяется.
- Добавлены резервные копии `config.previous.json` и `config.last-good.json`.
- Последний рабочий конфиг автоматически восстанавливается при пропаже, повреждении или неожиданном сбросе основного файла.
- При штатном выходе через трей выполняется дополнительное сохранение.
- В журнал добавлены короткие сводки состояния конфигурации.

Исправление проверено на чистой распаковке и четырёх последовательных циклах закрытия и повторного запуска.
