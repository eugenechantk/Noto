# iOS Visual Evidence Audit

Verdict: FAIL

Timestamp: 2026-09-25 15:41 HKT

Repository: `/Users/eugenechan/dev/personal/Noto`

Simulator: `cc-01a0d6ec-01a0d77c` (`727E1067-EE0F-4CBA-8395-FA00929AEDDF`), iPhone 17 Pro, iOS 26.3

App: Noto 2 (`com.eugenechan.Noto2`), scheme `Noto2`

## Change Audited

Noto 2 Browse explorer top chrome: Liquid Glass navigation/action controls, removal of the hard top-bar edge, and reuse of the editor's soft top-chrome fade while rows scroll beneath a fixed header.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC7: Root Settings + More and nested Back + More are distinct interactive Liquid Glass circles on iOS 26. | PASS | `01-root-explorer.png` shows separate circular Settings and More controls. `02-empty-nested-folder.png` shows separate circular Back and More controls. The corresponding tree files show stable 44x44 button frames and the requested identifiers; opening More produced its native action menu during the audit. |
| SC8: No hard separator or opaque rectangular edge below the top bar, including an empty nested folder. | FAIL | `02-empty-nested-folder.png` shows a clear horizontal rule spanning the content width immediately below “Nothing here yet.” (approximately y=157). The root state does not show an opaque bar edge, but the explicitly required empty-folder state still has a hard divider. |
| SC9: Rows scroll behind a soft editor-matching fade while header/title/buttons remain fixed and legible. | PASS | `05-scroll-transition.mov` records rows moving behind the fixed Browse header. `06-scroll-under-top-fade.png` shows the Projects row occupying y=81–152 beneath the fixed title/buttons at y=62–106, with a soft fade and no rectangular header background. `03-editor-top-chrome-reference.png` provides the editor transition reference. |

## Artifacts

- `01-root-explorer.png`
- `01-root-explorer-tree.json`
- `02-empty-nested-folder.png`
- `02-empty-nested-folder-tree.json`
- `03-editor-top-chrome-reference.png`
- `04-scroll-before.png`
- `05-scroll-transition.mov`
- `06-scroll-under-top-fade.png`
- `06-scroll-under-top-fade-tree.json`

## Commands

- `flowdeck config get --json`
- `flowdeck run -s Noto2 -S "727E1067-EE0F-4CBA-8395-FA00929AEDDF" --json`
- `.maestro/seed-vault.sh 727E1067-EE0F-4CBA-8395-FA00929AEDDF --bundle-id com.eugenechan.Noto2`
- `flowdeck run -s Noto2 -S "727E1067-EE0F-4CBA-8395-FA00929AEDDF" --no-build --json`
- `flowdeck ui simulator session start -S "727E1067-EE0F-4CBA-8395-FA00929AEDDF" --json`
- FlowDeck `tap`, `screen`, `record`, and `swipe` commands against the same simulator.

## Notes

- Five temporary blank notes were created through the app UI in the isolated simulator so the Browse list exceeded the viewport and the top transition could be observed under real scrolling.
- This audit covered iOS 26.3 on an isolated iPhone simulator. The earlier-iOS material fallback was not evaluated.
- No application source, tests, project files, package files, or build settings were modified.
