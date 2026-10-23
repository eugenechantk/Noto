# Note sharing release — 2026-10-24

Source: `3c2409f966e8afecc15975110bbee8210e6fb4a2`, pushed to `origin/main`.
Version: `0.2.0`, build `202610240135`.

## Result

Noto on Pro and Air runs the same signed, 23-file bundle at `/Applications/Noto.app`.
Both executable hashes and process paths match the release manifest.
Previous installations remain in `~/Library/Application Support/Noto/ReleaseBackups/` on each Mac.
Noto 2 is available to internal TestFlight testers.
Apple confirms `VALID` on the highest `0.2.0` train and `IN_BETA_TESTING`.
The canonical verification lane passed at 01:58:53 HKT.

Sharing sends the full Markdown body, including current edits, without frontmatter or template metadata.
Every saved-note editor has a direct Share action. Context actions use the chosen note.

## Verification

- The clean checkout passes 180 vault tests and all 10 embedding tests, including real model inference.
- The final IPA's app and both extensions pass signature, profile, version, build, and model checks.
- Both desktop installations pass strict signature and complete bundle checks.
- The earlier independent iPhone audit verified exact 2,555-byte and 101-byte clipboard results.
- The earlier 24-case app regression suite passed. A fresh clean-host rerun did not complete; see `release-plan.json`.
- Native Mac sharing still needs a password unlock for final system-service verification. Installed Pro UI was captured.

The first candidate omitted the ignored Granite model. Its upload was canceled, and both Mac candidates were replaced.
The corrected artifacts contain model weights that match the source. The canceled first candidate is absent from Apple's final build list.

## Changed files

The feature commit created six files and edited twelve. It deleted none.
The grouped source list is in `../../feature/share-note-markdown.md`.
Unrelated working-tree changes, local secrets, binaries, and full audit captures remain uncommitted.

The release proof creates six files: this receipt, `testflight-status.json`, `testflight-ipa.json`,
`mac-bundle-manifest.json`, `pro-install-result.json`, and `air-install-result.json`.
It edits or deletes no source files.
