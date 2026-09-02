# iOS Visual Evidence Audit
Verdict: PASS
Timestamp: 2026-08-07 15:20 HKT
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: cc-019fdab8-019fdb10 (3FC24E14-542B-49EE-B5BE-EDCEC6F7E650)
App: com.eugenechan.Noto

## Change Audited
Deep-link runtime handling for `noto://open?path=<vault-relative .md path>` after the app switched to the shared `NotoVault.NotoDeepLink` codec, including warm routing, cold-launch routing, unsafe-link rejection, and post-link navigation usability.

## Success Criteria
| Criterion | Result | Evidence |
|---|---|---|
| Opening a valid nested `noto://` URL while Noto is already running routes to the exact note editor. | PASS | [05-captures-before-links.png](./05-captures-before-links.png) shows the running app on the Captures list before handoff. `flowdeck ui simulator open-url "noto://open?path=Captures%2FNothing%20is%20real%20anymore.md"` then produced [08-warm-valid-link-editor.png](./08-warm-valid-link-editor.png), showing the exact `Nothing is real anymore` editor. |
| Opening a valid `noto://` URL while Noto is terminated cold-launches Noto into the exact note editor. | PASS | `flowdeck stop 10DB7A03-EF77-49AD-BB64-F270A38AC42B --json` terminated the running app. [09-home-after-termination.png](./09-home-after-termination.png) shows the simulator on the Home screen. `flowdeck ui simulator open-url "noto://open?path=Captures%2FAI%20Chatbots%20Last%20Week%20Tonight%20with%20John%20Oliver%20%28HBO%29.md"` then produced [10-cold-launch-valid-link-editor.png](./10-cold-launch-valid-link-editor.png), showing the exact `AI Chatbots: Last Week Tonight with John Oliver (HBO)` editor. |
| Invalid or unsafe links do not open an escaped note. | PASS | [06-invalid-link-result.png](./06-invalid-link-result.png) captures the iOS handoff confirmation for `noto://open?path=..%2FSecrets.md`. After accepting it, [07-invalid-link-after-open.png](./07-invalid-link-after-open.png) shows Noto still on the Captures list, with no note editor opened. |
| Normal Noto navigation remains usable. | PASS | [03-captures-list.png](./03-captures-list.png) and [04-manual-note-editor.png](./04-manual-note-editor.png) show normal in-app navigation from the Captures list into a nested note editor. After the cold-launch deep link, [11-post-deeplink-back-navigation.png](./11-post-deeplink-back-navigation.png) shows Back navigation still returning to a usable vault screen. |

## Artifacts
- `01-launch.png`
- `01-launch-tree.json`
- `02-vault-home.png`
- `02-vault-home-tree.json`
- `03-captures-list.png`
- `03-captures-list-tree.json`
- `04-manual-note-editor.png`
- `04-manual-note-editor-tree.json`
- `05-captures-before-links.png`
- `05-captures-before-links-tree.json`
- `06-invalid-link-result.png`
- `06-invalid-link-result-tree.json`
- `07-invalid-link-after-open.png`
- `07-invalid-link-after-open-tree.json`
- `08-warm-valid-link-editor.png`
- `08-warm-valid-link-editor-tree.json`
- `09-home-after-termination.png`
- `10-cold-launch-valid-link-editor.png`
- `10-cold-launch-valid-link-editor-tree.json`
- `11-post-deeplink-back-navigation.png`
- `11-post-deeplink-back-navigation-tree.json`

## Commands
- `flowdeck config get --json`
- `flowdeck run -S "3FC24E14-542B-49EE-B5BE-EDCEC6F7E650" --json`
- `flowdeck ui simulator session start -S "3FC24E14-542B-49EE-B5BE-EDCEC6F7E650" --json`
- `flowdeck ui simulator tap "Create New Vault, Pick a location — a Noto folder will be created" -S "3FC24E14-542B-49EE-B5BE-EDCEC6F7E650" --json`
- `flowdeck ui simulator tap "More" -S "3FC24E14-542B-49EE-B5BE-EDCEC6F7E650" --json`
- `flowdeck ui simulator tap "New Folder" -S "3FC24E14-542B-49EE-B5BE-EDCEC6F7E650" --json`
- `flowdeck ui simulator open-url "noto://open?path=..%2FSecrets.md" -S "3FC24E14-542B-49EE-B5BE-EDCEC6F7E650" --json`
- `flowdeck ui simulator open-url "noto://open?path=Captures%2FNothing%20is%20real%20anymore.md" -S "3FC24E14-542B-49EE-B5BE-EDCEC6F7E650" --json`
- `flowdeck stop 10DB7A03-EF77-49AD-BB64-F270A38AC42B --json`
- `flowdeck ui simulator open-url "noto://open?path=Captures%2FAI%20Chatbots%20Last%20Week%20Tonight%20with%20John%20Oliver%20%28HBO%29.md" -S "3FC24E14-542B-49EE-B5BE-EDCEC6F7E650" --json`
- `flowdeck ui simulator session stop -S "3FC24E14-542B-49EE-B5BE-EDCEC6F7E650" --json`

## Notes
- The simulator started from Noto’s first-run welcome flow. The audit stayed independent by creating/opening the vault through the live UI rather than relying on prior saved state.
- After entering the `Captures` folder, note counts fluctuated rapidly and many capture notes appeared. To avoid relying on fuzzy list labels, the exact filenames used for the deep links were confirmed read-only from the simulator’s File Provider storage before opening the URLs.
- After the cold-launch deep link, tapping Back returned to the vault root rather than the Captures list. This did not block navigation and the app remained usable, but it is worth noting as a stack-restoration nuance outside the stated acceptance criteria.
