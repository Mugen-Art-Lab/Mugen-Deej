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
- Adaptive foreground-application profiles for toggle/encoder mappings, when present;
- informational source protocol/topology metadata.

Restore accepts both schema v1 and v2. A v1 backup has no typed-action payload, so restoring v1 intentionally preserves whatever current toggle/encoder mappings and application profiles already exist rather than treating their absence as an instruction to erase them. Current v2 backups also include Adaptive application profiles. Older v2 files created before profiles existed remain valid; if their optional `adaptiveProfiles` payload is absent, the current application profiles are preserved.

Restore continues to validate the backup before writing, creates an emergency pre-restore backup, and rolls back from that emergency copy if restore itself fails. The current emergency snapshot is v2 and includes both typed mappings and Adaptive application profiles.

Source topology is used only for a human-readable restore summary. The backup remains a settings snapshot, not a controller identity/profile file.

## Why Adaptive makes this important

Adaptive v3 can report arbitrary controller shapes. The current 5 sliders / 29 buttons / 2 toggles / 1 encoder Uno fixture is only one regression topology.

A user may legitimately create a backup while using a large Adaptive panel and later restore it while a Legacy controller, a smaller Extended controller, another Adaptive topology, or no controller at all is connected.

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

The current development v2 schema records informational source metadata including the app version, detected protocol generation, and detected slider/button/toggle/encoder counts. It includes typed mappings for toggles and encoders plus an optional versioned `adaptiveProfiles` payload for foreground-application overrides.

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
- Hardware discovery remains authoritative for what controls exist in the live UI.
- Backup contents remain authoritative for saved user mappings/preferences, including dormant mappings for currently absent controls.
- Do not create separate Legacy/Extended/Adaptive backup file types unless a future feature introduces a genuinely different export concept.
