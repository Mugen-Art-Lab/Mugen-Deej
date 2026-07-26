# Changelog

## 0.8.5 — 2026-07-26

- Fixed recovery after Windows sleep and hibernation.
- The application interface remains responsive and the main window opens normally after resume.
- Active controller connections are preserved across suspend instead of closing and reopening the COM port.
- Controller packets resume automatically through the existing SerialPort connection.
- Unrelated in-progress COM-port probes are cancelled during suspend without disturbing the active controller.
- Added detailed suspend and resume diagnostics to the application log.
- Verified through multiple short hibernation cycles and an overnight hibernation lasting more than seven hours.

## 0.8.4 — 2026-07-24

- Fixed first-launch configuration persistence: a newly created default configuration is now reloaded from JSON before the first-run interface begins.
- Prevented the initial PowerShell ordered dictionary from saving untouched default values after the user changed names and assignments.
- Added atomic configuration writes through a verified temporary JSON file.
- Added read-back verification after every configuration save.
- Added `config.previous.json` and `config.last-good.json` recovery copies.
- Restores a completed last-good configuration when the live file is missing, broken, or unexpectedly resembles a fresh first-run configuration.
- Saves the configuration once more during a normal tray exit.
- Added concise configuration summaries to the log, including language, first-run state, slider count, and target count.
- Confirmed persistence across four consecutive close-and-reopen cycles from a completely clean portable folder.

## 0.8.3 — 2026-07-23

- Embedded the five-size Mugen Deej icon directly into `MugenDeej.exe` as native Windows icon resources.
- Windows Explorer, shortcuts, the taskbar and the executable itself can now use the branded icon without relying on a generic EXE icon.
- Kept the bundled `MugenDeej.ico` for WinForms windows and the notification-area icon.
- Moved icon initialization after logger initialization for safer startup diagnostics.

## 0.8.2 — 2026-07-23

- Added the custom Mugen Deej multi-size application icon (`MugenDeej.ico`).
- The main window, dialogs, tray icon and taskbar icon now use the bundled Mugen Deej icon.
- Packaged the icon inside the portable build for easy reuse.


## 0.8.1 — 2026-07-23

- Added exponential retry backoff for COM ports held by other applications: retries now grow from 60 seconds up to 10 minutes instead of repeating every 15 seconds.
- Increased the negative-protocol cache for unrelated serial devices to five minutes, while newly appeared ports and explicit reconnect scans are still checked immediately.
- Replaced repeated localized access-denied exception dumps with compact “port is busy” log entries that include the next retry interval.
- Added an orange connection status listing COM ports that are currently busy when a controller cannot be found.
- Reset temporary probe history whenever a COM port disappears or reappears, preserving fast USB hot-plug recovery.
- Distinguished Windows code 31 from a missing or broken CH340 driver and now recommends another USB port or powered hub instead of immediately offering driver reinstallation.
- Detects duplicate COM-number assignments among present devices and reports the conflict directly; the WCH installer button is hidden for this Windows/USB topology issue.

## 0.8.0 — 2026-07-22

- Redesigned the application picker around two clear sources: applications currently using audio and running applications that are still silent.
- Added filtered enumeration of interactive processes in the current Windows session, including known tray applications even when they have no visible window.
- Silent applications can now be assigned before they create a Windows audio session; control starts automatically when the application first plays sound.
- Previously saved applications remain visible when they are not running and can be removed without manual config editing.
- Added application state labels for running-silent and saved-offline targets.
- Removed duplicate entries between the active-audio and silent-application lists while preserving checked selections during refresh.
- Kept manual process-name entry as a fallback for uncommon or fully background applications.
- Added complete Russian and English text for the new picker workflow.

## 0.7.3 — 2026-07-22

- Corrected the `IMMDeviceCollection` COM interface identifier used by Core Audio capture enumeration.
- Kept the working Windows PnP fallback for systems where Core Audio enumeration is unavailable.
- After an `E_NOINTERFACE` failure, the broken Core Audio route is skipped for the rest of the current run instead of being retried repeatedly.
- Added a short refresh guard and a longer capture-device cache so one drop-down opening cannot enumerate the same microphones several times.
- Logs the capture-device list only when it changes, significantly reducing repeated warnings and duplicate endpoint lists.

