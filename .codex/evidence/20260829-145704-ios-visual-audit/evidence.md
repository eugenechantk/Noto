# iOS Visual Evidence Audit
Verdict: PASS
Timestamp: 2026-08-29 15:02:10 HKT
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: cc-01a04c40-01a04c4d / 427542AE-481C-4374-9927-A43984472136
App: com.eugenechan.Noto2

## Change Audited
Noto 2 Quick Capture system control: a WidgetKit `ControlWidget` named `Quick Capture` using `square.and.pencil`, backed by `Noto2QuickCaptureOpenIntent`, with app routing through `noto2://capture` and `Noto2LaunchRouter` to foreground Noto 2 on the Capture tab.

## Success Criteria
| Criterion | Result | Evidence |
|---|---|---|
| Noto 2 publishes a button-style system control named `Quick Capture`. | PASS | `06-built-appex-info.json` shows an embedded WidgetKit extension (`com.apple.widgetkit-extension`) with display name `Noto Quick Capture`. `06-built-app-plugins.txt` shows `Noto2QuickCaptureControl.appex` embedded in `Noto2.app`. `07-quick-capture-source.txt` shows `ControlWidgetButton` and `.displayName("Quick Capture")`. |
| The control uses an appropriate compose/capture symbol for the circular slot. | PASS | `07-quick-capture-source.txt` shows `Label("Quick Capture", systemImage: "square.and.pencil")`, which is a standard compose symbol and fits the intended surface. |
| Activating Quick Capture foregrounds Noto 2 to Capture. | PASS | `02-before-quick-capture-search.png` shows Noto 2 away from Capture on Search. `03-home-before-deeplink.png` shows the app backgrounded on SpringBoard. After `flowdeck ui simulator open-url noto2://capture`, `04-after-deeplink-capture.png` and `05-direct-deeplink-capture.png` show Noto 2 foregrounded on Capture. |
| Runtime screen shows Capture editor anchors. | PASS | `01-ordinary-launch-capture-tree.json`, `04-after-deeplink-capture-tree.json`, and `05-direct-deeplink-capture-tree.json` contain `captureStatusLine`, `note_editor`, and `capturePlaceholder`. Matching screenshots are `01-ordinary-launch-capture.png`, `04-after-deeplink-capture.png`, and `05-direct-deeplink-capture.png`. |
| Normal startup behavior remains. | PASS | After seeding and relaunching with `--no-build`, `01-ordinary-launch-capture.png` shows the ordinary app launch landing cleanly on Capture. Caller-provided regression result: Noto2 Swift Testing bundle passed 29/29 before audit. |

## Artifacts
- `01-ordinary-launch-capture.png`
- `01-ordinary-launch-capture-tree.json`
- `02-before-quick-capture-search.png`
- `02-before-quick-capture-search-tree.json`
- `03-home-before-deeplink.png`
- `03-home-before-deeplink-tree.json`
- `04-after-deeplink-capture.png`
- `04-after-deeplink-capture-tree.json`
- `05-direct-deeplink-capture.png`
- `05-direct-deeplink-capture-tree.json`
- `06-built-app-plugins.txt`
- `06-built-appex-info.json`
- `07-quick-capture-source.txt`

## Commands
- `flowdeck config get --json`
- `FLOWDECK_HEADLESS=0 flowdeck run -w /Users/eugenechan/dev/personal/Noto/Noto.xcodeproj -s Noto2 -S "427542AE-481C-4374-9927-A43984472136" --json`
- `./.maestro/seed-vault.sh 427542AE-481C-4374-9927-A43984472136 --bundle-id com.eugenechan.Noto2`
- `FLOWDECK_HEADLESS=0 flowdeck run -w /Users/eugenechan/dev/personal/Noto/Noto.xcodeproj -s Noto2 -S "427542AE-481C-4374-9927-A43984472136" --no-build --json`
- `flowdeck ui simulator session start -S "427542AE-481C-4374-9927-A43984472136" --json`
- `flowdeck ui simulator tap "Continue" -S "427542AE-481C-4374-9927-A43984472136" --json`
- `flowdeck ui simulator tap "hide_keyboard_button" --by-id -S "427542AE-481C-4374-9927-A43984472136" --json`
- `flowdeck ui simulator tap --point 201,825 --geometry points -S "427542AE-481C-4374-9927-A43984472136" --json`
- `flowdeck ui simulator button home -S "427542AE-481C-4374-9927-A43984472136" --json`
- `flowdeck ui simulator open-url noto2://capture -S "427542AE-481C-4374-9927-A43984472136" --json`
- `flowdeck ui simulator screen -S "427542AE-481C-4374-9927-A43984472136" --output ... --optimize`
- `flowdeck ui simulator session stop -S "427542AE-481C-4374-9927-A43984472136"`

## Notes
- The handoff requested simulator `45483E1A-BF82-4FF9-A054-8F1EA0DBCDCC`, but the repo's FlowDeck isolation hook blocked shared-simulator UI commands and created this session's dedicated simulator `427542AE-481C-4374-9927-A43984472136`. Audit evidence was collected on the dedicated simulator to stay within repo rules.
- I made a best-effort attempt to reach system-level gallery/customization UI, but Lock Screen customization and Control Center gallery were not exposed reliably through this simulator session. Publication evidence therefore comes from the built embedded extension metadata plus runtime deep-link/foreground behavior rather than a gallery screenshot.
