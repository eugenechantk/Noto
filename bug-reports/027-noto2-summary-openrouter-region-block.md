# Bug 027: Noto 2 summary fails when OpenRouter is region-blocked

## Status: FIXED — verified 2026-08-26

## Description

Noto 2's streamed search summary does not work from Hong Kong because the direct OpenRouter API route appears to be blocked. A previous custom-base-URL attempt has not resolved the end-to-end failure. The summary should use a reachable, explicitly configured API route and report actionable failures.

## Steps to Reproduce

1. Launch Noto 2 in Hong Kong without a VPN.
2. Open Search and enter a query with local results.
3. Wait for the streamed LLM summary.
4. Observe that the summary fails instead of streaming, despite the earlier proxy/base-URL work.

## Root Cause

The earlier July fix added a manually entered OpenRouter base URL, but it was only an escape hatch:

1. A saved override was trusted indefinitely. If that proxy was malformed, down, or no longer needed, the app never retried OpenRouter's default route.
2. The client always appended `/chat/completions`, so pasting a full proxy endpoint produced a duplicated path.
3. Streaming HTTP failures discarded the response body, and Noto 2 hid the associated error string, making route, key, model, and credit failures indistinguishable.
4. There was no offline fallback, so any network/provider failure removed the summary feature entirely.

The Hong Kong route itself is not categorically blocked at investigation time: on 2026-08-26, `GET /api/v1/models` returned HTTP 200 and live completions through both `google/gemini-3.1-flash-lite` and `openai/gpt-4o-mini` returned HTTP 200 from this Hong Kong machine. A fresh Noto 2 simulator build also streamed the expected summary. The durable bug is therefore failure handling and stale-route recovery, not a currently reproducible blanket geoblock.

## Success Criteria

### 1. The configured route accepts either an API root or a full chat-completions endpoint
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — `Packages/NotoChat/Tests/NotoChatTests/OpenRouterClientTests.swift` → `customBaseURLAcceptsRootOrFullEndpoint`

**Simulator verification:**
1. Launch Noto 2 with a valid configured endpoint.
2. Search for `project`.
3. **Expected:** The remote summary completes without a duplicated URL path.

### 2. A failed custom route automatically retries direct OpenRouter
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `NEW` — `Noto2Tests/SearchSummaryRoutingTests.swift` → `customRouteFallsBackToDirectOpenRouter`

**Simulator verification:**
1. Save an unreachable custom base URL.
2. Search for `project` while direct OpenRouter is reachable.
3. **Expected:** The prose summary completes through the direct route and is labeled `AI-generated`.

### 3. If remote AI is unavailable, search still shows source-grounded offline highlights
- [x] Verified in unit test
- [x] Verified in simulator

**Unit tests:** `NEW` — `Packages/NotoSearch/Tests/NotoSearchTests/ExtractiveSearchSummaryTests.swift` → all four tests

**Simulator verification:**
1. Save an invalid OpenRouter key so both the configured proxy and direct route fail.
2. Search for `project`.
3. **Expected:** Attributed bullet highlights appear, labeled `Offline highlights`, with a `Retry AI` action.

### 4. Streaming HTTP failures preserve their diagnostic response body
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `MODIFIED` — `Packages/NotoChat/Tests/NotoChatTests/OpenRouterClientTests.swift` → `streamSurfacesHTTPErrorBody`

**Simulator verification:** Covered indirectly by criteria 2–3; route failures must proceed to retry/fallback without leaving the summary spinner stuck.

## Investigation Log

### Attempt 1

**Hypothesis:** The custom endpoint support was added to settings but is either not applied by the Noto 2 summary client, is normalized incorrectly, or does not provide an actually reachable default route.

**Changes:** Investigation in progress.

**Result:** The direct API and fresh app build both succeeded from Hong Kong. The previous fix did not provide automatic recovery or a fallback tier, so work moved to resilient routing plus offline highlights.

### Attempt 2

**Hypothesis:** Retrying the direct endpoint after a failed override and guaranteeing a source-grounded offline summary will eliminate the region/network single point of failure.

**Changes:** Added full-endpoint normalization, streaming error-body capture, route fallback, and an extractive summary builder in `NotoSearch`.

**Result:** Passed.

## Final Summary

- OpenRouter remains the preferred prose-summary tier.
- A failed saved override now retries the default OpenRouter endpoint once.
- If remote inference still fails (route, authentication, provider, or account), Noto 2 renders attributed offline highlights copied from the matching notes.
- Custom endpoint input accepts both an API root and a complete `/chat/completions` URL.

## Verification

- `Packages/NotoChat`: 65 tests passed.
- `Packages/NotoSearch`: 4 new extractive-summary tests passed. The full 129-test suite was attempted twice; both runs hit the pre-existing `SearchIndexCoordinatorTests` debounce timing failure, while all 4 new tests passed.
- `Noto2Tests`: 25 tests passed in the isolated iPhone simulator.
- Final Noto 2 Debug simulator build passed.
- Simulator evidence:
  - `full-endpoint-summary.jpg`: a full `/chat/completions` override produces an AI summary.
  - `stale-proxy-direct-fallback.jpg`: an unreachable override retries direct OpenRouter and produces an AI summary.
  - `offline-fallback.jpg`: invalid remote authentication produces attributed offline highlights and a Retry AI action.
