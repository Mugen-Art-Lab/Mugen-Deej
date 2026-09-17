# Mugen Deej — backup compatibility across controller topologies

This note captures the backup/restore rule for Legacy, Extended and Adaptive controllers before first-class toggle/encoder mappings are added.

## Current backup behavior

The existing portable backup format is `MugenDeejBackup`, `schemaVersion = 1`.

A v1 snapshot currently stores:

- the main `config` object;
- momentary `buttonActions`.

Restore validates the backup format/schema and button-action payload, creates an emergency pre-restore backup, writes the restored settings, and rolls back from the emergency copy if the restore operation itself fails.

At present there is no controller-topology compatibility check during restore. The backup is a settings snapshot, not a controller identity/profile file.

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

## Backup metadata for a future schema

When first-class toggle and encoder mappings are added, bump the backup schema rather than silently changing v1 semantics.

A future schema can store informational source metadata such as:

- app version;
- detected protocol generation at backup time;
- detected counts for sliders/buttons/toggles/encoders;
- mapping payloads for each control family;
- virtual-controller mapping data where applicable.

The source topology is diagnostic metadata, not a hard restore lock. Legacy and Extended have no stable device identity, and Adaptive v3 currently has no device-ID field, so compatibility can be judged only from protocol/topology, not from proof that the same physical controller is attached.

## Restore UX

If a controller is connected during restore, Mugen may show a concise compatibility summary such as:

- backup topology: Adaptive v3 — 5 sliders, 29 buttons, 2 toggles, 1 encoder;
- current topology: Legacy — 5 sliders;
- result: 5 slider settings active now; other mappings kept inactive.

A topology mismatch should normally be a warning/summary, not a hard error.

If no controller is connected, restore should still be allowed. Compatibility can be evaluated when a controller is next detected.

## Safety rules

- Keep the existing emergency pre-restore backup and rollback behavior.
- Continue validating backup schema before writing anything.
- Migrate older schemas explicitly; do not reinterpret v1 fields ambiguously.
- Hardware discovery remains authoritative for what controls exist in the live UI.
- Backup contents remain authoritative for saved user mappings/preferences, including dormant mappings for currently absent controls.