## 0.7.2 — 2026-07-22

- Added a Windows PnP fallback for enumerating active capture endpoints when Core Audio returns an empty list.
- Recognizes capture endpoints by their `SWD\MMDEVAPI\{0.0.1...}` device identifiers and preserves the endpoint ID needed for volume control.
- Uses `Get-PnpDevice` when available and falls back to CIM on older PowerShell installations.
- Added explicit logging that identifies whether microphone devices came from Core Audio or the PnP fallback.

## 0.7.1 — 2026-07-22

- Fixed the microphone device drop-down showing only the generic default-microphone option.
- Corrected 64-bit `PROPVARIANT` handling while reading Core Audio endpoint names.
- Isolated malformed or disappearing capture endpoints so one bad device cannot hide the rest of the list.
- Added diagnostic logging with the count and friendly names of detected capture endpoints.

## 0.7.0 — 2026-07-22

- Reworded the microphone target as the **default Windows microphone** rather than the ambiguous “main microphone”.
- Added a per-control input-device drop-down for Microphone level mode.
- Kept **Default Windows microphone — recommended** as the simple default choice.
- Added support for binding a control to a specific active capture endpoint.
- Preserved disconnected device selections in the configuration and marked them unavailable instead of silently switching to another microphone.
- Refreshed the capture-device list whenever its drop-down is opened.
- Added throttled audio-target warnings to prevent log spam when a selected input device is unavailable.
- Bumped the configuration schema to version 8 while preserving existing microphone assignments as the default-device option.

## 0.6.0 — 2026-07-22

- Replaced user-facing “knob” terminology with the more universal **control / регулятор** terminology.
- Updated the first-run guide to explicitly mention both rotary knobs and linear faders.
- Added clear onboarding text explaining that control names are display-only labels and should be renamed to match their purpose.
- Fresh configurations now start with `Control 1–5` / `Регулятор 1–5` and no audio assignments.
- Generated default names follow the selected interface language, while user-defined names remain untouched.
- Added a **Microphone level** mode for the default Windows input device.
- The microphone mode uses the Windows input endpoint level and is described honestly as distinct from guaranteed hardware gain.
- Disabled application-selection buttons for master-volume, microphone, and unused modes.
- Increased the settings and first-run layouts to fit the new explanations without clipping.
- Bumped the configuration schema to version 7 while preserving existing names and assignments.

## 0.5.0 — 2026-07-22

- Added a dedicated bilingual language-selection window for clean installations and missing configurations.
- The first screen presents **Русский** and **English** as equal choices before the main interface is created.
- Added a bilingual note explaining that the language can be changed later from the upper-right corner of the main window.
- Changed the default responsiveness preset for new configurations from Fast to Balanced.
- Existing users keep their saved language and responsiveness settings without migration changes.

## 0.4.8 — 2026-07-22

- Added a temporary negative-result cache for COM ports that open successfully but do not expose the Mugen Deej protocol.
- Added a shorter retry cooldown for busy or inaccessible COM ports.
- Newly appeared or reappeared COM ports now bypass the cache and are probed immediately.
- The last working port remains first in the normal automatic scan order.
- Startup discovery and the explicit **Find and reconnect** action clear the cache and rescan every available port, so a previously rejected COM number can still become a Deej controller.
- Reduced repeated warning spam and long delays caused by probing the same unrelated ports every few seconds.

## 0.4.7 — 2026-07-22

- Fixed the main window opening behind the Explorer folder used to launch `MugenDeej.exe`.
- The startup form is now explicitly restored, brought to the foreground, and activated before controller discovery begins.
- The temporary foreground boost is removed immediately, so the application does not remain always-on-top.
- Opening the app from the tray or double-clicking the tray icon now uses the same reliable foreground behavior.

## 0.4.6 — 2026-07-22

- Stopped the disconnected-state diagnostics from claiming that an unrelated healthy CH340/CH341 device belongs to the controller.
- Driver details are now shown only for the exact COM port of a successfully connected controller.
- While no controller is connected, the driver panel displays a neutral “will be identified after connection” message and hides the WCH maintenance button.
- A genuinely malfunctioning WCH device is still reported and keeps the repair/install action available.

## 0.4.5 — 2026-07-22

