# Feature: Noto 2 Quick Capture Lock Screen Control (Superseded)

> Superseded by `.codex/feature/noto2-lock-screen-widget.md` after clarifying that the intended placement is the Lock Screen widget area beneath the clock, not the bottom control slot.

## User Story

As a Noto 2 user, I want to replace the system flashlight control on my Lock Screen with a Noto Quick Capture control so I can start writing with one tap.

## User Flow

1. Add Noto 2's “Quick Capture” control while customizing the Lock Screen.
2. Tap the circular control from the Lock Screen.
3. Unlock when iOS requires authentication.
4. Noto 2 opens directly to its Capture tab with the capture editor ready.
5. Normal app launches continue to open using the app's existing default behavior.

## Success Criteria

- SC1: Noto 2 publishes a button-style WidgetKit control named “Quick Capture” on the app's supported iOS versions (currently iOS 26+).
- SC2: The control uses a clear system compose/capture symbol suitable for the circular Lock Screen slot.
- SC3: Activating the control foregrounds Noto 2 and selects the Capture tab.
- SC4: The routing logic accepts only the intended Noto 2 quick-capture route and ignores unrelated URLs.
- SC5: Existing Noto 2 startup and tab behavior remains intact for ordinary launches.
- SC6: The Noto 2 app target embeds the control extension in simulator and device builds.

## Test Strategy

- App-target Swift Testing verifies strict route parsing and tab selection state without relying on rendered UI.
- Existing Noto 2 startup tests guard launch behavior.
- FlowDeck builds/tests verify app-extension integration.
- Simulator evidence verifies a deep-link activation reaches the Capture screen. System Lock Screen gallery availability remains device/system-managed and is checked from the built extension metadata where simulator automation cannot expose customization UI reliably.

## Tests

### App unit

- `Noto2Tests/Noto2QuickCaptureRoutingTests.swift`
  - accepts the canonical quick-capture URL — verifies SC3, SC4.
  - rejects unrelated schemes, hosts, paths, and query variants — verifies SC4.
  - publishes repeated valid requests to the Capture tab — verifies SC3, SC5.

### Existing regression

- `Noto2Tests/Noto2StartupTests.swift` — verifies SC5.

### Build and runtime integration

- FlowDeck Noto 2 tests/build — verifies SC1, SC6.
- FlowDeck deep-link launch recording — verifies SC3.

## Implementation Details

- Use `ControlWidgetButton` with an `OpenIntent`, which is Apple's native control surface for Control Center, Lock Screen controls, and the Action Button.
- `Noto2QuickCaptureControl` is a WidgetKit extension embedded by the Noto 2 app target.
- `Noto2QuickCaptureOpenIntent` is compiled into both the app and extension, as required for an `OpenIntent` that foregrounds the app.
- `Noto2LaunchRouter` publishes repeated launch requests and `RootTabView` remains the owner of tab selection.
- The strict `noto2://capture` route provides a testable external launch path and rejects URL variants outside this feature.
- The extension and app each contain generated App Intents metadata for `Noto2QuickCaptureOpenIntent`.

## Residual Risks

- Independent visual audit passed. Simulator automation could not reliably expose Apple's Lock Screen / Control Center customization gallery, so system publication was verified from the embedded `.appex`, WidgetKit extension metadata, App Intents metadata, and source configuration rather than a gallery screenshot.
- The new extension bundle identifier needs its App Store provisioning profile bootstrapped before the next signed device/TestFlight deployment; `fastlane/.env.noto2` now supplies it through `EXTENSION_TARGETS` for the existing `bootstrap_match` workflow.

## Verification

- Focused `Noto2QuickCaptureRoutingTests`: 3/3 passed.
- Full Noto 2 Swift Testing bundle: 29/29 passed.
- FlowDeck Noto 2 build, install, and launch: passed on an isolated iPhone simulator.
- Embedded extension install and generated App Intents metadata checks: passed.
- Independent visual audit: PASS — `.codex/evidence/20260829-145704-ios-visual-audit/evidence.md`.
- Interaction recording: `.codex/evidence/noto2-quick-capture-control/open-quick-capture.mov`.

## Bugs

- Fixed during implementation: explicit app and extension plist files initially participated in synchronized resources / generated metadata incorrectly; target membership and plist generation now produce installable bundles.
