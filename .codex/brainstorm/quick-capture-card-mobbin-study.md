# Quick Capture card study — Mobbin

## Direction

Keep the current physical card and flick-to-file interaction. Iterate on how the stack communicates depth and how the card responds during the gesture.

## References

### Wysa — persistent next-card peek

https://mobbin.com/screens/344a5dd8-8103-45e5-b6d6-cb34ae7f0155

- The next card is visible before interaction, so “this is a stack” is immediate.
- Back cards are slightly offset and rotated rather than merely scaled.
- The front card stays visually clean; depth comes from overlap, not shadow.

### Tinder — asymmetric stack and gesture stamp

https://mobbin.com/screens/32cecf0c-2823-4a0a-bf92-92a88e977037

- Front and next cards use different rotations, making the stack feel physical.
- Gesture feedback is a localized stamp rather than a full-card color wash.
- The next card is already present and becomes more visible as the front card moves.

### Deepstash — loose paper pile

https://mobbin.com/screens/26562596-2a4a-4bae-a679-bcc6ec691a3e

- Thin outlines and slightly misaligned sheets create a paper metaphor.
- A stamped outcome label communicates intent without hiding content.
- Backing sheets are restrained: small offsets, small rotations, no heavy shadow.

### Abode — colored layer revealed behind a neutral card

https://mobbin.com/screens/aaa11e19-f074-4596-92ee-553911f20b69

- The large neutral writing card sits over a strong background layer.
- Movement can reveal state in the layer behind the card instead of tinting the editor itself.
- The card remains readable throughout the interaction.

### mymind — paper field inside quiet chrome

https://mobbin.com/screens/8c920d3f-da68-4a93-ae5b-749cd81e76d4

- A low-contrast outer surface frames a brighter writing field.
- Very thin separation is enough; the design avoids a large shadow.
- The editor has clear internal padding and a small contextual eyebrow.

### The Outsiders — focused dark note panel

https://mobbin.com/screens/4ccebf51-f506-4c4b-be4e-14557e8e80c7

- Tonal dark surfaces separate the note from the app without high contrast.
- Content remains the focal point; color is reserved for commitment.
- The visual weight sits low near the keyboard, leaving the note calm.

## Iteration concepts

### A. Peek + stamp — recommended

Combine Wysa's persistent next-card peek with Tinder/Deepstash gesture stamps.

- At rest, reveal 14–18 pt of the next card below the current card.
- Back card: `0.965` scale, `2°` rotation, 16–20 pt downward offset.
- Front card remains fully readable while dragging.
- File feedback: orange outlined `FILE` or checkmark stamp near the upper-left/upper-right corner, opacity tied to gesture progress.
- Discard feedback: muted `DISCARD` stamp; no destructive full-card flood.
- As the front card leaves, the back card straightens, scales to `1`, and rises into place.

Why first: it strengthens discoverability and physicality without changing the interaction model or adding permanent controls.

### B. Loose paper pile

Use two backing sheets with small opposing rotations, inspired by Deepstash.

- Back sheet 1: `-1.5°`, 10 pt down.
- Back sheet 2: `1.5°`, 18 pt down.
- Thin tonal outlines; little or no shadow.
- Main card can use a slightly warmer surface than the app background.

Tradeoff: more character, but potentially too playful for Noto's current restrained visual language.

### C. Color reveal

Keep one neutral front card and use the layer behind it to communicate the outcome, inspired by Abode.

- Orange underlay appears as the card moves up or right.
- Graphite underlay appears as the card moves left.
- Small centered glyph/label lives on the underlay, not over the text.
- Front card never changes fill or opacity during the drag.

Tradeoff: strongest legibility and gesture feedback, but the saturated reveal can feel louder than the rest of Noto.

### D. Framed paper

Borrow mymind's quieter inner-paper treatment.

- Outer card uses Noto's existing dark surface.
- Editor becomes a subtly lighter inset writing field with 12–16 pt radius.
- Thin top eyebrow: `QUICK CAPTURE` or `INBOX`.
- Stack motion remains unchanged.

Tradeoff: creates useful hierarchy, but adds a card-inside-card layer and reduces usable text width.

## Recommendation

Prototype **Peek + stamp** first. It is the smallest meaningful iteration:

1. Make the next card visible at rest.
2. Replace the full-card commit overlays with localized stamps.
3. Keep the existing pinned-to-finger motion, velocity thresholds, filing behavior, and keyboard-first launch.
4. Preserve the current orange accent only for the file direction.

If the resulting stack still feels too flat, add the **Color reveal** underlay next. Avoid changing the card surface, gesture physics, and state feedback simultaneously; those should be evaluated independently.
