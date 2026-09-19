# Mugen Deej — backup compatibility across controller topologies

This note captures the backup/restore rule for Legacy, Extended and Adaptive controllers, including first-class toggle/encoder mappings introduced in the current development branch.

## Product decision

Backups are **universal Mugen Deej settings backups**, not per-protocol or per-device backup variants.

A user should not need to remember whether a given file was a "Legacy backup", "Extended backup" or "Adaptive backup". The backup file remains one generic Mugen Deej backup type. Protocol/topology information may be stored inside the file as metadata for diagnostics and restore summaries, but it is not part of the user-facing backup identity.

The filename can therefore remain generic/time-based, for example:

`MugenDeej_2026-09-18_01-30-00.backup`

The internal `schemaVersion` is an implementation/migration detail and should not become something users have to manage manually.

## Current development behavior

Current development builds write portable backups as `MugenDeejBackup`, `schemaVersion = 2`.

A v2 snapshot stores:

- the main `config` object;
- momentary `buttonActions`;
- first-class Adaptive toggle/encoder action mappings;
- foreground-application profiles for ordinary button mappings plus Adaptive toggle/encoder mappings, when present;
- virtual Xbox button/stick-direction mappings as ordinary strings inside Global/per-profile button action arrays;
- informational source protocol/topology metadata.

Restore accepts both schema v1 and v2. A stable-era v1 backup restores its existing global config and `buttonActions` normally. Because v1 has no typed-action or application-profile payload, restoring v1 intentionally preserves whatever current toggle/encoder mappings and application profiles already exist rather than treating absent newer fields as an instruction to erase them.

Current v2 backups include the optional versioned application-profile payload. Older v2 files created before profiles existed remain valid; if `adaptiveProfiles` is absent, the current application profiles are preserved. #89/#90-era v2 profiles may exist but have no per-profile `buttons` member. Those profiles remain valid: missing/empty per-profile button mappings inherit the restored Global `buttonActions` until the user explicitly edits and saves buttons for that application.

#101 digital Xbox stick-direction mappings do not require a new backup schema. They use the same button-action string slots already carried by stable-era `buttonActions` and by optional per-profile `buttons` arrays. Older backups simply cannot contain those newer action strings; restoring them behaves exactly as before. A current backup containing a digital stick mapping remains a normal v2 Mugen Deej backup.

Restore continues to validate the backup before writing, creates an emergency pre-restore backup, and rolls back from that emergency copy if restore itself fails. The current emergency snapshot is v2 and includes both typed mappings and Adaptive application profiles.

Source topology is used only for a human-readable restore summary. The backup remains a settings snapshot, not a controller identity/profile file.

## Why Adaptive makes this important

Adaptive v3 can report arbitrary controller shapes. The current 5 sliders / 29 buttons / 2 toggles / 1 encoder Uno fixture is only one regression topology.

A user may legitimately create a backup while using a large Adaptive panel and later restore it while a Legacy controller, a smaller Extended controller, another Adaptive topology, or no controller at all is connected. The reverse is also valid: a stable v1.0.0 backup made with Legacy or Extended hardware must restore in the current build without requiring Adaptive firmware.

Restore must therefore never assume that the hardware present at restore time has the same protocol generation or control counts as the hardware used when the backup was created.

## Required compatibility model

Backups should remain portable settings snapshots rather than being rejected merely because the current controller differs.

Recommended behavior:

1. Restore global application settings normally.
2. Restore mappings/configuration by control family and index.
3. Apply only mappings for physical controls that currently exist.
4. Keep mappings for currently absent controls dormant rather than deleting them.
5. If the original controller/topology returns later, its stored mappings should become usable again.
6. Never fabricate missing controls in the main UI merely because a backup contains mappings for them.
7. Never truncate/destroy a larger saved mapping set just because a smaller controller is connected.

Example: restoring a backup made from a 5/29/2/1 Adaptive panel while a 5-slider Legacy controller is connected should not make the Legacy UI show buttons/toggles/encoders. The five compatible slider settings may be used; button/toggle/encoder mappings remain stored but inactive.

## Schema v2 metadata

The current development v2 schema records informational source metadata including the app version, detected protocol generation, and detected slider/button/toggle/encoder counts. It includes Global typed mappings for toggles/encoders plus an optional versioned `adaptiveProfiles` payload for foreground-application overrides. Profile objects may contain `buttons`, `toggles`, and `encoders`; the `buttons` member is optional for backward compatibility with #89/#90-era profile files. The historical internal filename/schema name remains `adaptive-profiles.json`/version 1 for compatibility even though button overrides are now usable with Extended controllers too.

The source topology is diagnostic metadata, not a hard restore lock. Legacy and Extended have no stable device identity, and Adaptive v3 currently has no device-ID field, so compatibility can be judged only from protocol/topology, not from proof that the same physical controller is attached.

Virtual-controller mapping data remains in its existing configuration path for this milestone; if that is later folded into portable backup semantics it should be added through an explicit future schema migration rather than silently changing v2.

## Restore UX

If a controller is connected during restore, Mugen may show a concise compatibility summary such as:

- backup topology: Adaptive v3 — 5 sliders, 29 buttons, 2 toggles, 1 encoder;
- current topology: Legacy — 5 sliders;
- result: 5 slider settings active now; other mappings kept inactive.

A topology mismatch should normally be a warning/summary, not a hard error.

If no controller is connected, restore should still be allowed. Compatibility can be evaluated when a controller is next detected.

The user-facing wording should describe the outcome, not ask the user to understand backup schema numbers or choose a protocol-specific backup type.

## Safety rules

- Keep the existing emergency pre-restore backup and rollback behavior.
- Continue validating backup schema before writing anything.
- Migrate older schemas explicitly; do not reinterpret v1 fields ambiguously.
- Keep `button-actions.json` as the Global button mapping store; application profiles override it only when a matching profile actually contains button mappings.
- Missing per-profile `buttons` is inheritance, not deletion: fall back to Global.
- Adding new button-action kinds (such as #101 digital stick directions) should not force a backup schema bump while they fit the existing versioned action-string container.
- Legacy remains unaffected by button profiles because its discovered button count is zero; Extended requires no firmware change to use PC-side button profiles.
- Hardware discovery remains authoritative for what controls exist in the live UI.
- Backup contents remain authoritative for saved user mappings/preferences, including dormant mappings for currently absent controls.
- Do not create separate Legacy/Extended/Adaptive backup file types unless a future feature introduces a genuinely different export concept.
