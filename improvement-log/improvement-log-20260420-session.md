# Improvement Log — Session 20260420

## Tracker

- [ ] 2026-04-20 — Fell back to training knowledge after WebFetch failed on JS-rendered HIG page, instead of trying /browse
- [ ] 2026-04-20 — Gave incorrect SwiftUI API recommendation (`.prominentDetail`) that would have shipped a non-HIG-compliant sidebar

## Log

### 2026-04-20 — Fell back to training knowledge after WebFetch failed on HIG page

**What happened:** WebFetch returned only the page title for the Apple HIG sidebars doc because the page is JavaScript-rendered. I noted the failure, then answered Eugene's question from my training knowledge about HIG sidebars (Big Sur patterns, `NavigationSplitViewStyle.prominentDetail`, `.ultraThinMaterial`). Eugene had to interrupt and tell me to use `/browse` or claude-in-chrome. When I actually ran the page through browse, the HIG was meaningfully different from what I remembered — June 2025 update introduced `backgroundExtensionEffect()` and named the pattern "Liquid Glass layer."

**Why this was wrong:** When a primary source fails to fetch, the correct response is to try another fetching tool (browse, claude-in-chrome, deep-dive skill), not to substitute training knowledge without flagging the risk. HIG docs are living and my training knowledge was stale by ~6 months. I shipped an architectural recommendation (`.prominentDetail` + custom `sidebarBackground` token) that would have produced a non-HIG-compliant implementation and introduced an unnecessary color token we'd have had to remove.

**What better looks like:**
1. When WebFetch returns "title only" or a stub for a JS-rendered page, immediately try `/browse` (or claude-in-chrome). Don't ask the user what to do.
2. If no fetch tool works, explicitly flag: "I couldn't pull the live doc; here's what my training knowledge says, which may be ~N months stale." Never present training knowledge as authoritative on a living spec.
3. For Apple HIG / Apple APIs especially: my knowledge cutoff is early 2026 but Apple ships HIG updates between WWDCs. Default to fetching, not recalling.

### 2026-04-20 — Recommended wrong SwiftUI API for floating-sidebar pattern

**What happened:** Recommended `NavigationSplitView.navigationSplitViewStyle(.prominentDetail)` as the way to achieve "content flows beneath sidebar." Apple's actual API for this, as of WWDC 2025 / iOS 26, is `.backgroundExtensionEffect()` — a dedicated SwiftUI modifier called out by name in the HIG. `.prominentDetail` does something different (emphasizes the detail column on iPad) and wouldn't produce the mirrored-edge effect the HIG describes.

**Why this was wrong:** I inferred the API from my memory of pre-iOS-26 patterns. Noto targets iOS/macOS 26 and has a dedicated `/ios-design-liquid-glass` skill — I should have loaded that skill first when Eugene said "sidebar with content underneath," because that's exactly the Liquid Glass pattern.

**What better looks like:** When the task involves a visual/material effect on an Apple platform, load `/ios-design-liquid-glass` before making any API recommendations. Modern Liquid Glass APIs (`.glassEffect()`, `.backgroundExtensionEffect()`, etc.) are skill-documented for exactly this reason.

