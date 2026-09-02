# Quick Capture design explorations

## Goal

Make the cold-launch Capture screen immediately writable and make filing a thought feel faster than opening a normal note editor.

## Non-negotiables

- Editor is focused on launch; no tap before typing.
- Draft persists until file or discard succeeds.
- Filing stays one deliberate action after typing.
- Empty state contains no setup, metadata, or organizational decisions.
- Long notes remain possible even though short notes are the primary case.

## Directions

### 1. Current swipe stack — baseline

Keep the existing card stack: swipe up or right to file, left to discard.

- Strength: satisfying repeated-capture loop; no visible controls.
- Weakness: filing is undiscoverable and the custom gesture competes with vertical text scrolling.
- Best if: Noto 2 is intentionally gesture-led and returning-user speed matters more than first-use clarity.

### 2. Canvas + check — recommended

Use a full-bleed editor inspired by Apple Journal, Raycast, and Beli. Keep a circular checkmark at top-right and an unobtrusive discard control at top-left. Retain swipe-up as an expert shortcut, not the only filing path.

- Strength: immediate writing surface, explicit completion, maximum usable editor height.
- Weakness: top-right is not ideal for one-handed reach.
- Why it wins: it combines Mobbin's strongest convergence — “a bar and a page” — with Noto's faster learned gesture. A new user never has to discover the gesture, while a repeat user loses no speed.

### 3. Focused sheet

Place the editor in a rounded sheet with paired close/check controls, following Slopes and Calm.

- Strength: the draft feels tangible and safely bounded; file/discard are unmistakable.
- Weakness: the sheet and keyboard compress the writing area and make Capture feel more modal than instant.
- Best if: emotional clarity and containment matter more than raw canvas size.

### 4. Thumb dock

Keep the canvas but place the file action in a slim dock immediately above the keyboard, borrowing Raycast's footer placement and the reachability of messaging composers.

- Strength: shortest one-handed movement from the last key to filing.
- Weakness: visually crowds the keyboard edge, risks accidental taps, and fights the existing formatting toolbar.
- Best if: telemetry shows most captures are one or two lines and are usually filed one-handed.

## Recommendation

Prototype **Canvas + check** first. Preserve swipe-up/right as a secondary shortcut and remove left-swipe discard; destructive behavior should stay explicit. This keeps the learned speed of the current design without making a custom gesture the only path.

If one-handed capture is the dominant real-world behavior, test **Thumb dock** second — but only after deciding whether its action replaces or coexists with the formatting toolbar.

## Evaluation plan

Run each prototype against the same flow:

1. Cold launch with keyboard focused.
2. Type a two-line note.
3. File it without changing grip.
4. Start the next note.
5. Repeat with a note long enough to scroll.

Compare time-to-first-character, time from last character to filed state, accidental gesture/tap rate, and whether long-note scrolling remains predictable.

## Sources used

- Mobbin references already stored under `.claude/design/noto2/refs/`: Apple Journal, Slopes, Starling, Beli, Calm, Raycast, and stoic.
- Apple HIG: Text views, Entering data, Gestures, and Buttons.
