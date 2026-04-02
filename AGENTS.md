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
