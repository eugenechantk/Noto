# Feature: Noto 2 Quick Capture Lock Screen Widget

## User Story

As a Noto 2 user, I want a Quick Capture widget in the Lock Screen widget area beneath the clock so I can open the capture editor with one tap.

## User Flow

1. Customize the iPhone Lock Screen and select the widget area beneath the clock.
2. Find Noto 2's “Quick Capture” widget in the widget gallery.
3. Add either its circular or rectangular presentation.
4. Tap the widget from the Lock Screen.
5. Unlock when iOS requires authentication.
6. Noto 2 opens directly to the Capture tab.

## Success Criteria

- SC1: Noto 2 publishes a WidgetKit accessory widget named “Quick Capture,” not only a Lock Screen control.
- SC2: The widget supports both `.accessoryCircular` and `.accessoryRectangular` Lock Screen families.
- SC3: The circular presentation uses a clear system compose symbol and remains legible in system vibrant rendering.
- SC4: The rectangular presentation includes concise “Quick Capture” labeling and a compose symbol.
- SC5: Tapping either presentation opens `noto2://capture`, and Noto 2 routes to its Capture tab.
- SC6: Ordinary app launches and existing Noto 2 navigation remain unchanged.
- SC7: The Noto 2 app embeds an installable WidgetKit extension in simulator and signed device builds.

## Test Strategy

- Existing app-target Swift Testing validates the strict shared quick-capture URL and launch router used by the widget.
- The complete Noto 2 test bundle guards startup and navigation regressions.
- FlowDeck build/install verification proves the accessory widget compiles and is embedded.
- Simulator and independent visual evidence verify the widget gallery presentation where the system customization UI is automatable; otherwise, built WidgetKit metadata and widget preview evidence provide the system-surface proof.

## Tests

### App unit

- `Noto2Tests/Noto2QuickCaptureRoutingTests.swift`
  - canonical quick-capture URL routes to Capture — SC5.
  - malformed routes remain rejected — SC5, SC6.
  - repeated quick-capture requests publish correctly — SC5, SC6.

### Existing regression

- `Noto2Tests/Noto2StartupTests.swift` — SC6.

### Build and runtime integration

- FlowDeck Noto 2 tests/build/install — SC1, SC2, SC7.
- Lock Screen gallery or WidgetKit preview evidence — SC1, SC2, SC3, SC4.
- Widget activation/deep-link evidence — SC5.

## Implementation Details

- Replace the extension's `ControlWidget` configuration with a static `Widget` timeline configuration.
- Keep the existing extension target and bundle identifier so signing and embedding remain stable.
- Use the shared strict `Noto2LaunchRoute.quickCaptureURL` as the widget URL.
- Use native accessory widget families and system rendering rather than custom backgrounds or color assumptions.
- The prior control-only feature artifact remains historical evidence for the superseded implementation.
- The circular family uses `AccessoryWidgetBackground` and `square.and.pencil`; the rectangular family pairs the same symbol with “Quick Capture” and “New note.”
- The obsolete control-specific `OpenIntent` and App Intents types were removed because accessory widgets launch through `.widgetURL`.

## Residual Risks

- The simulator screenshot compositor omits Apple's Lock Screen customization overlay even though its accessibility tree exposes the gallery. Gallery availability and both widget sizes were therefore verified through the live system accessibility tree; the activation destination has separate screenshot/video evidence.

## Verification

- Focused `Noto2QuickCaptureRoutingTests`: 3/3 passed.
- Full Noto 2 Swift Testing bundle: 31/31 passed.
- FlowDeck build, extension embedding, install, and launch: passed on isolated iPhone simulator `45483E1A-BF82-4FF9-A054-8F1EA0DBCDCC`.
- Live Lock Screen widget gallery: Noto 2 listed “Quick Capture” with circular `69×69` and rectangular `155×69` buttons.
- Widget URL activation opened Capture with the editor focused and keyboard visible.
- Activation evidence: `.codex/evidence/noto2-lock-screen-widget/open-capture.mov` and `capture-opened.png`.
- Independent visual audit: PASS. It placed both widgets on the actual Lock Screen, cold-launched Capture by tapping the rectangular widget, and confirmed Browse remained intact. Report: `.codex/evidence/20260830-000225-ios-visual-audit/evidence.md`.

## Bugs

- Tracked as `bug-reports/029-noto2-lock-screen-widget-surface.md`.
