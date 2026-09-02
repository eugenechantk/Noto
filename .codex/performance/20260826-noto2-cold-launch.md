# iOS Performance Investigation: Noto 2 cold launch

## Symptom

Cold launching Noto 2 does not make the Quick Capture editor usable immediately.

## Classification

- Category: launch
- Device scope: isolated iPhone simulator
- Build scope: local Release

## Baseline

- Metric: cold-process launch request to visible, editable Quick Capture UI
- Current value: 987 ms median over five local-vault launches (594–1,131 ms)
- Target value: materially lower than baseline, with Quick Capture presented before unrelated Browse/Search/index work
- Measurement surface: FlowDeck launch/UI capture and app launch markers

## Reproduction

1. Build Noto 2 in Release.
2. Install and seed an isolated simulator vault.
3. Terminate the app before every measured launch.
4. Launch and record the first visible and first editable Quick Capture state.

## Hypotheses

- [x] `RootTabView` eagerly initializes `VaultController`, which starts root enumeration before Capture is built.
- [x] Root-level `.task` and `.onAppear` start duplicated root loading plus search/index/file-watcher/status work that Capture does not need.
- [ ] Quick Capture's editor construction or autofocus is the next likely optimization target after unrelated startup work is removed.

## Before / After

- Before samples: 987, 1,131, 594, 1,006, 642 ms — median 987 ms, mean 872 ms, range 594–1,131 ms.
- After samples: 1,166, 943, 605, 893, 529 ms — median 893 ms, mean 827 ms, range 529–1,166 ms.
- Change: median improved by 94 ms (9.5%); mean improved by 45 ms (5.1%).
- Measurement note: FlowDeck UI capture had roughly 0.4–0.5 s effective sampling granularity despite a requested 100 ms interval. Treat this as directional simulator evidence; use Organizer and MetricKit for device distributions after shipping.

## Workload Validation

- Seeded 3,000 notes after installing the optimized build.
- Capture appeared with the software keyboard and accepted text.
- Browse loaded the seeded root and nested folders on demand.
- Search reported 3,000 indexed notes and returned results for `Root Note 00042`.
- A large-vault launch number was intentionally excluded because reinstalling the app rotated the simulator container before that measurement.

## Regression Protection

- [x] Launch dependency/lifecycle behavior covered by tests
- [x] Repeatable cold-start benchmark documented
- [ ] Field metric to watch after ship: Organizer cold launch time and MetricKit launch histogram
