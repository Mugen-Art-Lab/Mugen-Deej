# Mugen Deej 1.0.0 release worklog

Branch: `release/1.0.0`

This document is the continuity anchor for the 1.0.0 release work. Keep it updated after significant changes so a future development session can recover the project state without relying on chat history.

## Release history policy

- `0.8.7` remains the last public release of the old line.
- `0.9.0-dev1` through `0.9.0-dev25` are an internal development line, not a public release.
- The 0.9.0 development history must be preserved in Git/documentation rather than rewritten as if it never existed.
- `1.0.0` will be the first public release of the extended-controller architecture.

## Known-good pre-1.0 baseline

The current golden runtime baseline is the tested portable build:

`Mugen-Deej-0.9.0-dev25-soak-fixed`

It is the source of truth for consolidating the internal 0.9.0 line before new 1.0.0 work begins.

Important local development artifacts used to reconstruct the history:

- `Mugen-Deej-0.9.0-dev25-soak-fixed.zip` — the tested runtime folder.
- `SomethingStrange.zip` — collected dev1..dev25 installers/patches and release-candidate notes.
- `Mugen_Deej_0.9.0_RELEASE_CANDIDATE_NOTES.md` — detailed RC summary and test/release checklist.
- `MugenDeej_Reference_Extended_5x6_Nano.ino` — final tested reference firmware.

Do not commit personal runtime data from the golden portable folder (`config*.json`, logs, user button mappings, local backups, etc.).

## Tested 0.9.0 architecture

### Controller support

One Windows client automatically supports both protocol families:

- Legacy / classic deej: numeric fields only, e.g. `512|123|900|456|777`.
- Extended: slider/button fields, e.g. `s512|s123|s900|s456|s777|b1|b1|b0|b1|b1|b1`.

Slider and button counts are discovered from valid packets rather than hard-coded.

The application has been tested with:

- a legacy five-control controller;
- an extended five-control + six-button controller;
- hot-swap between controller families;
- disconnect/reconnect;
- Windows suspend/hibernate/resume;
- startup/tray behavior;
- RU/EN switching;
- Light/Dark/Auto theme behavior.

### Button actions implemented in the golden baseline

- Per-control soft mute/unmute.
- Media Play/Pause, Previous, Next, Stop via `WM_APPCOMMAND`.
- Windows Volume Up, Volume Down, Mute/Unmute.
- Custom hotkeys with Ctrl/Shift/Alt/Win and F1-F24, including F13-F24, sent with `SendInput`.
- Physical hotkey capture.
- Launch program/file.
- Open folder.
- Open URL.
- Run command.

Dynamic button payloads used by the dev line:

- `hotkey:<vk>:<modifier-mask>`
- `launch64:<base64>`
- `folder64:<base64>`
- `url64:<base64>`
- `command64:<base64>`

The dev filename is currently `button-actions.dev.json`; 1.0.0 will migrate this to `button-actions.json`.

## Config safety already present

The established `config.json` safety behavior must not be weakened while adding import/restore:

- first-run default config is written and immediately reloaded from JSON before the first-run UI continues;
- saves use a temporary JSON file;
- the temporary JSON is parsed/verified before replacing the live file;
- `config.previous.json` preserves the previous state;
- `config.last-good.json` preserves a verified known-good state;
- the live config is read back after save;
- recovery logic can restore a last-good completed configuration when the live file is missing/broken or unexpectedly resembles a fresh first-run config.

This behavior was introduced before the 0.9.0 work and is part of the compatibility contract for 1.0.0.

## Final tested reference firmware

The reference firmware intended for 1.0.0 uses the real tested 5x6 wiring:

- analog: `A0, A1, A2, A3, A4`;
- buttons: `9, 8, 7, 6, 5, 4`;
- `INPUT_PULLUP` (`0 = pressed`, `1 = released`);
- 9600 baud;
- direct `Serial.print()` output, no dynamic `String` packet construction;
- non-blocking `millis()` scheduling;
- `PACKET_INTERVAL_MS = 60`;
- per-button `BUTTON_DEBOUNCE_MS = 25`;
- immediate full-state packet after a debounced button-state change.

The older Arduino sketch currently present in the repository is historical and must be updated during consolidation without erasing the development history explaining the earlier approach.

## 1.0.0 scope still to implement

The 0.9.0 dev line is feature-complete and soak-tested. New work for 1.0.0 is intentionally limited to release/migration infrastructure:

1. Consolidate the known-good dev25 runtime into this branch as a distinct historical baseline commit.
2. Update the 0.9.0 development history and current reference firmware/documentation.
3. Rename the button action store to `button-actions.json` with safe one-time migration from `button-actions.dev.json`.
4. Add a portable backup/restore format, suggested filename:
   `MugenDeej_YYYY-MM-DD_HH-MM-SS.backup`.
5. Add an explicit backup schema/version independent from the application version.
6. Backup should contain user settings needed for migration (main config + button actions), not logs or transient machine/runtime files.
7. Restore flow must be safe: parse -> validate signature/schema -> migrate in memory -> validate result -> preserve current settings -> atomically apply restored settings.
8. Add the backup/restore UI next to the collapsed `Connection and diagnostics` section on the main window.
9. Keep RU/EN parity for all new UI text.
10. Clean release metadata/docs, version strings, examples, ignores and checksums.

Do not add unrelated new features before 1.0.0.

## Planned Git sequence

Keep changes reviewable instead of making one giant release commit:

1. **Consolidate internal 0.9.0 dev25 baseline** — tested runtime/code and historical docs only; no new backup feature yet.
2. **Add 1.0.0 settings migration foundation** — final button-action filename/schema migration.
3. **Add backup/restore** — `.backup` format, validation, recovery behavior and bilingual UI.
4. **Release cleanup** — version `1.0.0-rc1`, README/changelog/examples/.gitignore/reference firmware/checksums as appropriate.
5. Smoke-test the clean RC on both legacy and extended controllers, including at least one suspend/resume cycle.
6. Merge `release/1.0.0` into `main`, tag `v1.0.0`, then create the public release only after the smoke test passes.

## Release gate

Do not merge to `main` merely because the code builds. Before the public 1.0.0 release verify:

- legacy controller works without firmware changes;
- extended 5x6 controller and all configured button actions work;
- old dev button mappings migrate safely;
- backup can be created and restored;
- invalid/corrupt backup cannot destroy the active configuration;
- settings survive normal close/reopen;
- startup/tray behavior remains correct;
- suspend/resume remains correct;
- RU/EN switching and theme switching remain correct;
- no unexpected config loss, stuck mute/action state, unhandled exceptions or startup regressions.

## Working rule

When in doubt, preserve the known-good controller/USB/audio/config core and make the smallest change required. The 1.0.0 work is primarily about safe migration and packaging, not redesigning proven behavior.
