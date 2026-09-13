# Mugen Deej 1.0.0 release worklog

Branch: `release/1.0.0`

This is the continuity anchor for the 1.0.0 work. Read this file first when resuming development in a new chat/session.

## Release history policy

- `0.8.7` is the last public release of the old line.
- `0.9.0-dev1` through `0.9.0-dev25` are an internal development line and must remain preserved in Git/documentation.
- `0.9.0-dev25` is the tested golden baseline from which 1.0.0 work started.
- `1.0.0` is intended to be the first public release of the extended-controller architecture.
- Do not erase/rewrite the 0.9.0 development history simply because it was never published.

## Golden pre-1.0 baseline

Known-good portable runtime:

`Mugen-Deej-0.9.0-dev25-soak-fixed`

The tested golden `MugenDeej.ps1` is committed at the root of `release/1.0.0`. The staged dev patches are deliberately applied only to the packaged copy until the new behavior has been tested.

Golden baseline characteristics:

- legacy numeric protocol and extended `s...|b...` protocol auto-detection;
- slider/button counts discovered from packets rather than hard-coded;
- live button UI and soft mute;
- media actions via `WM_APPCOMMAND`;
- Windows volume actions;
- custom hotkeys including F13-F24 via `SendInput`;
- physical hotkey capture;
- launch program/file, open folder, open URL, run command;
- polished RU/EN UI with Auto/Light/Dark theme support;
- tray/startup fixes;
- suspend/hibernate/resume support;
- final reference Arduino firmware with A0-A4, buttons 9..4, 9600 baud, 60 ms full-state heartbeat and 25 ms firmware button debounce.

The 0.9.0 UI was heavily refined through the dev line: layout, spacing, card geometry, owner-drawn controls, focus behavior, theme parity, localization repaint, settings hints and final slider/button settings ergonomics were all iterated before the golden dev25 baseline.

## Config safety contract inherited by 1.0.0

Do not weaken this behavior:

- first-run config is written and immediately reloaded before the first-run UI continues;
- saves use a temporary JSON file;
- the temporary file is parsed/validated before replacing the live config;
- `config.previous.json` preserves the previous state;
- `config.last-good.json` preserves a verified known-good state;
- the live file is read back after save;
- recovery logic can restore a valid completed last-good config when the live config is missing/broken or unexpectedly looks like a fresh first-run config.

## 1.0.0 development stages

### `1.0.0-dev1` — button action filename migration

Final filename:

`button-actions.json`

Legacy internal-dev filename:

`button-actions.dev.json`

Rules:

- final file wins if it already exists;
- legacy file is parsed and schema-validated before migration;
- migration writes through a temporary file and reads the new file back;
- legacy file is retained as a rollback copy and is not deleted;
- after migration, saves go to `button-actions.json`;
- if migration cannot write the final file, legacy settings remain usable for the current run and migration can be retried later.

A GitHub Actions artifact was successfully built from the staged dev1 patch.

### `1.0.0-dev2` — portable backup/restore

Added a main-window `Backup & restore / Резервная копия` button next to `Connection and diagnostics`.

Backup filename:

`MugenDeej_YYYY-MM-DD_HH-MM-SS.backup`

Backup format:

- signature: `MugenDeejBackup`;
- independent `schemaVersion: 1`;
- metadata (`createdAt`, `createdBy`);
- full main config;
- button actions with their own version field.

Restore safety:

- parse and validate backup before changing live data;
- create `MugenDeej_PreRestore_YYYY-MM-DD_HH-MM-SS.backup` first;
- save restored config through the established config safety pipeline;
- save button actions through their verified writer;
- if restore fails, attempt rollback from the pre-restore snapshot.

Tested successfully on the legacy-controller PC using a real dev25 config and a clean-folder restore scenario.

### `1.0.0-dev3` — themed backup dialogs and automatic restart

Replaced backup MessageBoxes with themed Mugen Deej dialogs that follow the current effective theme.

After a successful restore the app asks whether to restart immediately. `Yes` performs a normal shutdown and relaunches `MugenDeej.exe` automatically.

### `1.0.0-dev4` — one-shot visible launch after restore

Problem found during real testing: a restored config with `startMinimized=true` caused the automatic post-restore restart to disappear immediately into the tray, making it unclear whether the restore had succeeded.

Fix:

- the restart after restore gets a one-shot visible-launch marker;
- that one restart shows the main window regardless of the restored `startMinimized` value;
- the saved setting itself is not changed;
- the next ordinary launch again obeys `startMinimized` normally.

