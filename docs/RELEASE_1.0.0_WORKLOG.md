# Mugen Deej 1.0.0 release worklog

Branch: `release/1.0.0`

This document is the continuity anchor for the 1.0.0 release work. Keep it updated after significant changes so a future development session can recover the project state without relying on chat history.

## Release history policy

- `0.8.7` remains the last public release of the old line.
- `0.9.0-dev1` through `0.9.0-dev25` are an internal development line, not a public release.
- The 0.9.0 development history must be preserved in Git/documentation rather than rewritten as if it never existed.
- `1.0.0` will be the first public release of the extended-controller architecture.

## Known-good pre-1.0 baseline

The golden runtime baseline is the tested portable build:

`Mugen-Deej-0.9.0-dev25-soak-fixed`

It is the source of truth for the internal 0.9.0 line and must remain recoverable while 1.0.0 work proceeds.

Important local development artifacts used to reconstruct the history:

- `Mugen-Deej-0.9.0-dev25-soak-fixed.zip` — the tested runtime folder.
- `SomethingStrange.zip` — collected dev1..dev25 installers/patches and release-candidate notes.
- `Mugen_Deej_0.9.0_RELEASE_CANDIDATE_NOTES.md` — detailed RC summary and test/release checklist.
- `MugenDeej_Reference_Extended_5x6_Nano.ino` — final tested reference firmware.

Do not commit personal runtime data from the golden portable folder (`config*.json`, logs, user button mappings, local backups, etc.).

### Consolidation status

The tested `0.9.0-dev25` application script is committed directly as the root `MugenDeej.ps1` in `release/1.0.0`. The final tested Arduino reference firmware and the preserved 0.9.0 development history are also present in the branch.

A semi-automatic portable packaging path is available through `tools/Build-PortableRelease.ps1`, `BUILD_PORTABLE.cmd`, and the manually triggered `Build portable package` GitHub Actions workflow. It produces a ZIP and checksum but does not publish a release automatically.

The first control build of `0.9.0-dev25` was successfully produced through GitHub Actions before any 1.0.0 runtime changes were introduced.

## Current 1.0.0 development stage

Current development target: `1.0.0-dev1`.

`dev1` is intentionally limited to the button-action settings filename migration:

- final filename: `button-actions.json`;
- legacy filename: `button-actions.dev.json`;
- if the final file already exists, it is authoritative and the legacy file is ignored;
- if only the legacy file exists, it is parsed and schema-validated before migration;
- the new file is written through a temporary file and read back before migration is accepted;
- the legacy file is preserved as a rollback copy and is not deleted;
- if migration cannot write the new file, the legacy mapping can still be loaded for that run and migration is retried on a later launch;
- saves after migration go only to `button-actions.json` and are verified after writing.

For this first test, the byte-for-byte golden root `MugenDeej.ps1` is deliberately left untouched. `VERSION.txt` is `1.0.0-dev1`, and `tools/patches/Apply-1.0.0-dev1.ps1` transforms a staged copy during portable packaging. This lets the migration be tested on real hardware before the large generated runtime file is promoted back into the repository. Once `dev1` passes, the tested staged `MugenDeej.ps1` should replace the root file and the builder will automatically return to its normal direct-copy path because the source version will match `VERSION.txt`.

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

## 1.0.0 scope still to implement

The 0.9.0 dev line is feature-complete and soak-tested. New work for 1.0.0 is intentionally limited to release/migration infrastructure:

1. Finish and validate the `button-actions.json` migration in `1.0.0-dev1`.
2. Add a portable backup/restore format, suggested filename:
   `MugenDeej_YYYY-MM-DD_HH-MM-SS.backup`.
3. Add an explicit backup schema/version independent from the application version.
4. Backup should contain user settings needed for migration (main config + button actions), not logs or transient machine/runtime files.
5. Restore flow must be safe: parse -> validate signature/schema -> migrate in memory -> validate result -> preserve current settings -> atomically apply restored settings.
6. Add the backup/restore UI next to the collapsed `Connection and diagnostics` section on the main window.
7. Keep RU/EN parity for all new UI text.
8. Clean release metadata/docs, version strings, examples, screenshots and checksums.

Do not add unrelated new features before 1.0.0.

## Planned Git sequence

Keep changes reviewable instead of making one giant release commit:

1. **Completed: consolidate internal 0.9.0 dev25 baseline** — tested runtime, final reference firmware, historical docs, matching metadata and a reproducible/semi-automatic portable package builder.
2. **In test: 1.0.0-dev1 settings migration foundation** — final button-action filename/schema migration using a staged patch over the golden runtime.
3. **Promote tested dev1 runtime** — after the artifact passes migration/restart/button tests, replace root `MugenDeej.ps1` with the tested staged script.
4. **Add backup/restore** — `.backup` format, validation, recovery behavior and bilingual UI.
5. **Release cleanup** — version `1.0.0-rc1`, README/changelog/examples/screenshots/checksums as appropriate.
6. Smoke-test the clean RC on both legacy and extended controllers, including at least one suspend/resume cycle.
7. Merge `release/1.0.0` into `main`, tag `v1.0.0`, then create the public release only after the smoke test passes.

## dev1 test checklist

Use a copy of a real dev25 portable folder that still contains `button-actions.dev.json`.

- Build/download `Mugen-Deej-1.0.0-dev1-Portable.zip`.
- Copy the old `button-actions.dev.json` into the fresh dev1 portable folder before first launch.
- Launch with the extended controller.
- Verify `button-actions.json` is created automatically.
- Verify `button-actions.dev.json` remains present and unchanged.
- Verify all existing button assignments still work.
- Change at least one button assignment and click Save.
- Restart Mugen Deej and verify the changed assignment persists from `button-actions.json`.
- Optionally rename/move the legacy `.dev.json` after successful migration and verify the new file is sufficient by itself.
- Confirm the main slider configuration, tray/startup behavior, language/theme switching and controller detection are unchanged.

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
