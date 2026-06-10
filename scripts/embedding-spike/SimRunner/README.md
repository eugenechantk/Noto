# SimRunner — on-simulator validation harness for GraniteEmbed

Validates the converted Core ML model on an actual iOS simulator runtime: loads the
build-compiled `.mlmodelc`, embeds 10 pre-tokenized EN/ZH/JA fixtures, asserts cosine
parity ≥ 0.999 vs the PyTorch fp32 reference and ≥ 0.9995 vs the Mac CoreML run, and
writes metrics to `/tmp/noto-embed-spike/sim_result.txt`.

## Setup (model not committed — 94 MB)

```bash
cp -R ../../../.claude/spikes/artifacts/GraniteEmbed_int8.mlpackage \
      Tests/SimRunnerTests/Resources/
```

The fixtures (`sim_fixtures.json`) are committed; regenerate them with the
tokenize-and-export step documented in the spike report if the model changes.

## Run

```bash
flowdeck simulator create --name "Noto-EmbedSpike" --device-type "iPhone 16 Pro" --runtime "iOS 26.2" --json
flowdeck test -w ../SimRunner-workspace.xcworkspace -s SimRunnerTests -S "Noto-EmbedSpike"
cat /tmp/noto-embed-spike/sim_result.txt
```

Note: the wrapper `.xcworkspace` exists because FlowDeck/xcodebuild needs a workspace;
it just references this package (scheme: `SimRunnerTests`).

## Result 2026-06-10 (iPhone 16 Pro sim, iOS 26.2)

`min_cos_torch=0.999741 min_cos_mac=0.999989 load_s=0.08 median_ms=336.4`

Latency on simulator is NOT representative (no ANE, unoptimized CPU path) — correctness
is the signal here. Real-device ANE latency expectation: ~15–40 ms (M3 Max ANE: 13.4 ms).
