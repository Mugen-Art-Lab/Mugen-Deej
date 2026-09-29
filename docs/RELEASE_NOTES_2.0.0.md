# Mugen Deej 2.0.0 — release notes

> Draft release body. Replace the checksum placeholders with hashes from the
> final pre-merge/release build.

## English

Mugen Deej 2.0 expands the project from a physical Windows volume mixer into a
topology-aware desktop control surface while preserving classic deej
compatibility.

### Highlights

- **Adaptive v3** — self-describing controllers can expose analog controls,
  momentary buttons, latching toggles and cumulative-position rotary encoders.
- **Typed toggle/encoder actions** — separate toggle ON/OFF actions and encoder
  CW/CCW/Push mappings.
- **Control layers** — T1/T2 can switch named layers with per-layer button and
  encoder assignments plus optional on-screen layer notifications.
- **Application profiles** — Adaptive mappings can follow the active
  application context.
- **Optional Virtual Xbox 360 / XInput output** — physical controls can drive a
  virtual gamepad with stateful press/hold/release behavior and safe
  neutralization on profile/layer changes.
- **Universal backup schema v3** — main settings, button actions, Adaptive
  actions/profiles/layers and virtual-controller settings can be backed up and
  restored together.
- **Stronger reconnect/diagnostics** — controller discovery, hot unplug,
  suspend/resume handling, topology guarding and diagnostics have been hardened
  through real-hardware testing.
- **Per-controller slider inversion** — differently wired controllers can keep
  separate direction settings.

### Controller compatibility

Mugen Deej 2.0 supports all three protocol generations:

- **Legacy** — classic numeric-only deej packets;
- **Extended** — typed slider/button packets;
- **Adaptive v3** — self-describing `s/b/t/e` packets.

Existing Legacy slider-only hardware does not need Adaptive firmware.

The public Adaptive reference is the tested Nano **5/28/2/1** controller at
**115200 baud**. Wiring, flashing and smoke-test documentation is included in:

- `docs/ADAPTIVE_V3.md`
- `docs/ADAPTIVE_V3_WIRING.md`
- `docs/ADAPTIVE_V3_BUILD.md`

### Install / upgrade

For most users, download **Mugen-Deej-2.0.0-Setup.exe**. The Setup wrapper uses
the exact same Portable payload as the ZIP and performs a portable-style
installation/update; it does not register an uninstall entry in Windows
Installed Apps.

A **Portable ZIP** is also provided.

An in-place 1.0.0 -> 2.0.0 update was hardware-tested. User configuration,
logs/backups and mapping data are treated as runtime data rather than release
payload and are not replaced by the normal package build.

Before a major update, creating a Mugen backup is still recommended.

### Unsigned Windows binaries

The current 2.0 release path does not have an Authenticode signing certificate.
Windows may show **Unknown publisher** or Microsoft Defender SmartScreen UI.

Download only from the official Mugen Deej GitHub Release and verify the
published SHA-256 checksum.

### Downloads / SHA-256

- `Mugen-Deej-2.0.0-Setup.exe` — **FINAL SHA-256: TBD**
- `Mugen-Deej-2.0.0-Portable.zip` — **FINAL SHA-256: TBD**

Sidecar `.sha256` files are published with both artifacts.

### Experimental hardware note

Development testing has also demonstrated a second matrix-backed encoder,
Adaptive `5/28/2/2`, 500000-baud transport and a 10 ms heartbeat. These
results inform future two-/four-encoder hardware, but they are **not required**
for the public 2.0 Adaptive reference build.

---

## Русский

Mugen Deej 2.0 развивает проект от физического микшера громкости Windows до
настольной панели управления, которая сама определяет топологию подключённого
контроллера, сохраняя совместимость с классическим deej.

### Главное

- **Adaptive v3** — самодокументируемый контроллер может передавать аналоговые
  регуляторы, моментальные кнопки, фиксируемые тумблеры и энкодеры с
  накопительной позицией.
- **Отдельные действия тумблеров и энкодеров** — ON/OFF для тумблеров,
  CW/CCW/Push для энкодеров.
- **Слои управления** — T1/T2 могут переключать именованные слои с отдельными
  назначениями кнопок/энкодеров и опциональным экранным уведомлением.
- **Профили приложений** — Adaptive-настройки могут зависеть от активного
  приложения.
- **Опциональный виртуальный Xbox 360 / XInput-геймпад** — физические элементы
  могут управлять виртуальным контроллером с корректным удержанием/отпусканием
  и безопасным сбросом состояния при смене профиля/слоя.
- **Универсальный backup schema v3** — основные настройки, кнопки,
  Adaptive-действия/профили/слои и настройки виртуального контроллера
  сохраняются вместе.
- **Усиленное переподключение и диагностика** — поиск контроллера, hot-unplug,
  сон/гибернация, защита топологии и диагностические сценарии проходили
  аппаратные тесты.
- **Инверсия регуляторов на профиль контроллера** — контроллеры с разной
  разводкой могут хранить отдельное направление.

### Совместимость контроллеров

Mugen Deej 2.0 поддерживает три поколения протокола:

- **Legacy** — классические числовые пакеты deej;
- **Extended** — типизированные регуляторы/кнопки;
- **Adaptive v3** — самодокументируемые поля `s/b/t/e`.

Старые Legacy-контроллеры только с регуляторами перепрошивать на Adaptive не
нужно.

Публичная эталонная Adaptive-сборка — проверенный Nano **5/28/2/1** на
**115200 бод**. Документация по подключению, прошивке и проверке:

- `docs/ADAPTIVE_V3.md`
- `docs/ADAPTIVE_V3_WIRING.md`
- `docs/ADAPTIVE_V3_BUILD.md`

### Установка / обновление

Для большинства пользователей предназначен
**Mugen-Deej-2.0.0-Setup.exe**. Setup использует тот же Portable payload, что и
ZIP, выполняет portable-установку/обновление и не регистрирует отдельную запись
удаления в «Установленных приложениях» Windows.

Также публикуется **Portable ZIP**.

Обновление 1.0.0 -> 2.0.0 поверх существующей установки проходило реальную
аппаратную проверку. Пользовательские конфиги, логи/backup и назначения не
являются частью релизного payload и обычной сборкой не заменяются.

Перед крупным обновлением всё равно полезно сделать резервную копию из Mugen.

### Неподписанные Windows-бинарники

Для текущего релиза 2.0 нет Authenticode-сертификата. Windows может показать
**«Неизвестный издатель»** или интерфейс Microsoft Defender SmartScreen.

Скачивайте файлы только из официального GitHub Release Mugen Deej и сверяйте
опубликованную SHA-256 контрольную сумму.

### Файлы / SHA-256

- `Mugen-Deej-2.0.0-Setup.exe` — **FINAL SHA-256: TBD**
- `Mugen-Deej-2.0.0-Portable.zip` — **FINAL SHA-256: TBD**

Для обоих файлов релиз содержит отдельные `.sha256` sidecar-файлы.

### Экспериментальная железка

В разработке также проверялись второй матричный энкодер, Adaptive
`5/28/2/2`, транспорт 500000 бод и heartbeat 10 мс. Это полезная база для
будущих вариантов с двумя/четырьмя энкодерами, но **не обязательная часть**
публичной эталонной Adaptive-сборки 2.0.
