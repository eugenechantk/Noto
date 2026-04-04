# iCloud Read/Write Rules

## Summary

Noto stores notes as markdown files inside a user-selected vault. When that vault lives in iCloud Drive, the app must handle two different concerns:

- **access permission**
- **file availability**

Those concerns differ between macOS and iOS.

## macOS

On macOS, the main risk is **sandbox access**.

Rules:

- External vaults require `com.apple.security.files.user-selected.read-write`
- The saved security-scoped bookmark is the real access token
- A remembered raw path is not enough to regain write access after relaunch
- The app must validate writability when resolving or setting an external vault
- If the vault is not writable, the app must clear the broken saved state and force a folder re-pick

Typical failure:

- notes load normally
- typing works visually
- save/delete fails with `NSCocoaErrorDomain Code=513`

That is not an editor bug. It is a permission bug.

## iOS

On iOS, the main risk is **file availability / iCloud metadata drift**.

Rules:

- Do not trust iCloud download metadata as the primary gate for opening a note
- Try a real coordinated read first
- If the file is readable, open it immediately
- Only fall back to the iCloud download flow when the file is genuinely unreadable
- If metadata says the file is current but the read still fails, surface a real failure instead of pretending it still needs download

Typical failure:

- some notes show `Downloading from iCloud...` or a download error
- but the same files already exist locally and are readable

That is not a vault permission bug. It is a read-path decision bug.

## Shared Principle

For iCloud-backed markdown notes:

- prefer real file access checks over inferred state
- use metadata as a hint, not the source of truth

Concrete rule:

- **macOS write path**: trust actual write success
- **iOS read path**: trust actual read success

## Current App Policy

- `MarkdownNoteStore` is the persistence boundary for note reads and writes
- `CoordinatedFileManager` performs the actual coordinated filesystem operations
- `NoteEditorScreen` handles note loading and editor lifecycle

Platform split:

- macOS: protect against invalid external-vault access tokens
- iOS: protect against misleading iCloud download state for readable files
