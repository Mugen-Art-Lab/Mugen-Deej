# Mugen Deej 1.0.0

Mugen Deej 1.0.0 is the first public release to support the Extended controller
format. Classic slider-only deej controllers still work as before, while
Extended controllers can add physical buttons and configurable actions.

## English

### Highlights

- **Legacy and Extended controllers** — classic numeric deej packets remain
  supported, while Extended `s...|b...` packets add buttons alongside analog
  controls. Mugen Deej detects the protocol and the number of controls
  automatically.
- **Configurable physical buttons** — buttons can mute/unmute an assigned
  control, send media and Windows volume commands, trigger hotkeys, launch
  programs or files, open folders or URLs, and run commands.
- **Tested Extended reference firmware** — the repository includes a proven
  five-control, six-button Arduino/Nano-style firmware profile under
  `arduino/MugenDeejController/`.
- **Backup and restore** — a backup stores the main configuration and button
  actions. Restore validates the file first, saves an emergency copy of the
  current settings, and then uses the same verified configuration-writing path
  as normal saves.
- **Setup EXE and portable ZIP** — Mugen Deej stays portable in both cases.
  Setup simply extracts the same portable files into a folder of your choice;
  the ZIP lets you do the same manually.
- **Safer updates** — Setup handles an already-running Mugen Deej, warns about
  protected folders, can create a desktop shortcut, and preserves user
  configuration, logs and backups when updating an existing folder.
- **Russian and English UI** — both languages remain fully supported together
  with Auto, Light and Dark themes.

### Controller compatibility

Legacy packet example:

```text
107|246|536|665|1020
```

Extended packet example:

```text
s512|s123|s900|s456|s777|b1|b1|b0|b1|b1|b1
```

In Extended packets, `sN` is an analog value from `0..1023`,
`b1` means released, and `b0` means pressed. Both formats use
newline-terminated packets. The reference Extended firmware keeps the classic
`9600` baud rate.

### Which download should I use?

For most users: **`Mugen-Deej-1.0.0-Setup.exe`**.

For a fully portable copy: **`Mugen-Deej-1.0.0-Portable.zip`**.

A matching SHA-256 checksum file is provided for each package.

Setup does not turn Mugen Deej into an installed Windows application; it is a
self-contained extractor for the portable package. It can also create a desktop
shortcut and launch Mugen Deej after extraction.

If you enabled **Start Mugen Deej with Windows** inside the application, turn
that option off before deleting or moving the folder. The startup entry belongs
to Mugen Deej itself, not to Setup.

> The 1.0.0 binaries are not code-signed. Depending on Windows security
> settings, you may see an **Unknown publisher** or SmartScreen warning. Use the
> SHA-256 checksum from the release if you want to verify the downloaded file.

### Upgrade notes

Existing Legacy controller firmware does not need to be changed. Internal
development builds that used `button-actions.dev.json` migrate to
`button-actions.json`; the old file is kept as a rollback copy.

---

## Русский

Mugen Deej 1.0.0 — первый публичный релиз с поддержкой Extended-контроллеров.
Старые deej-контроллеры только с регуляторами продолжают работать как раньше,
а Extended позволяет добавить физические кнопки и назначить им действия.

### Главное

- **Legacy и Extended** — классический числовой формат deej по-прежнему
  поддерживается, а пакеты `s...|b...` позволяют передавать вместе с
  регуляторами ещё и кнопки. Протокол и количество элементов Mugen Deej
  определяет автоматически.
- **Настраиваемые физические кнопки** — кнопку можно назначить на
  включение/выключение звука для выбранного регулятора, медиакоманды, изменение
  системной громкости Windows, горячие клавиши, запуск программ и файлов,
  открытие папок или ссылок, а также выполнение команд.
- **Проверенная Extended-прошивка** — в
  `arduino/MugenDeejController/` лежит эталонный профиль для пяти
  регуляторов и шести кнопок на Arduino/Nano-подобной плате.
- **Резервное копирование и восстановление** — в резервную копию входят
  основные настройки и действия кнопок. Перед восстановлением Mugen Deej
  проверяет файл и сохраняет аварийную копию текущих настроек.
- **Setup EXE и portable ZIP** — в обоих случаях Mugen Deej остаётся
  портативной программой. Setup EXE просто распаковывает тот же набор файлов в
  выбранную папку, а ZIP позволяет сделать это вручную.
- **Аккуратное обновление** — установщик умеет дождаться закрытия уже
  запущенного Mugen Deej, предупреждает о защищённых папках, при желании
  создаёт ярлык и не удаляет пользовательские настройки, логи и резервные
  копии при обновлении существующей папки.
- **Русский и английский интерфейс** — оба языка полностью поддерживаются
  вместе с темами Авто, Светлая и Тёмная.

### Совместимость контроллеров

Пример Legacy-пакета:

```text
107|246|536|665|1020
```

Пример Extended-пакета:

```text
s512|s123|s900|s456|s777|b1|b1|b0|b1|b1|b1
```

В Extended-формате `sN` — значение регулятора от `0` до `1023`,
`b1` означает отпущенную кнопку, а `b0` — нажатую. Пакеты заканчиваются
переводом строки; эталонная Extended-прошивка работает на скорости `9600` бод.

### Что скачивать?

Для большинства пользователей: **`Mugen-Deej-1.0.0-Setup.exe`**.

Для полностью переносимой версии: **`Mugen-Deej-1.0.0-Portable.zip`**.

Для каждого пакета опубликован отдельный файл с контрольной суммой SHA-256.

Setup EXE не превращает Mugen Deej в установленное приложение Windows — это
самораспаковывающаяся оболочка для portable-версии. Она может дополнительно
создать ярлык на рабочем столе и запустить Mugen Deej после распаковки.

Если в самой программе была включена опция **«Запускать Mugen Deej вместе с
Windows»**, перед удалением или переносом папки сначала выключите её. Запись
автозапуска создаёт само приложение, а не Setup EXE.

> Файлы версии 1.0.0 не подписаны цифровой подписью. В зависимости от настроек
> безопасности Windows может показать «Неизвестный издатель» или предупреждение
> SmartScreen. При желании сверяйте SHA-256 с контрольной суммой из релиза.

### Обновление со старых версий

Legacy-прошивку менять не нужно. Внутренние тестовые сборки, где действия
кнопок хранились в `button-actions.dev.json`, автоматически переходят на
`button-actions.json`; старый файл остаётся как резервная копия для отката.
