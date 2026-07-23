# GitHub repository setup

## Repository

- **Name:** `Mugen-Deej`
- **Description:** `A portable bilingual Windows client for deej-compatible USB audio controllers.`
- **Visibility at first:** Private
- **Initialize with README:** No — this folder already contains the repository files.
- **License:** Do not add another one in the GitHub form; `LICENSE` is already included.

## Suggested topics

`deej`, `audio-controller`, `volume-mixer`, `windows`, `arduino`, `powershell`, `serial-port`, `core-audio`, `ch340`, `desktop-app`

## Recommended repository settings

- Enable Issues.
- Keep Discussions disabled until the public launch unless you already want a community area.
- Disable Wiki unless it will actually be maintained; the `docs/` folder is enough for now.
- Set `main` as the default branch.
- Add a short social preview later using the icon and a clean screenshot.

## Initial release

Create a draft release tagged `v0.8.3` with title `Mugen Deej 0.8.3`.
Paste `docs/RELEASE_NOTES_0.8.3.md` into the release notes and attach:

- `Mugen-Deej-0.8.3.zip`
- `Mugen-Deej-0.8.3.zip.sha256`

Keep the release as a draft while the repository is private. Publish it when the repository is opened.

## Before changing the repository to public

- Check the complete Git history for personal data, tokens, absolute paths, and private screenshots.
- Confirm that `config.json`, logs, and driver installers are not committed.
- Replace the placeholder security contact in `SECURITY.md`.
- Verify the clean-install experience on a second Windows computer.
- Review README screenshots and both language versions.
- Publish the `v0.8.3` release or create the first stable release later without changing the currently tested application version merely for appearance.

## Recommended repository metadata

**Description**

```text
Portable bilingual Windows client for deej-compatible Arduino audio controllers.
```

**Topics**

```text
deej arduino audio-mixer volume-control windows powershell winforms serial ch340
```

Before making the repository public, verify that the relationship-to-deej section is visible near the top of both README files and that `THIRD_PARTY_NOTICES.md` is included in the first commit.
