# Maestro E2E Testing Research for Noto

## Synthesis

### Key Findings

#### 1. What Maestro Is and How It Works

Maestro is an open-source (Apache 2.0) mobile and web UI automation framework that uses **declarative YAML flows** instead of code to define E2E tests. It has 13,000+ GitHub stars and is actively maintained by Maestro.dev (formerly mobile-dev-inc).

**Architecture:**
- **Black-box testing** -- Maestro interacts with the iOS Accessibility layer, not your app's internals. It analyzes rendered frames and simulates genuine user interactions. When you execute `tapOn`, Maestro triggers the same iOS input pipeline that a physical touch would.
- **Interpreted execution** -- YAML flows are interpreted at runtime (no compilation step), enabling fast iteration. You edit a YAML file and re-run immediately.
- **Built-in flakiness tolerance** -- Maestro automatically waits for elements to appear and handles UI transitions/animations without manual `sleep()` calls. This is the core "deterministic" selling point vs. XCUITest.
- **Framework-agnostic** -- Works with Swift, Objective-C, SwiftUI, UIKit, Flutter, React Native. It only cares about the rendered accessibility tree.
- **Device-level control** -- Can interact with system permission dialogs, navigate across apps, and handle OS-level UI.

The internal architecture (from the GitHub repo) has separate modules: `maestro-cli` (CLI), `maestro-ios` (iOS driver + XCTest runner), `maestro-orchestra` (core execution engine), `maestro-studio` (visual IDE), and `maestro-ai` (AI-assisted testing).

