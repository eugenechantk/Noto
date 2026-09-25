# iOS Visual Evidence Audit

Verdict: PASS

Timestamp: 2026-09-25 15:45 HKT

Repository: `/Users/eugenechan/dev/personal/Noto`

Simulator: `cc-01a0d6ec-01a0d77c` (`727E1067-EE0F-4CBA-8395-FA00929AEDDF`), iPhone 17 Pro, iOS 26.3

App: Noto 2 (`com.eugenechan.Noto2`), scheme `Noto2`

## Change Audited

Re-audit of the Noto 2 Browse explorer top chrome after hiding separators on empty/loading directory-state rows.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC7: Root Settings + More and nested Back + More are distinct interactive Liquid Glass circles on iOS 26. | PASS | `01-root-glass.png` shows distinct root Settings and More circles. `02-empty-folder-no-separator.png` shows distinct nested Back and More circles. Their tree files report stable 44x44 controls with the requested identifiers. `05-more-menu.png` and its tree prove the More control remains interactive and presents New Note/New Folder. |
| SC8: No hard separator or opaque rectangular edge below the top bar, including an empty nested folder. | PASS | `02-empty-folder-no-separator.png` shows the previously failing Archive empty state without any horizontal divider beneath “Nothing here yet.” The header blends into the content area without an opaque rectangular lower edge. |
| SC9: Rows scroll behind a soft editor-matching fade while header/title/buttons remain fixed and legible. | PASS | `03-scroll-transition.mov` records rows moving beneath the fixed Browse header. `04-scroll-under-fade.png` shows the Projects row occupying y=81–152 beneath the fixed title/buttons at y=62–106, with the soft fade preserving header legibility. |

## Artifacts

- `01-root-glass.png`
- `01-root-glass-tree.json`
- `02-empty-folder-no-separator.png`
- `02-empty-folder-no-separator-tree.json`
- `03-scroll-transition.mov`
- `04-scroll-under-fade.png`
- `04-scroll-under-fade-tree.json`
- `05-more-menu.png`
- `05-more-menu-tree.json`

## Commands

- `flowdeck config get --json`
- `flowdeck run -s Noto2 -S "727E1067-EE0F-4CBA-8395-FA00929AEDDF" --json`
- `flowdeck ui simulator session start -S "727E1067-EE0F-4CBA-8395-FA00929AEDDF" --json`
- FlowDeck `tap`, `screen`, `record`, and `swipe` commands against the same isolated simulator.

## Notes

- The fresh FlowDeck build installed and launched successfully before this audit.
- The simulator retained the temporary notes created during the prior audit, which provided enough rows to exercise the scroll transition.
- This audit covered iOS 26.3 on an isolated iPhone simulator. The earlier-iOS material fallback was not evaluated.
- No application source, tests, project files, package files, or build settings were modified.
