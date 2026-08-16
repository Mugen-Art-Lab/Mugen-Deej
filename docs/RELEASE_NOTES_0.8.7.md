# Mugen Deej 0.8.7

Mugen Deej 0.8.7 is a UI-focused release that adds native light/dark theming and a refreshed Friendly UI while deliberately leaving the proven controller, USB, reconnect, and Windows audio logic unchanged.

## What’s new

- Added **Auto, Light, and Dark** application themes.
- **Auto** follows Windows app-theme changes while Mugen Deej is running.
- Refreshed the WinForms interface with rounded cards, custom combo boxes, flatter buttons, and smoother control-position indicators.
- Added matching theme styling across the main window, control settings, first-run guide, application picker, and notification-area menu.
- Improved light-theme contrast and surface separation for bright and HDR displays.
- Improved visual stability of control-position indicators so a stationary potentiometer no longer appears to jitter.
- Refined Russian and English layouts, including the theme selector, physical-control position labels, and control-status spacing.

## Theme behavior

The selected theme is saved in the portable configuration. **Light** and **Dark** remain fixed until changed manually. **Auto** follows the current Windows application theme and updates while the program is running, without requiring a restart.

## UI-only stabilization

The indicator stabilization in 0.8.7 affects only the visual representation of a physical control. The exact controller value used by the existing audio-control path remains unchanged. USB discovery, serial communication, controller filtering, application mappings, Core Audio control, and reconnect behavior were intentionally left untouched.

## Verified in this release

- Live switching between Auto, Light, and Dark themes.
- Auto-theme updates after changing the Windows application theme.
- Russian and English layouts in the main window and control-settings dialog.
- Immediate response to active control movement without the previous stationary visual jitter.
- Existing startup and start-minimized-to-tray behavior from 0.8.6.
- Resume after repeated Windows hibernation cycles.
- Existing USB disconnect/reconnect recovery.

## Compatibility

Existing Mugen Deej configurations remain compatible. The Windows startup behavior introduced in 0.8.6 and the suspend/resume recovery retained from 0.8.5 are unchanged.

## Русский

Mugen Deej 0.8.7 — обновление, сосредоточенное на интерфейсе. Оно добавляет полноценные светлую и тёмную темы и обновлённый Friendly UI, при этом проверенная логика контроллера, USB, переподключения и управления звуком Windows намеренно не менялась.

### Что нового

- Добавлены темы **Авто, Светлая и Тёмная**.
- Режим **Авто** следует за изменениями темы приложений Windows прямо во время работы Mugen Deej.
- Интерфейс WinForms обновлён: появились скруглённые карточки, собственные ComboBox, более плоские кнопки и плавные индикаторы положения регуляторов.
- Светлая и тёмная стилизация применяется к главному окну, настройке регуляторов, подсказке первого запуска, выбору приложений и меню области уведомлений.
- Улучшен контраст светлой темы на ярких и HDR-дисплеях.
- Убрано визуальное подёргивание индикаторов неподвижных потенциометров без изменения реального значения, используемого для управления звуком.
- Исправлены мелкие проблемы русской и английской вёрстки: переключатель темы, подписи положения физических регуляторов и отступы в карточке состояния.

### Поведение тем

Выбранная тема сохраняется в portable-конфигурации. **Светлая** и **Тёмная** остаются фиксированными до ручного переключения. **Авто** следует за текущей темой приложений Windows и меняется без перезапуска программы.

### Что не менялось

Стабилизация полосок относится только к их отображению. USB-поиск, последовательное соединение, фильтрация контроллера, назначения приложений, Core Audio и логика переподключения оставлены без изменений.

### Проверено в этом релизе

Проверены переключение всех трёх тем, живое следование теме Windows в режиме Авто, русская и английская вёрстка, мгновенная реакция индикаторов без визуального дребезга в неподвижном состоянии, существующий автозапуск и запуск в трей, повторные выходы из гибернации и восстановление после отключения и повторного подключения USB-контроллера.

Совместимость с существующими конфигурациями сохранена. Поведение автозапуска из 0.8.6 и восстановление после сна/гибернации, сохранённое с 0.8.5, не изменялись.
