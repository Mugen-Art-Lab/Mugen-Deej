# Mugen Deej 0.8.5

A maintenance release focused on reliable Windows sleep and hibernation recovery.

## Highlights

- Keeps the application interface responsive across Windows sleep and hibernation.
- Restores the main window correctly after resume.
- Preserves the active serial connection instead of closing and reopening the COM port.
- Resumes controller packets automatically through the existing serial handle.
- Retains automatic recovery when a controller is physically disconnected and reconnected.
- Keeps detailed suspend/resume diagnostics in the application log.

## Tested scenario

The verified build resumed successfully after multiple short hibernation cycles and after an overnight hibernation of more than seven hours, without restarting Mugen Deej or reconnecting the controller.

## Русский

Mugen Deej 0.8.5 исправляет восстановление после сна и гибернации Windows. Интерфейс остаётся работоспособным, главное окно снова открывается корректно, а активное подключение контроллера продолжает работу через уже существующее последовательное соединение — без повторного открытия COM-порта.
