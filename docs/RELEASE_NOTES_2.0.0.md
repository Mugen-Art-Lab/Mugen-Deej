# Mugen Deej 2.0.0

> Черновик текста GitHub Release. Перед публикацией заменить места
> `FINAL SHA-256: TBD` контрольными суммами из финальной сборки.
>
> Draft GitHub Release body. Replace `FINAL SHA-256: TBD` with checksums from
> the final release build before publishing.

## English

Mugen Deej 2.0 is the largest update so far. It keeps classic deej controllers
working while adding a new Adaptive v3 protocol for richer DIY control panels:
buttons, latching toggles, rotary encoders, layers, application profiles and an
optional virtual Xbox controller.

### What's new

- **Adaptive v3** — a controller can describe its own set of sliders, buttons,
  toggles and rotary encoders. Mugen builds the interface from the controls that
  are actually connected instead of assuming one fixed panel layout.
- **Toggle and encoder actions** — assign separate actions for toggle ON/OFF and
  encoder clockwise/counter-clockwise/push.
- **Control layers** — T1/T2 can switch named layers with different button and
  encoder assignments. Optional on-screen notifications show the active layer.
- **Application profiles** — Adaptive mappings can change with the active
  application.
- **Optional Xbox 360 / XInput output** — physical controls can drive a virtual
  gamepad. Held inputs are tracked correctly and the virtual state is
  neutralized safely when profiles or layers change.
- **Backup format v3** — one backup can include the main settings, button
  actions, Adaptive actions, application profiles, layers and virtual-controller
  settings.
- **More robust connection handling** — controller discovery, hot unplug,
  reconnects, suspend/resume and malformed packet handling received extensive
  real-hardware testing.
- **Per-controller slider direction** — Legacy, Extended and Adaptive
  controllers with different wiring can keep separate inversion settings.
- **Improved diagnostics and encoder feedback** — clearer packet-rate
  diagnostics, more receive-buffer headroom for high-rate Adaptive traffic and
  a dedicated fast UI path for rotary encoder indicators.

### Controller compatibility

Mugen Deej 2.0 supports three protocol generations:

- **Legacy** — classic numeric-only deej packets;
- **Extended** — sliders and momentary buttons;
- **Adaptive v3** — self-describing sliders, buttons, toggles and encoders.

Existing Legacy slider-only controllers do **not** need new firmware.

The public Adaptive reference build is the tested Nano
**5 sliders / 28 buttons / 2 toggles / 1 push encoder** controller at
**115200 baud**.

Reference documentation:

- `docs/ADAPTIVE_V3.md`
- `docs/ADAPTIVE_V3_WIRING.md`
- `docs/ADAPTIVE_V3_BUILD.md`

### Install or update

For most users, use **`Mugen-Deej-2.0.0-Setup.exe`**.

A **Portable ZIP** is also available for users who prefer a completely manual,
portable installation.

The Setup EXE installs/updates the same Portable payload used by the ZIP. It
does not add a normal uninstall entry to Windows Installed Apps.

An in-place **1.0.0 -> 2.0.0** update was tested on real hardware. Normal
updates preserve user configuration, mappings, logs and backups.

Creating a Mugen backup before a major update is still recommended.

### Windows SmartScreen / unsigned binaries

Mugen Deej 2.0 is currently distributed without an Authenticode code signature.
Windows may therefore show **Unknown publisher** or Microsoft Defender
SmartScreen.

Download files only from the official Mugen Deej GitHub Release and verify the
published SHA-256 checksum if you want to confirm the downloaded file.

### Downloads

- `Mugen-Deej-2.0.0-Setup.exe` — **FINAL SHA-256: TBD**
- `Mugen-Deej-2.0.0-Portable.zip` — **FINAL SHA-256: TBD**

A matching `.sha256` file is published for each package.

### Experimental hardware work

Development builds have also tested a second matrix-backed encoder,
Adaptive `5/28/2/2`, 500000-baud serial transport and a 10 ms heartbeat.
Those experiments are helping shape future two- and four-encoder hardware, but
they are **not required** for the public 2.0 Adaptive reference controller.

---

## Русский

Mugen Deej 2.0 — самое крупное обновление проекта на данный момент. Старые
контроллеры deej продолжают работать как раньше, а для более сложных
самодельных панелей появился новый протокол Adaptive v3: с кнопками,
фиксируемыми тумблерами, энкодерами, слоями управления, профилями приложений и
опциональным виртуальным Xbox-контроллером.