- Added a valid-packet heartbeat so physically unplugged controllers are detected even when Windows leaves the serial port formally open.
- Added automatic recovery after reconnecting the controller to the same or another USB port in automatic mode.
- Driver diagnostics now follow the exact COM port used by the active controller instead of showing an unrelated CH340 device.
- Added support for generic USB-serial controllers such as devices shown as `USB Serial Port (COMx)`.
- The WCH driver maintenance button is hidden when the active controller is not a CH340/CH341-family device.

## 0.4.4 — 2026-07-22

- Fixed the `Made by Mugen Art Lab` footer being pushed below the visible window when diagnostics were expanded.
- Reduced the expanded-window height and compacted the diagnostics layout without removing any controls or explanatory text.
- Anchored the footer to the current client area so it stays visible in both collapsed and expanded modes.

## 0.4.3 — 2026-07-22

- Fixed a reconnect race where two overlapping COM-port scans could run at once.
- Prevented a successful green connection status from being overwritten by a later stale “not found” result.
- Disabled the reconnect button while a scan is in progress and blocked timer-driven nested scans.
- Reset the automatic reconnect timer after each completed scan.

## 0.4.2 — 2026-07-22

- Fixed clipped connection-mode helper text in both Russian and English.
- Increased the diagnostics panel height and moved the driver section down to preserve spacing.
- Reworded the helper text to be shorter and clearer.

## 0.4.1 — 2026-07-22

- Fixed a PowerShell parser error that prevented version 0.4.0 from starting.
- Replaced typographic quotes inside the English first-run text with parser-safe string construction.
- Updated the launcher to force UTF-8 PowerShell output so future startup diagnostics remain readable in Russian and English.

## 0.4.0

- Mugen Deej is now a general-purpose product rather than a controller branded for one recipient.
- Added complete Russian and English interface localization.
- Added a language selector to the main window with instant switching.
- Fresh installations choose Russian for a Russian Windows UI and English for other Windows UI languages.
- Localized the first-run guide, knob settings, application picker, diagnostics, driver installation, status messages, and tray menu.
- Added English documentation and a bilingual landing README.

## 0.3.1 — 2026-07-22

- Fixed clipped helper text in the application picker.
- Widened and rearranged the manual process-entry controls.
- Widened the per-knob application-selection buttons so their labels remain on one line.
- Fixed clipping of the advanced `config.json` button.
- Added extra spacing for high-DPI and font-scaling environments.

## 0.3.0 — 2026-07-22

- Redesigned the main window around the everyday workflow: connection status, live knob indicators, and one primary settings button.
- Moved COM-port controls, driver maintenance, and logs into a collapsible **Connection and diagnostics** section.
- Added a first-run guide with live indicators for all five physical knobs.
- Replaced free-form process editing with per-knob modes: Windows master volume, applications, or disabled.
- Added an application picker with checkboxes, friendly names, current Windows audio sessions, common applications, and manual fallback.
- Added live position indicators and percentages to both the main window and the knob settings window.
- Added clear left-to-right physical knob labels.
- Added automatic normalization of quotes and the `.exe` suffix for manually entered process names.
- Moved response filtering and global inversion into an optional advanced section with human-readable explanations.
- Improved newly opened application detection with a throttled audio-session refresh on cache misses.
- Improved driver button labels and layout according to the detected driver state.

## 0.2.0 — 2026-07-22

- Added a graphical five-knob mapping editor.
- Added editable knob names and comma-separated process groups.
- Added response presets and global slider inversion to the settings UI.
- Changed serial processing to latest-packet-wins to prevent stale input queues.
- Added a cached Windows audio-session layer.
- Added grouped process-volume updates in a single audio pass.
- Reduced the default dead zone from 0.015 to 0.003.
- Increased the UI polling rate from 40 ms to 25 ms.
- Fixed the driver-install button layout.
- Switched release numbering from alpha suffixes to version 0.2.0.

## 0.1.0-alpha.2 — 2026-07-22

- Fixed PowerShell parser error caused by `$PortName:` interpolation.
- Added launcher logging to `logs/launcher.log`.
- Added visible error dialog when PowerShell exits abnormally.
- Updated CMD launcher to use `MugenDeej.exe`.
