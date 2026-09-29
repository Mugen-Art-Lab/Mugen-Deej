# Mugen Deej 0.8.6

Mugen Deej 0.8.6 adds built-in Windows startup controls while keeping the application fully portable.

## What’s new

- Added **Start Mugen Deej with Windows** to the main window.
- Added an independent **Start minimized to the notification area** option.
- Start-minimized launch is visually silent: the main window is suppressed before controller discovery instead of flashing briefly and then hiding.
- Windows startup registration points to `MugenDeej.exe` in the current portable folder.
- If the portable folder is moved while startup is enabled, launching Mugen Deej once from the new location updates the stored path automatically.
- Disabling startup removes only the `Mugen Deej` startup value and leaves unrelated startup entries untouched.
- Added a reminder to disable startup before deleting the portable folder.

## Portable startup note

Mugen Deej does not use an installer. If Windows startup is enabled, disable it from the application before deleting the portable folder. Deleting the folder first can leave a stale Windows startup entry pointing to a file that no longer exists.

## Verified in this release

- Startup with the main window visible after a full Windows restart.
- Startup directly to the notification area after a full Windows restart.
- Enabling, disabling, and restoring the Mugen Deej startup entry without disturbing other startup applications.
- Automatic startup-path update after launching the application from a different portable folder.
- Sleep/hibernation recovery through the existing SerialPort connection.
- USB disconnect detection and automatic reconnection after the controller reappears.

## Compatibility

The serial protocol and existing controller configuration remain compatible with 0.8.5. The sleep/hibernation recovery behavior introduced in 0.8.5 is retained.

## Русский

Mugen Deej 0.8.6 добавляет встроенные настройки автозапуска Windows, сохраняя приложение полностью portable.

### Что нового

- Добавлена настройка **«Запускать Mugen Deej вместе с Windows»** в главном окне.
- Добавлена независимая настройка **«Запускать свёрнутым в область уведомлений»**.
- При запуске в свёрнутом виде главное окно больше не появляется на экране перед подключением контроллера.
- Автозапуск использует `MugenDeej.exe` из текущей portable-папки.
- Если папка программы была перемещена при включённом автозапуске, следующий ручной запуск автоматически обновляет сохранённый путь.
- Отключение автозапуска удаляет только запись `Mugen Deej`, не затрагивая другие программы автозагрузки.
- Добавлено напоминание отключить автозапуск перед удалением portable-папки.

### Проверено в этом релизе

Проверены обычный автозапуск после полной перезагрузки Windows, запуск сразу в область уведомлений, автоматическое обновление пути после переноса portable-папки, восстановление после сна и гибернации через существующее последовательное соединение, а также автоматическое переподключение после физического отключения и повторного подключения USB-контроллера.

Совместимость с конфигурациями 0.8.5 и существующим последовательным протоколом сохранена.