# Bug 029: Quick Capture publishes as a control instead of a Lock Screen widget

## Status: FIXED — verified 2026-08-30

## Description

The shipped Quick Capture extension publishes a WidgetKit control for the bottom Lock Screen control slot, Control Center, and the Action button. The intended surface is an accessory widget in the Lock Screen widget area beneath the clock.

## Steps to Reproduce

1. Install Noto 2 build `0.1.0 (202608291645)`.
2. Customize an iPhone Lock Screen.
3. Select the widget area beneath the clock and look for a Noto 2 Quick Capture accessory widget.
4. Observe that the implementation declares `ControlWidget` / `StaticControlConfiguration`, which targets the separate Controls surface rather than the accessory widget gallery.

## Root Cause

WidgetKit exposes two distinct system surfaces through the same extension point. The extension implemented `ControlWidget` with `StaticControlConfiguration`, which registers a system control for the bottom Lock Screen shortcut, Control Center, and Action button. The widget area beneath the clock requires a `Widget` configuration that explicitly supports accessory widget families.

## Success Criteria

### 1. Quick Capture is published as a Lock Screen accessory widget
- [x] Verified in unit test/build
- [x] Verified in simulator

**Unit test/build:** `NEW BUILD CONTRACT` — the Noto 2 scheme compiles and embeds a WidgetKit extension whose source uses `StaticConfiguration` with `.accessoryCircular` and `.accessoryRectangular` families.

**Simulator verification:**
1. Build and install Noto 2 on the isolated iPhone simulator.
2. Open the Lock Screen customization widget gallery or render both WidgetKit previews.
3. **Expected:** “Quick Capture” is available in circular and rectangular widget presentations, rather than only as a bottom Lock Screen control.

### 2. Activating the widget opens Noto 2 on Capture
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `MODIFIED` — `Noto2Tests/Noto2QuickCaptureRoutingTests.swift` → `canonicalQuickCaptureURLSelectsCapture` validates the exact shared widget URL and Capture route.

**Simulator verification:**
1. Add or preview the Quick Capture widget.
2. Tap the widget.
3. Unlock if prompted.
4. **Expected:** Noto 2 opens with the Capture tab selected.

### 3. Existing launches and malformed URLs retain their behavior
- [x] Verified in unit test
- [x] Verified in simulator

**Unit tests:** `EXISTING` — `Noto2Tests/Noto2QuickCaptureRoutingTests.swift` and `Noto2Tests/Noto2StartupTests.swift`.

**Simulator verification:**
1. Launch Noto 2 normally and confirm its normal startup path.
2. Activate the canonical quick-capture URL and confirm Capture selection.
3. **Expected:** only the canonical widget URL changes the selected tab.

## Investigation Log

### Attempt 1

**Hypothesis:** The extension uses the wrong WidgetKit protocol and configuration type for the requested system surface.

**Changes:** None yet.

**Result:** Source inspection confirms `Noto2QuickCaptureControl` conforms to `ControlWidget` and returns `StaticControlConfiguration`.

**Decision:** Replace the control configuration with one accessory widget that supports circular and rectangular Lock Screen families. Retain the existing extension target and bundle identifier to avoid unnecessary signing and embedding churn.

### Attempt 2

**Hypothesis:** A static accessory widget using the existing strict capture URL will appear in the under-clock gallery and preserve the current launch router.

**Changes:** Replaced `ControlWidget` / `StaticControlConfiguration` with `Widget` / `StaticConfiguration`, added circular and rectangular accessory layouts, attached the canonical route with `.widgetURL`, and removed the obsolete control-only `OpenIntent` types.

**Result:** The focused routing suite passed 3/3 and the full Noto 2 suite passed 31/31. FlowDeck built, embedded, installed, and launched the extension. The real Lock Screen gallery listed Noto 2 and exposed two “Quick Capture” widget buttons sized for circular and rectangular slots. Activating the same widget URL opened Capture with the editor focused.

**Evidence:** `.codex/evidence/noto2-lock-screen-widget/open-capture.mov` and `.codex/evidence/noto2-lock-screen-widget/capture-opened.png`. Apple's customization overlay is omitted by the simulator screenshot compositor, but the live accessibility tree exposed the gallery title, description, and both widget buttons.

**Next:** Independent visual evidence audit.

### Independent Audit

**Result:** PASS.

**Evidence:** `.codex/evidence/20260830-000225-ios-visual-audit/evidence.md`. The audit independently placed both circular and rectangular widgets on the Lock Screen, stopped the app, cold-launched Capture by tapping the rectangular widget, and confirmed Browse still worked afterward.

## Final Summary

The extension used the WidgetKit control API for the wrong Lock Screen surface. It now publishes native circular and rectangular accessory widgets beneath the clock, and either widget opens Noto 2 directly to the focused Capture editor. Focused tests, the full Noto 2 suite, live system gallery verification, and an independent visual audit all passed.
