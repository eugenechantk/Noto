# iOS Visual Evidence Audit
Verdict: PASS
Timestamp: 2026-08-29 15:21:01 HKT
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: cc-01a04c40-01a04c61 (83A006CE-E4A4-46AB-9B89-C2BA2754BB68)
App: com.eugenechan.Noto2

## Change Audited
Noto 2 Browse sorting change in `Noto2/Browse/ExplorerSorting.swift`: folders first by localized natural name, then notes by modified date descending.

## Success Criteria
| Criterion | Result | Evidence |
|---|---|---|
| Root Browse groups folders before pages. | PASS | `01-root-order.png`, `01-root-order-tree.json` |
| Root folders stay in localized natural alphabetical order. | PASS | `01-root-order.png`, `01-root-order-tree.json` show `Archive`, `Captures`, `Projects`. |
| Root pages are ordered newest edited to oldest. | PASS | `01-root-order.png`, `01-root-order-tree.json` show `Project Plan`, `Shopping List`, `Meeting Notes`, `Long Scrolling Note` after controlled mtimes were set to 2026-08-28, 2026-08-22, 2026-08-15, and 2026-08-01. |
| Nested folder behavior matches root behavior. | PASS | `02-captures-order.png`, `02-captures-order-tree.json` show `The State of Consumer AI - Usage` above `The $120K Blueprint...` after controlled mtimes were set to 2026-08-25 and 2026-08-08. |
| Browse row presentation and navigation remain intact. | PASS | `02-captures-order.png` shows the expected note rows in `Captures`; `03-root-return.png`, `03-root-return-tree.json` show successful back navigation to the unchanged root list. |

## Artifacts
- `01-root-order.png`
- `01-root-order-tree.json`
- `02-captures-order.png`
- `02-captures-order-tree.json`
- `03-root-return.png`
- `03-root-return-tree.json`

## Commands
- `flowdeck config get --json`
- `flowdeck context --json`
- `flowdeck apps --json`
- `flowdeck run -w /Users/eugenechan/dev/personal/Noto/Noto.xcodeproj -s Noto2 -S "83A006CE-E4A4-46AB-9B89-C2BA2754BB68" --json`
- `./.maestro/seed-vault.sh 83A006CE-E4A4-46AB-9B89-C2BA2754BB68 --bundle-id com.eugenechan.Noto2 --initial-tab browse`
- `touch` on seeded vault files to set controlled mtimes for root and `Captures` notes
- `flowdeck run --no-build -w /Users/eugenechan/dev/personal/Noto/Noto.xcodeproj -s Noto2 -S "83A006CE-E4A4-46AB-9B89-C2BA2754BB68" --json`
- `flowdeck ui simulator session start -S "83A006CE-E4A4-46AB-9B89-C2BA2754BB68" --json`
- `flowdeck ui simulator tap "Captures, 2 items" -S "83A006CE-E4A4-46AB-9B89-C2BA2754BB68" --json`
- `flowdeck ui simulator tap "Browse" -S "83A006CE-E4A4-46AB-9B89-C2BA2754BB68" --json`

## Notes
- This audit independently verified the visual ordering and navigation behavior on the simulator. It did not visually exercise the equal-date or untitled-note tie-break cases from the feature doc; those remain covered by the reported automated tests rather than by this visual audit.
- `flowdeck run --no-build` still performed an install step in this environment, but the seeded simulator container remained intact and the post-seed ordering matched the controlled timestamps on-screen.
