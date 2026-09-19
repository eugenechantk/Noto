# iOS Visual Evidence Audit
Verdict: PARTIAL
Timestamp: 2026-09-04 19:28:52 HKT
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: iPhone `cc-01a06c17-01a06c23` (`89B84671-665D-4621-BF1A-513D6050C482`); iPad attempt `cc-01a06c17-ipad` (`C876CB9D-ED9F-45E0-9111-C14F951B84A3`)
App: com.eugenechan.Noto2

## Change Audited
Noto 2 Digest direct-input update: remove legacy Add to/Create buttons from the Digest card, autofocus the add-to search field on right-swipe, and autofocus an empty create title field on up-swipe.

## Success Criteria
| Criterion | Result | Evidence |
| --- | --- | --- |
| 1. With an inbox capture, swipe right, do not tap, immediately type, and verify query text/results update. | PASS on iPhone | `02a-iphone-add-to-initial.png` shows the right-swipe Add to sheet before typing. `02-iphone-add-to-typed.png` shows `meet` entered without a tap and the list filtered to `Meeting Notes`. |
| 2. Swipe up, verify title is empty, do not tap, immediately type, and verify title updates. | PASS on iPhone | `03a-iphone-create-initial.png` shows the Create sheet with an empty `Note title` field and visible caret. `03-iphone-create-typed.png` shows `Audit note` typed without a tap and the filename preview updated to `Audit note.md`. |
| 3. Digest card has no Add to/Create buttons, but both right/up gestures still open destinations. | PASS on iPhone | `01-iphone-digest-card.png` shows the Digest card with only the create/discard targets and no legacy Add to/Create buttons. `02a-iphone-add-to-initial.png` and `03a-iphone-create-initial.png` prove right-swipe and up-swipe still open their destinations. |
| 4. Check layout on both an isolated iPhone and iPad simulator if tooling permits. | PARTIAL | iPhone completed with the artifacts above. iPad provisioning succeeded, but FlowDeck iPad capture failed: `ipad-tooling-limitation.txt` records `flowdeck apps --json` returning zero running apps after launch and repeated `Failed to parse accessibility tree` errors from `flowdeck ui simulator screen`. |

## Artifacts
- `01-iphone-digest-card.png`
- `01-iphone-digest-card-tree.json`
- `02a-iphone-add-to-initial.png`
- `02a-iphone-add-to-initial-tree.json`
- `02-iphone-add-to-typed.png`
- `02-iphone-add-to-typed-tree.json`
- `03a-iphone-create-initial.png`
- `03a-iphone-create-initial-tree.json`
- `03-iphone-create-typed.png`
- `03-iphone-create-typed-tree.json`
- `capture-draft.txt`
- `ipad-tooling-limitation.txt`

## Commands
- `flowdeck config get --json`
- `flowdeck run -s Noto2 -S "89B84671-665D-4621-BF1A-513D6050C482" --json`
- `./.maestro/seed-vault.sh 89B84671-665D-4621-BF1A-513D6050C482 --bundle-id com.eugenechan.Noto2`
- `./.maestro/seed-vault.sh 89B84671-665D-4621-BF1A-513D6050C482 --bundle-id com.eugenechan.Noto2 --draft-file /Users/eugenechan/dev/personal/Noto/.codex/evidence/20260904-192132-ios-visual-audit/capture-draft.txt`
- `flowdeck ui simulator session start -S "89B84671-665D-4621-BF1A-513D6050C482" --json`
- `flowdeck ui simulator tap "Noto 2" -S "89B84671-665D-4621-BF1A-513D6050C482" --json`
- `flowdeck ui simulator swipe --from 210,420 --to 385,420 --duration 0.35 -S "89B84671-665D-4621-BF1A-513D6050C482" --json`
- `flowdeck ui simulator tap --point 138,810 --geometry points -S "89B84671-665D-4621-BF1A-513D6050C482" --json`
- `flowdeck ui simulator swipe --from 205,445 --to 385,445 --duration 0.35 -S "89B84671-665D-4621-BF1A-513D6050C482" --json`
- `flowdeck ui simulator type "meet" -S "89B84671-665D-4621-BF1A-513D6050C482" --json`
- `flowdeck ui simulator swipe --from 205,445 --to 205,180 --duration 0.35 -S "89B84671-665D-4621-BF1A-513D6050C482" --json`
- `flowdeck ui simulator type "Audit note" -S "89B84671-665D-4621-BF1A-513D6050C482" --json`
- `flowdeck simulator create --name "cc-01a06c17-ipad" --device-type "com.apple.CoreSimulator.SimDeviceType.iPad-mini-A17-Pro" --runtime "iOS 26.3" --json`
- `flowdeck run -s Noto2 -S "C876CB9D-ED9F-45E0-9111-C14F951B84A3" --json`
- `./.maestro/seed-vault.sh C876CB9D-ED9F-45E0-9111-C14F951B84A3 --bundle-id com.eugenechan.Noto2 --source-vault "/Users/eugenechan/Library/Developer/CoreSimulator/Devices/89B84671-665D-4621-BF1A-513D6050C482/data/Containers/Data/Application/DA9B8DFB-0C9C-4990-ABC4-A341F6FD7E48/Documents/Noto" --initial-tab digest`
- `flowdeck ui simulator session start -S "C876CB9D-ED9F-45E0-9111-C14F951B84A3" --json`
- `flowdeck apps --json`
- `flowdeck ui simulator screen -S "C876CB9D-ED9F-45E0-9111-C14F951B84A3" --output /Users/eugenechan/dev/personal/Noto/.codex/evidence/20260904-192132-ios-visual-audit/04-ipad-screen-fallback.png --json`

## Notes
- The iPhone verification used a real capture created in-app on September 4, 2026 by filing the seeded capture draft into `inbox/2026-09-04-95d9fe80.md`, then opening Digest from the app tab bar.
- On iPhone, the add-to vault scan completed quickly on the seeded vault, so the loading row was not present by the time the first screenshot was taken. The direct-input requirement itself was still verified: typing began without tapping and immediately filtered the results.
- The iPad leg remained unverified because FlowDeck failed to provide a usable runtime capture after launch. No source files were modified during this audit.