Real test PASS:

- clean portable folder;
- first-run language selection;
- restore a real backup with RU + dark theme + existing slider mappings;
- pre-restore emergency backup created correctly;
- automatic restart performed;
- restored window appeared visibly once;
- normal later relaunch returned to start-minimized/tray behavior;
- current config, previous and last-good stabilized on the restored state;
- no restore rollback or unhandled exception occurred.

The test log showed an isolated malformed legacy serial packet shape after reconnect (`legacy:6:0` instead of `legacy:5:0`); it was ignored and controller operation continued. Treat separately if it becomes recurrent.

### `1.0.0-dev5` — self-extracting Setup EXE packaging

Runtime behavior is the tested dev4 behavior; dev5 is primarily a packaging milestone.

The package builder now produces both:

- `Mugen-Deej-1.0.0-dev5-Portable.zip`
- `Mugen-Deej-1.0.0-dev5-Setup.exe`

plus SHA-256 sidecar files.

Setup architecture:

- custom self-contained Go wrapper;
- embeds the exact portable ZIP produced by the same build run;
- opens a bilingual PowerShell/WinForms setup wizard;
- user chooses the destination folder;
- default destination is outside Program Files (`%LOCALAPPDATA%\Mugen Deej`);
- warns if Program Files / Program Files (x86) is selected because Mugen Deej stores config next to the app and may need elevated write permissions there;
- optional desktop shortcut (checked by default);
- optional launch after setup (checked by default);
- if an existing Mugen Deej folder is selected, setup updates application files while leaving user configs/logs/backups alone because they are not present in the portable payload;
- setup itself does not register Mugen Deej as an installed Windows application and does not create an uninstall registry entry;
- final setup page explains manual removal.

Important startup caveat documented in the setup UI:

The setup program itself does not create application install registry entries. However, if the user later enables `Start Mugen Deej with Windows` inside Mugen Deej, the application uses the current-user Windows `Run` entry. Before manually deleting the portable/application folder, the user should disable that checkbox in Mugen Deej so the stale startup entry is removed.

The setup source is under `src/setup/`. `tools/Build-PortableRelease.ps1` now parses both the staged app script and setup script with Windows PowerShell 5.1, builds the normal launcher, creates the portable ZIP, then embeds that exact ZIP into the Setup EXE.

## Semi-automatic packaging

Manual GitHub workflow:

`Actions -> Build portable package -> Run workflow -> release/1.0.0`

The branch workflow uploads one artifact containing the portable ZIP/checksum and Setup EXE/checksum.

Local entry point remains:

`BUILD_PORTABLE.cmd`

The builder never publishes a GitHub Release automatically.

## Tests still needed before RC

1. Build and test `1.0.0-dev5` Setup EXE:
   - clean install to a user-selected non-Protected folder;
   - desktop shortcut creation on/off;
   - launch-after-setup on/off;
   - Program Files warning/cancel path;
   - update over an existing portable folder while preserving config/button-actions/backups;
   - verify Setup does not create an Installed Apps/uninstall entry.
2. Test backup/restore on the extended 5-slider + 6-button controller PC:
   - migrate a real `button-actions.dev.json` with non-`none` actions;
   - create backup containing those actions;
   - change actions;
   - restore and restart;
   - verify all physical button actions return correctly.
3. Re-test startup/tray and at least one suspend/resume cycle after final consolidation.
4. Promote the tested staged runtime into the root `MugenDeej.ps1` before RC so release packaging no longer depends on the dev patch chain.
5. Release cleanup: README/README_RU, changelog, screenshots if needed, examples, version `1.0.0-rc1`, final checksums and smoke test.

## Release gate

Do not merge to `main` merely because packages build. Before public `v1.0.0` verify:

- legacy controller works without firmware changes;
- extended 5x6 controller and real button actions work;
- old `.dev.json` button mappings migrate safely;
- backup create/restore and emergency rollback behavior work;
- corrupt/invalid backup cannot destroy active settings;
- post-restore one-shot visible restart works while normal start-minimized behavior remains intact;
- Setup EXE installs/updates without registering a normal Windows installation;
- startup/tray behavior remains correct;
- suspend/resume remains correct;
- RU/EN and Light/Dark/Auto remain correct;
- no config loss, stuck mute/action state or unhandled exceptions.

## Working rule

Preserve the proven controller/USB/audio/config core and make the smallest change required. The remaining 1.0.0 work is release, migration, backup and packaging infrastructure — not a redesign of the known-good runtime.
