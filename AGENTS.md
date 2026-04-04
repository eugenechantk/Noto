# Workspace Agent Instructions

- Send macOS banner notifications only in these cases:
  `1)` when work is finished, or
  `2)` when user input is required to proceed.
- Command:
  `~/.codex/bin/codex-notify "<status + needed input>" "Noto" "/Users/eugenechan/dev/personal/Noto"`
- Keep title as `Codex-Noto`.
- For simulator-based testing or automation, always use an isolated simulator instance instead of a shared booted device.
- When running Maestro in this repo, prefer `scripts/run_maestro_isolated.sh` so parallel agents do not collide on the same simulator.
- At the end of any completed task, explicitly report:
  `1)` the actions taken, and
  `2)` the files changed, grouped as created, edited, or deleted when applicable.
- Keep that completion report concise and factual. If no files changed, say so.
- When the user reports a bug or asks for a code change, do the work directly unless blocked by a real ambiguity or a destructive tradeoff that requires confirmation.
- Do not ask for permission to make routine code changes, tests, or verification runs when the user has already asked for the problem to be solved.
- For macOS external-vault save/delete bugs, do not assume the editor is at fault first. Check sandbox entitlements, security-scoped bookmark resolution, and actual write errors before changing editor code.
- For multi-window note behavior, distinguish same-process window sync from external filesystem sync. Same-app windows should use the in-process sync path; `VaultFileWatcher` is only the fallback for external changes.