### Что нового

- **Adaptive v3** — контроллер сам сообщает Mugen, какие органы управления у
  него есть: регуляторы, кнопки, тумблеры и энкодеры. Интерфейс строится по
  фактически подключённому железу, а не под одну заранее заданную панель.
- **Отдельные действия для тумблеров и энкодеров** — для тумблера можно
  назначить разные действия на включение и выключение, а для энкодера — на
  вращение вправо, влево и нажатие.
- **Слои управления** — T1/T2 могут переключать именованные слои с разными
  назначениями кнопок и энкодеров. При желании Mugen показывает на экране,
  какой слой сейчас активен.
- **Профили приложений** — назначения Adaptive-контроллера могут меняться в
  зависимости от активного приложения.
- **Опциональный виртуальный Xbox 360 / XInput-контроллер** — физические кнопки
  и другие элементы можно назначать на виртуальный геймпад. Удержания и
  отпускания отслеживаются корректно, а при смене профиля или слоя состояние
  безопасно сбрасывается.
- **Единый формат резервных копий v3** — в одну резервную копию входят основные
  настройки, действия кнопок, Adaptive-настройки, профили приложений, слои и
  параметры виртуального контроллера.
- **Надёжнее подключение и восстановление связи** — дополнительно проверены
  поиск контроллера, отключение USB на ходу, автоматическое переподключение,
  сон/гибернация и отбрасывание повреждённых пакетов.
- **Направление регуляторов хранится отдельно для каждого контроллера** —
  Legacy, Extended и Adaptive с разной разводкой можно менять местами без
  постоянного переключения общей инверсии.
- **Улучшена диагностика и отображение энкодеров** — информация о частоте
  пакетов стала понятнее, при быстром Adaptive-потоке у последовательного порта
  больше запаса по буферу, а положение энкодеров обновляется отдельным быстрым
  циклом интерфейса.

### Совместимость с контроллерами

Mugen Deej 2.0 поддерживает три поколения протокола:

- **Legacy** — классический числовой формат deej;
- **Extended** — регуляторы и моментальные кнопки;
- **Adaptive v3** — самодокументируемый формат с регуляторами, кнопками,
  тумблерами и энкодерами.

Старые Legacy-контроллеры только с регуляторами **не нужно перепрошивать**.

Проверенная эталонная Adaptive-сборка для 2.0 — Nano с
**5 регуляторами / 28 кнопками / 2 тумблерами / 1 энкодером с нажатием** на
скорости **115200 бод**.

Документация по эталонной сборке:

- `docs/ADAPTIVE_V3.md`
- `docs/ADAPTIVE_V3_WIRING.md`
- `docs/ADAPTIVE_V3_BUILD.md`

### Установка и обновление

Для большинства пользователей удобнее
**`Mugen-Deej-2.0.0-Setup.exe`**.

Если нужна полностью переносимая установка без установщика, используйте
**Portable ZIP**.

Setup EXE устанавливает тот же набор файлов, который находится в Portable ZIP,
и не добавляет обычную запись удаления в список установленных приложений
Windows.

Обновление **1.0.0 -> 2.0.0** поверх существующей установки проверено на
реальном контроллере. Обычное обновление не удаляет пользовательские настройки,
назначения, логи и резервные копии.

Перед крупным обновлением всё равно рекомендуется сделать резервную копию
настроек средствами Mugen.

### Windows SmartScreen и цифровая подпись

Mugen Deej 2.0 пока распространяется без Authenticode-подписи. Поэтому Windows
может показать **«Неизвестный издатель»** или предупреждение Microsoft Defender
SmartScreen.

Скачивайте файлы только из официального GitHub Release Mugen Deej. При желании
можно дополнительно сверить SHA-256 контрольную сумму скачанного файла с
опубликованной в релизе.

### Файлы релиза

- `Mugen-Deej-2.0.0-Setup.exe` — **FINAL SHA-256: TBD**
- `Mugen-Deej-2.0.0-Portable.zip` — **FINAL SHA-256: TBD**

Для каждого пакета публикуется отдельный файл `.sha256`.

### Экспериментальная конфигурация

Во время разработки мы также проверяли второй матричный энкодер, топологию
Adaptive `5/28/2/2`, скорость 500000 бод и heartbeat 10 мс. Эти эксперименты
нужны для будущих вариантов контроллера с двумя и четырьмя энкодерами, но для
эталонной Adaptive-сборки 2.0 они **не требуются**.
