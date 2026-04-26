# Feature: ipad-scroll-delay

## User Story

As an iPad user editing notes in Noto, I want vertical scrolling to start immediately so the editor feels native and responsive.

## User Flow

1. Open a note on iPad in the regular-width split view.
2. Drag vertically in the editor to scroll.
3. Scrolling should begin immediately without a noticeable hesitation or gesture delay.
4. The same editor interaction should remain correct on iPhone.

## Success Criteria

- Vertical scrolling in the iPad editor begins immediately without the current delay.
- Horizontal history navigation, if still present, does not interfere with normal vertical scroll starts.
- iPhone editor scrolling behavior is not regressed.

## Test Strategy

- Inspect the live iOS editor path and regular-width iPad container.
- Validate on isolated iPad and iPhone simulators with seeded vault data.
- Add focused automated coverage only if the bug can be meaningfully exercised below the UI layer.

## Tests

- `flowdeck build -S "D2A2DD3C-FC7E-4D18-B42F-6615E3EFB006" --json`
- `flowdeck run -S "D2A2DD3C-FC7E-4D18-B42F-6615E3EFB006" --no-build --json`
- `flowdeck run -S "8A165E65-953E-436C-B8CC-8E566C086257" --json`
- `flowdeck run -S "8A165E65-953E-436C-B8CC-8E566C086257" --no-build --json`

## Implementation Details

- The live iOS editor was reparsing the full markdown document on every `scrollViewDidScroll` callback through `refreshTodoMarkerButtons()`.
- Added a renderable-block cache in `TextKit2EditorViewController` so scroll-time overlay refresh reuses semantic analysis until the text or collapsed-range state changes.
- This targets editor scroll latency without changing visible editor behavior.

## Residual Risks

- Physical-device scroll feel can still differ slightly from Simulator gesture timing.
- This fix addresses scroll-time parsing overhead. If the remaining delay is caused by gesture arbitration rather than per-scroll work, that would need a second pass.

## Bugs

- Reported: iPad editor scroll starts with a delay, while iPhone does not.
