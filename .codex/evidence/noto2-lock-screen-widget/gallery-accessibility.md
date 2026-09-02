# Lock Screen Widget Gallery Accessibility Evidence

Date: 2026-08-29
Simulator: `45483E1A-BF82-4FF9-A054-8F1EA0DBCDCC` (iPhone 17, iOS 26)

## Navigation

1. Locked the simulator.
2. Long-pressed the Lock Screen.
3. Activated `posterboard-customize-button` (“Customize”).
4. Activated `grouped-widgets-reticle-view` (“Add Widget”).
5. Scrolled the app list to “Noto 2”.
6. Opened Noto 2's widget gallery entry.

## Observed gallery elements

- Heading: `Noto 2`
- Description: `Quick Capture, Open Noto directly to capture a thought.`
- Circular button:
  - Label: `Noto 2, Quick Capture`
  - Frame: `69×69` points
- Rectangular button:
  - Label: `Noto 2, Quick Capture`
  - Frame: `155×69` points
- Instruction: `Tap or drag to add widget.`

After activating the circular button, the Lock Screen widget reticle contained a new group labeled `Noto 2` with a `76×90` point frame.

## Capture limitation

FlowDeck's live accessibility tree exposed the system customization sheet and widget entries, but both its continuous and one-off screenshot compositors omitted Apple's PosterBoard customization overlay. The saved `widget-gallery.png` therefore shows the underlying Lock Screen only. The gallery evidence above records the live system accessibility observations; the independent auditor provides a separate verification pass.

## Activation evidence

- `open-capture.mov` records `noto2://capture` transitioning Noto 2 from Browse to Capture.
- `capture-opened.png` shows the Capture editor focused with the software keyboard visible.
