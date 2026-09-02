# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-08-30 00:08:35 HKT
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: iPhone 17 simulator `1922B139-ADDC-4A5E-9C85-FB43D75A2C2D`
App: `com.eugenechan.Noto2`

## Change Audited

Noto 2's Quick Capture WidgetKit extension was changed from a control-only surface to a Lock Screen accessory widget that should appear in the under-clock widget gallery, offer circular and rectangular presentations, and open the Capture editor through `noto2://capture`.

## Success Criteria

| Criterion | Result | Evidence |
| --- | --- | --- |
| Noto 2 appears in the Lock Screen widget gallery under the clock, not only the bottom quick-action controls surface. | PASS | [05-gallery-observation.json](./05-gallery-observation.json) records the live `Add Widgets -> Noto 2` gallery observation, including the `Noto 2` heading and `Quick Capture` description. [02-lock-screen-surface.jpg](./02-lock-screen-surface.jpg) shows the widget placed in the under-clock area while the flashlight quick action remains separate at the bottom. |
| Both circular and rectangular Quick Capture presentations are available and legible. | PASS | [05-gallery-observation.json](./05-gallery-observation.json) records two gallery buttons labeled `Noto 2, Quick Capture` with `69x69` and `155x69` point frames. [02-lock-screen-surface.jpg](./02-lock-screen-surface.jpg) shows the circular compose button and the rectangular `Quick Capt... / New note` presentation on the Lock Screen. |
| Activating the widget opens Noto 2 to Capture with the editor ready. | PASS | [06-activation-observation.json](./06-activation-observation.json) records a cold-launch widget tap from the Lock Screen after stopping the app. [03-capture-opened.jpg](./03-capture-opened.jpg) shows Noto 2 on Capture with the editor focused and the software keyboard visible. |
| Normal app UI remains intact. | PASS | [04-browse-intact.jpg](./04-browse-intact.jpg) shows Browse still functioning after widget activation, including folders and notes plus the unchanged Capture/Search/Browse tab bar. [04-browse-intact-tree.json](./04-browse-intact-tree.json) contains the corresponding accessibility snapshot. |

## Artifacts

- `01-lock-screen-widgets.jpg` — early lock-screen screenshot captured during widget setup.
- `02-lock-screen-surface.jpg` — lock screen with the placed rectangular and circular Quick Capture widgets visible beneath the clock.
- `03-capture-opened.jpg` — Noto 2 after widget activation, with Capture focused and keyboard visible.
- `04-browse-intact.jpg` — Browse tab after activation, proving the normal app UI still works.
- `04-browse-intact-tree.json` — accessibility tree for the Browse screenshot.
- `05-gallery-observation.json` — live gallery/tree observations for `Add Widgets -> Noto 2`.
- `06-activation-observation.json` — recorded activation path and post-launch observations.

## Commands

- `flowdeck config get --json`
- `flowdeck run -s Noto2 -S "1922B139-ADDC-4A5E-9C85-FB43D75A2C2D" --json`
- `.maestro/seed-vault.sh 1922B139-ADDC-4A5E-9C85-FB43D75A2C2D --bundle-id com.eugenechan.Noto2`
- `flowdeck run -s Noto2 -S "1922B139-ADDC-4A5E-9C85-FB43D75A2C2D" --no-build --json`
- `flowdeck ui simulator session start -S "1922B139-ADDC-4A5E-9C85-FB43D75A2C2D" --json`
- `flowdeck ui simulator button lock -S "1922B139-ADDC-4A5E-9C85-FB43D75A2C2D" --json`
- `flowdeck ui simulator tap "Customize" -S "1922B139-ADDC-4A5E-9C85-FB43D75A2C2D" --json`
- `flowdeck ui simulator tap "Add Widget" -S "1922B139-ADDC-4A5E-9C85-FB43D75A2C2D" --json`
- `flowdeck ui simulator scroll --until "Noto 2" --timeout 10000 -S "1922B139-ADDC-4A5E-9C85-FB43D75A2C2D" --json`
- `flowdeck ui simulator tap "Noto 2" -S "1922B139-ADDC-4A5E-9C85-FB43D75A2C2D" --json`
- `flowdeck ui simulator tap "Noto 2, Quick Capture" -S "1922B139-ADDC-4A5E-9C85-FB43D75A2C2D" --json`
- `flowdeck ui simulator tap --point 338,32 --geometry points -S "1922B139-ADDC-4A5E-9C85-FB43D75A2C2D" --json`
- `flowdeck stop 0BD3EF26-EBA9-4D11-A222-3FB794110FB8 --json`
- `flowdeck ui simulator tap --point 114,710 --geometry points -S "1922B139-ADDC-4A5E-9C85-FB43D75A2C2D" --json`

## Notes

- FlowDeck's live screenshot compositor was inconsistent while Apple's PosterBoard widget gallery sheet was open: some captures omitted the sheet even though the accessibility tree exposed it. I therefore used the live tree for gallery presence/family proof and the later visible lock-screen screenshot for actual on-screen appearance.
- There is an explicit date boundary in the evidence: FlowDeck command timestamps are in UTC on `2026-08-29`, while the simulator lock screen itself displayed `Sunday, August 30` in local time. Both refer to the same audit session.