**Sources:** [Maestro GitHub](https://github.com/mobile-dev-inc/Maestro), [Maestro Docs - iOS](https://docs.maestro.dev/get-started/supported-platform/ios), [BrowserStack Guide](https://www.browserstack.com/guide/maestro-testing)

#### 2. Installation and Setup

**Prerequisites:**
- Java 17 or higher (`java -version` to verify)
- Xcode + Command Line Tools (`xcode-select --install`)
- A booted iOS Simulator

**Installation (macOS):**
```bash
curl -fsSL "https://get.maestro.mobile.dev" | bash
```

Alternative via Homebrew (mentioned in some guides):
```bash
brew install maestro
brew tap facebook/fb
brew install facebook/fb/idb-companion
```

**No changes to your Xcode project are needed.** Maestro runs entirely on the test machine as a separate process. It does not require an SDK, framework, or pod in your app. The only app-side requirement is good accessibility identifiers.

**Setup workflow:**
1. Install Maestro CLI
2. Build and install your app on a simulator (via Xcode or `xcodebuild`)
3. Create `.maestro/` directory in your project root
4. Write YAML flow files
5. Run `maestro test .maestro/`

**Sources:** [Maestro GitHub README](https://github.com/mobile-dev-inc/Maestro), [Alexander Weiss Blog](https://alexanderweiss.dev/blog/2023-02-11-ios-ui-testing-with-maestro)

#### 3. Writing Test Flows -- YAML Syntax and Commands

A flow file starts with metadata (separated by `---`) followed by a list of commands:

```yaml
appId: com.noto.app
name: "Create a new note"
tags:
  - smoke
  - notes
---
- launchApp:
    clearState: true
- tapOn: "New Note"
- inputText: "# My First Note"
- assertVisible: "My First Note"
```

**Core Commands:**

| Command | Description | Syntax |
|---------|-------------|--------|
| `launchApp` | Launch app (with optional clearState, clearKeychain, stopApp) | `- launchApp` or `- launchApp: { clearState: true }` |
| `tapOn` | Tap an element by text, id, or point | `- tapOn: "Button Text"` or `- tapOn: { id: "myId" }` |
| `longPressOn` | Long press an element | `- longPressOn: "Menu Item"` |
| `doubleTapOn` | Double tap | `- doubleTapOn: "Element"` |
| `inputText` | Type text (regardless of focus state) | `- inputText: "Hello world"` |
| `eraseText` | Delete characters from focused field | `- eraseText` or `- eraseText: { charactersToErase: 5 }` |
| `assertVisible` | Assert element is visible | `- assertVisible: "Expected Text"` |
| `assertNotVisible` | Assert element is not visible | `- assertNotVisible: "Error"` |
| `scrollUntilVisible` | Scroll until element appears | `- scrollUntilVisible: { element: "Target", direction: DOWN }` |
| `swipe` | Swipe gesture | `- swipe: { start: "10%,50%", end: "90%,50%", duration: 500 }` |
| `pressKey` | Press a hardware/software key | `- pressKey: Enter` |
| `hideKeyboard` | Dismiss keyboard (iOS: scrolls up/down since no native API) | `- hideKeyboard` |
| `stopApp` | Stop the app | `- stopApp` |
| `runFlow` | Execute a subflow | `- runFlow: login.yaml` |
| `extendedWaitUntil` | Wait for visibility/invisibility | `- extendedWaitUntil: { visible: "Element", timeout: 10000 }` |
| `inputRandomEmail` | Generate random email | `- inputRandomEmail` |
| `inputRandomPersonName` | Generate random name | `- inputRandomPersonName` |
| `inputRandomNumber` | Generate random digits | `- inputRandomNumber: { length: 10 }` |

**Selectors:**

Elements can be targeted by:
- **Text**: `tapOn: "Button Label"` -- matches accessibilityLabel or visible text
- **ID**: `tapOn: { id: "accessibilityIdentifier" }` -- matches accessibilityIdentifier
- **Point**: `tapOn: { point: "50%,50%" }` -- coordinate-based (percentage or absolute)
- **Index**: `tapOn: { text: "Item", index: 1 }` -- disambiguate duplicates
- **Relative position**: `below`, `above`, `leftOf`, `rightOf` -- relative to another element

**Conditional Logic:**
```yaml
- runFlow:
    when:
      visible: "Special Offer!"
    commands:
      - tapOn: "Close"

- runFlow:
    when:
      platform: iOS
    file: ios_specific.yaml
```

**Environment Variables:**
```yaml
env:
  USERNAME: ${TEST_USER}
---
- inputText: ${USERNAME}
```

CLI: `maestro test -e USERNAME=testuser flow.yaml`

**Sources:** [Maestro YAML Guide](https://maestro.dev/insights/how-to-write-yaml-test-scripts-for-mobile-apps), [DeepWiki UI Commands](https://deepwiki.com/mobile-dev-inc/maestro-docs/4.1-ui-interaction-commands), [Alexander Weiss Blog](https://alexanderweiss.dev/blog/2023-02-11-ios-ui-testing-with-maestro)

#### 4. iOS-Specific Capabilities and Limitations

**What works:**
- iOS Simulator only (physical devices NOT supported)
- All core commands (tap, input, scroll, swipe, assert)
- System permission dialogs (location, notifications, camera) via `permissions:` config
- Multi-app journeys (launch Safari, return to app)
- `clearState: true` on launchApp to reset app state
- Both SwiftUI and UIKit apps

**Accessibility ID Mapping (critical for Noto):**
- `accessibilityIdentifier` in SwiftUI/UIKit --> maps to `id` in Maestro selectors
- `accessibilityLabel` in SwiftUI/UIKit --> maps to `text` in Maestro selectors

SwiftUI example:
```swift
TextField("Note title", text: $title)
    .accessibilityIdentifier("note_title_field")
```
Maestro flow:
```yaml
- tapOn:
    id: "note_title_field"
- inputText: "My Note"
```

**Known iOS Gotchas:**
- **Keyboard handling**: `hideKeyboard` on iOS works by scrolling up/down from the middle of the screen (no native iOS API to dismiss keyboard). Can be unreliable.
- **Custom keyboards**: If your app uses a custom keyboard (not the system keyboard), `inputText` will fail with "Keyboard not presented within 1 second timeout."
- **WheelPickerStyle**: Accessibility hierarchy not returned for wheel pickers.
- **Toggle with text**: When a SwiftUI Toggle is initialized with text, its accessibility element is a union of text + toggle, making selection tricky.
- **Link views**: Sometimes only one of accessibilityLabel or accessibilityIdentifier is available.
- **List/Group**: Sometimes don't assign accessibility IDs correctly.
- **Parallel execution**: Limited by macOS hardware -- Maestro Cloud solves this with a fleet of simulators.

**Sources:** [Maestro iOS Docs](https://docs.maestro.dev/get-started/supported-platform/ios), [GitHub Issue #2187](https://github.com/mobile-dev-inc/maestro/issues/2187), [Maestro Do's & Don'ts](https://medium.com/@NirajsubediQA/mastering-maestro-dos-don-ts-of-mobile-ui-automation-be383c2607ce)

#### 5. Running Tests -- CLI Commands

```bash
# Run a single flow
maestro test flow.yaml

# Run all flows in a directory
maestro test .maestro/

# Target a specific simulator by UDID
maestro --device 5B6D77EF-2AE9-47D0-9A62-70A1ABBC5FA2 test flow.yaml

# Run with environment variables
maestro test -e APP_ID=com.noto.app -e USERNAME=test flow.yaml

# Run with tag filtering
maestro test --include-tags smoke .maestro/
maestro test --exclude-tags slow .maestro/

# Continuous mode (re-runs on file change)
maestro test -c flow.yaml

# Generate test reports
maestro test --format JUNIT --test-output-dir results/ .maestro/
maestro test --format HTML --test-output-dir results/ .maestro/

# Record video of test execution
maestro record flow.yaml output.mp4

# Launch Maestro Studio (interactive visual IDE)
maestro studio

# Start a simulator
maestro start-device --platform ios --os-version 18

# Shard tests across devices
maestro test -s 3 .maestro/

# AI-powered analysis (beta)
maestro test --analyze .maestro/
```

**Sources:** [Maestro CLI Docs](https://docs.maestro.dev/maestro-cli/maestro-cli-commands-and-options)

#### 6. Maestro vs. XCUITest

| Aspect | Maestro | XCUITest |
|--------|---------|----------|
| **Language** | YAML (declarative) | Swift (imperative) |
| **Setup complexity** | Install CLI, write YAML | Built into Xcode, add UI test target |
| **Compilation** | None (interpreted) | Required (compiled with app) |
| **Flakiness handling** | Built-in auto-wait, retry | Manual waits needed |
| **Cross-platform** | iOS + Android + Web | iOS only |
| **Speed** | Slower than XCUITest | ~50% faster than Maestro |
| **Debugging** | Maestro Studio, video recording | Xcode debugger, breakpoints |
| **CI/CD** | Simple CLI, any CI | Requires macOS runner with Xcode |
| **Real devices** | Not supported (iOS) | Fully supported |
| **System dialogs** | Built-in permission handling | Requires addUIInterruptionMonitor |
| **Learning curve** | Very low (YAML) | Medium (Swift + XCTest APIs) |
| **Deep integration** | Black-box only | White-box possible (same process) |
| **Community** | Growing (13k stars) | Mature (Apple-backed) |

**When to use Maestro:**
- Smoke tests and critical path E2E tests
- When flakiness is your main pain point
- When non-engineers need to write/read tests
- When you want fast test authoring (10 min for a full flow)

**When to use XCUITest:**
- Performance-sensitive test suites
- Need breakpoint debugging during tests
- Need to test on real devices
- Deep integration with Xcode tooling

**Recommended hybrid approach (from industry):** Use XCUITest for unit-level UI tests, Maestro for smoke/E2E tests.

**Sources:** [QA Wolf Comparison](https://www.qawolf.com/blog/the-best-mobile-e2e-testing-frameworks-in-2025-strengths-tradeoffs-and-use-cases), [Drizz Comparison](https://www.drizz.dev/post/mobile-ui-testing-platforms-2026)

#### 7. Best Practices for a Note-Taking App (Noto)

**Accessibility IDs to add in Noto:**
```swift
// NoteListView
List { ... }
    .accessibilityIdentifier("note_list")

// Each note row
NoteRow(note: note)
    .accessibilityIdentifier("note_row_\(note.id)")

// Editor
TextEditor(text: $content)
    .accessibilityIdentifier("note_editor")

// New note button
Button("New Note") { ... }
    .accessibilityIdentifier("new_note_button")

// Navigation/toolbar items
.accessibilityIdentifier("settings_button")
.accessibilityIdentifier("back_button")
```

**Example flows for Noto:**

```yaml
# .maestro/notes/create_note.yaml
appId: com.noto.app
name: "Create a new note"
tags:
  - smoke
  - notes
---
- launchApp:
    clearState: true
- tapOn:
    id: "new_note_button"
- inputText: "# Shopping List"
- pressKey: Enter
- inputText: "- Milk"
- pressKey: Enter
- inputText: "- Eggs"
- assertVisible: "Shopping List"
```

```yaml
# .maestro/notes/markdown_formatting.yaml
appId: com.noto.app
name: "Verify markdown input"
tags:
  - notes
  - editor
---
- launchApp:
    clearState: true
- tapOn:
    id: "new_note_button"
- inputText: "# Heading One"
- pressKey: Enter
- inputText: "**bold text**"
- pressKey: Enter
- inputText: "- [ ] unchecked task"
- pressKey: Enter
- inputText: "- [x] checked task"
- assertVisible: "Heading One"
- assertVisible: "bold text"
```

```yaml
# .maestro/navigation/folder_navigation.yaml
appId: com.noto.app
name: "Navigate between folders"
tags:
  - navigation
---
- launchApp
- assertVisible:
    id: "note_list"
- tapOn: "Daily Notes"
- assertVisible: "Daily Notes"
- tapOn:
    id: "back_button"
- assertVisible:
    id: "note_list"
```

```yaml
# .maestro/notes/edit_existing_note.yaml
appId: com.noto.app
name: "Open and edit an existing note"
tags:
  - notes
---
- launchApp
- runFlow: common/create_note.yaml
- tapOn:
    id: "back_button"
- tapOn: "Shopping List"
- tapOn:
    id: "note_editor"
- pressKey: Enter
- inputText: "- Bread"
- assertVisible: "Bread"
```

```yaml
# .maestro/common/create_note.yaml
appId: com.noto.app
name: "Create a note (reusable)"
tags:
  - util
---
- tapOn:
    id: "new_note_button"
- inputText: "Shopping List"
- pressKey: Enter
```

**Tips for testing a markdown note-taking app:**
1. Use `inputText` for typing markdown -- Maestro types character by character into the focused field
2. Use `pressKey: Enter` for newlines (don't embed `\n` in inputText)
3. Assert on visible text content, not on markdown syntax (since markdown is rendered)
4. Use `clearState: true` on `launchApp` to ensure each test starts fresh
5. For file-based apps like Noto: consider that `clearState` clears the app sandbox but vault files in user-chosen directories may persist. You may need to handle vault setup in your test flow
6. Add `accessibilityIdentifier` to every interactive element in your SwiftUI views
7. Use `eraseText` before `inputText` when editing pre-filled fields
8. For the editor (UIKit UITextView wrapped in SwiftUI): ensure the UITextView has `accessibilityIdentifier` set via the UIViewRepresentable

#### 8. Project Structure

**Recommended layout for Noto:**
```
Noto/
  .maestro/
    config.yaml              # Workspace configuration
    notes/
      create_note.yaml
      edit_note.yaml
      delete_note.yaml
      markdown_formatting.yaml
    navigation/
      folder_navigation.yaml
      vault_setup.yaml
    daily_notes/
      daily_note_creation.yaml
    settings/
      settings_flow.yaml
    common/
      create_note.yaml       # Reusable subflow
      setup_vault.yaml       # Reusable subflow
```

**config.yaml:**
```yaml
flows:
  - notes/*
  - navigation/*
  - daily_notes/*
  - settings/*

excludeTags:
  - util

executionOrder:
  continueOnFailure: true
```

**Naming convention:** `snake_case.yaml` with descriptive names (e.g., `create_note_with_markdown.yaml`, not `test1.yaml`).

**Sources:** [Maestro Best Practices Blog](https://maestro.dev/blog/maestro-best-practices-structuring-your-test-suite), [Workspace Management Docs](https://docs.maestro.dev/maestro-flows/workspace-management/workspace-management-overview)

---

### Contradictions

1. **Installation method**: The GitHub README recommends `curl -fsSL "https://get.maestro.mobile.dev" | bash`, while some blog posts recommend Homebrew (`brew install maestro` + idb-companion). The curl method appears to be the officially recommended path as of 2026. Homebrew may work but is less prominently documented.

2. **Java requirement**: The GitHub README explicitly requires Java 17+, but some blog posts and the docs landing page mention Node.js 14+ as a prerequisite. These may both be true for different use cases (Java for the CLI runtime, Node for web testing), or the Node requirement may be outdated.

3. **Real device support**: Most sources say iOS physical devices are NOT supported. However, [BrowserStack](https://www.browserstack.com/guide/maestro-real-ios-device-testing) and [Bird Eats Bug](https://birdeatsbug.com/blog/maestro-real-ios-device-support) discuss real device testing -- this appears to be through cloud services (BrowserStack, Maestro Cloud) rather than local Maestro CLI support.

### Confidence Assessment

**Well-established:**
- YAML syntax, core commands, and flow structure -- documented across multiple official and third-party sources
- iOS Simulator-only limitation -- universally confirmed
- Accessibility ID mapping (accessibilityIdentifier -> id, accessibilityLabel -> text) -- confirmed in official docs and multiple blog posts
- Built-in auto-wait as the core flakiness-reduction mechanism -- confirmed everywhere
- No app-side SDK/dependency required -- confirmed everywhere

**Moderately confident:**
- Installation via curl is the current recommended method (confirmed in GitHub README, may have changed in latest docs)
- Java 17+ requirement (from GitHub README, not contradicted elsewhere)
- `hideKeyboard` reliability issues on iOS (from GitHub issues, not officially documented as a limitation)

**Uncertain/Actively debated:**
- Whether Maestro is truly "deterministic" vs. just "more reliable" -- the auto-wait mechanism reduces flakiness but does not eliminate it entirely. Some GitHub issues report hangs on macOS 15.6.
- Performance comparison numbers (XCUITest "50% faster") come from a single source and may be context-dependent
- idb-companion requirement -- some sources mention it, others don't. May no longer be required in newer versions.

### Gaps

1. **TextKit 1 / UITextView behavior** -- No sources cover how Maestro interacts with a raw UITextView wrapped in UIViewRepresentable (which is Noto's editor architecture). It's unclear if `inputText` works correctly with TextKit 1's NSTextStorage, or if the text view needs specific accessibility configuration.

2. **File system interaction** -- Noto uses a user-chosen vault directory. No sources address how to set up test fixtures (pre-existing markdown files) for E2E tests, or how `clearState` interacts with security-scoped bookmarks.

3. **YAML frontmatter verification** -- No information on how to assert file contents on disk after a Maestro test (Maestro only sees the UI, not the filesystem).

4. **Maestro + Xcode build integration** -- No clear documentation on how to build the app and run Maestro tests in a single CI step specifically for Swift/Xcode projects (most CI examples assume the app is already built).

5. **Current version and changelog** -- Could not access the actual docs site reliably to confirm the latest version and any recent breaking changes.

---

## Follow-up Questions

1. **How does Maestro's `inputText` interact with UITextView (TextKit 1)?** -- Noto uses a UIKit UITextView wrapped in UIViewRepresentable for its markdown editor. Need to verify that `inputText` works with this setup and whether the UITextView needs specific accessibility configuration beyond `accessibilityIdentifier`.

2. **How to handle vault setup in Maestro tests?** -- Noto requires a user-chosen vault directory on first launch. Need to determine whether to use `clearState` + UI-based vault setup in every test, or if there's a way to pre-configure the app state (e.g., by pre-populating UserDefaults or the app sandbox).

3. **What is the current recommended installation method and Java/idb-companion requirements for Maestro on macOS in 2026?** -- Conflicting info about Homebrew vs curl, Java vs Node, and whether idb-companion is still needed.

4. **How to integrate Maestro test runs into an Xcode build pipeline?** -- Specifically: build with xcodebuild, install on simulator, then run maestro test, all in one script suitable for local development and CI.

5. **Does Maestro support asserting on text attributes (bold, heading size) or only plain text content?** -- For a markdown editor, need to know if Maestro can verify that rendered markdown looks correct beyond just text presence.

---

## Source List

- [Maestro GitHub Repository](https://github.com/mobile-dev-inc/Maestro)
- [Maestro Docs Landing Page](https://docs.maestro.dev/)
- [Maestro Docs - iOS Support](https://docs.maestro.dev/get-started/supported-platform/ios)
- [Maestro CLI Commands and Options](https://docs.maestro.dev/maestro-cli/maestro-cli-commands-and-options)
- [Maestro Workspace Management](https://docs.maestro.dev/maestro-flows/workspace-management/workspace-management-overview)
- [Maestro Best Practices: Structuring Test Suite](https://maestro.dev/blog/maestro-best-practices-structuring-your-test-suite)
- [How to Write YAML Test Scripts](https://maestro.dev/insights/how-to-write-yaml-test-scripts-for-mobile-apps)
- [iOS Regression Testing Best Practices](https://maestro.dev/insights/ios-regression-testing-best-practices)
- [DeepWiki - UI Interaction Commands](https://deepwiki.com/mobile-dev-inc/maestro-docs/4.1-ui-interaction-commands)
- [Alexander Weiss - iOS UI Testing with Maestro](https://alexanderweiss.dev/blog/2023-02-11-ios-ui-testing-with-maestro)
- [Paul Samuels - Mobile UI Testing with Maestro](https://paul-samuels.com/blog/2023/11/20/mobile-ui-testing-with-maestro/)
- [Mastering Maestro Do's and Don'ts (Medium)](https://medium.com/@NirajsubediQA/mastering-maestro-dos-don-ts-of-mobile-ui-automation-be383c2607ce)
- [BrowserStack - Maestro Testing Guide](https://www.browserstack.com/guide/maestro-testing)
- [QA Wolf - E2E Testing Frameworks 2025](https://www.qawolf.com/blog/the-best-mobile-e2e-testing-frameworks-in-2025-strengths-tradeoffs-and-use-cases)
- [Drizz - Mobile UI Testing 2026](https://www.drizz.dev/post/mobile-ui-testing-platforms-2026)
- [TestDevLab - Maestro Beginner's Guide](https://www.testdevlab.com/blog/getting-started-with-maestro-mobile-ui-testing-framework)
- [Bitrise - Getting Started with Maestro](https://bitrise.io/blog/post/getting-started-with-maestro-the-new-mobile-ui-testing-framework-from-mobile-dev)
- [GitHub Issue #2187 - iOS Keyboard](https://github.com/mobile-dev-inc/maestro/issues/2187)
- [GitHub Issue #2628 - Silent Hang macOS 15.6](https://github.com/mobile-dev-inc/maestro/issues/2628)
