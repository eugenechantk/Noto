# macOS Vault Write Permission Root Cause

## Summary

The macOS save/delete failure was not a TextKit 2 editing bug. It was a sandbox permission bug on the user-picked vault.

The installed app was successfully receiving text edits and calling the save pipeline, but every coordinated write failed with:

- `NSCocoaErrorDomain Code=513`
- `Operation not permitted`

That means the app did not have write permission to the selected external folder, even though the folder appeared to open normally in the UI.

## Why This Happened

There were three overlapping problems:

1. The macOS app entitlement was wrong.
   - The app had `com.apple.security.files.user-selected.read-only`
   - It needed `com.apple.security.files.user-selected.read-write`
   - With read-only entitlement, all saves to a user-picked external vault fail, even if reading works.

2. A stale sandbox bookmark/token was already stored.
   - After the app had previously stored a broken or read-only vault access token, it kept reopening that vault.
   - The folder looked correct in the UI, but writes still failed.

3. The app previously reopened the vault silently without validating writability.
   - That created a fake-working state:
     - note list loads
     - existing files read correctly
     - editor accepts typing
     - saves and deletes fail later at write time

## Why Some Tests Still Passed

Some macOS tests used a direct test vault path override instead of the normal persisted bookmark flow.

That bypassed the real installed-app problem:

- tests exercised a deterministic local/direct path
- the installed app exercised the sandboxed external-vault bookmark path

So the editor/save logic could appear correct in tests while the real app still failed in production use.

## Correct Fix

The final fix had three parts:

1. Change the entitlement to read-write
   - `com.apple.security.files.user-selected.read-write = true`

2. Prefer bookmark-based resolution over remembered raw paths
   - A raw direct path is not enough to regain sandbox write access on relaunch.

3. Validate write access when resolving or setting an external vault
   - If the vault is not writable, do not silently continue.
   - Clear the broken saved external-vault state.
   - Force the user to re-pick the folder and re-grant access.

## Practical Rule

If the macOS app can read notes but cannot save or delete them:

1. Check for `Code=513` write failures first.
2. Verify the app entitlements include user-selected read-write access.
3. Assume the saved bookmark/token may be stale.
4. Re-pick the external vault folder after the entitlement fix.
5. Do not silently reopen a non-writable external vault.

## Outcome

After:

- fixing the entitlement
- validating writability on launch
- forcing a clean re-pick of the existing `Noto` folder

the installed macOS app could save edits again.
