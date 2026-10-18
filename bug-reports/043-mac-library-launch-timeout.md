# Bug 043: Mac library times out on the production vault

## Status: VERIFIED

## Description

The installed 0.2.0 Release app shows an empty library and a vault-loading timeout after a normal launch. The saved vault bookmark resolves, and the desktop workspace opens.

## Steps to reproduce

1. Install the signed Mac Release app from commit f704b3a.
2. Launch /Applications/Noto.app without preview settings.
3. Wait for the initial library scan.
4. Observe the timeout alert and zero visible notes.

## Investigation

The vault contains 1,181 Markdown files and 17 folders. A read-only directory scan takes 0.002 seconds. The desktop snapshot reads a coordinated prefix of every note, then abandons the entire result after eight seconds. The small preview fixture does not establish this real-vault behavior.

Evidence: .codex/feature/noto-0.2.0-release/pro-installed.png and pro-tree.json.

## Root cause confirmed

Each coordinated prefix read costs about 0.7 seconds in the real iCloud vault. The snapshot waits for every note before returning, so it exceeds the eight-second budget. Metadata loading takes only 0.082 seconds.

## Correction and criteria

The snapshot uses best-effort local previews and keeps unavailable notes in the list. Full document loading and writes keep coordination.

- The preview regression fails before the correction and passes after it.
- The full NotoVault suite must pass, including unavailable-row and byte-limit checks.
- The installed Mac Release app must display its real library without the timeout alert.
- The installed version, signature, and bundle bytes must match the final release.

The corrected read-only package scan returns 1,181 available notes in 3.078 seconds. All 152 NotoVault tests and 32 Mac app tests pass. Independent verification of the installed Release app confirms the populated real library, restored editor, and absence of the timeout. Its version is 0.2.0 (202610181301); its signature and all 23 bundle file hashes match the frozen release. Evidence: .codex/feature/noto-0.2.0-release/independent-mac-audit/evidence.md.
