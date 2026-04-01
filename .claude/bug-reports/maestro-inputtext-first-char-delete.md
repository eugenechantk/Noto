# Maestro inputText: First Character Deleted After Typing

## Summary of Root Cause

The "type first character, then delete it" behavior is caused by **iOS autocorrect/predictive text interacting with Maestro's keyboard event synthesis**. When Maestro sends the first character via synthesized keyboard events, iOS's autocorrect system marks it as provisional text (marked text / composing region). When the next batch of characters arrives (after Maestro's 500ms delay), iOS's keyboard system replaces the marked text rather than appending — which manifests as a `deleteBackward` + re-insert of the corrected text, minus the original first character.

## How Maestro Sends Keystrokes on iOS

Maestro does NOT use `XCUIElement.typeText()`. It uses Apple's private XCTest APIs:

1. `XCPointerEventPath.initForTextInput()` — creates a keyboard event path
2. `eventPath.typeText(text:typingSpeed:shouldRedact:)` — queues keystroke events
3. `XCTRunnerDaemonSession._XCT_synthesizeEvent(eventRecord:)` — sends the synthesized events to the iOS system

The critical implementation in `TextInputHelper.swift` splits text into two parts:

```swift
// First character typed at speed 1 (slow)
let firstCharacter = String(text.prefix(1))
eventPath.type(text: firstCharacter, typingSpeed: 1)
// ... synthesize first character

// 500ms delay
try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * 0.5))

// Remaining text typed at speed 30 (fast)
let remainingText = String(text.suffix(text.count - 1))
eventPath2.type(text: remainingText, typingSpeed: 30)
// ... synthesize remaining text
```

This two-phase approach was introduced to work around character skipping (PR #1417, September 2023). The comment in the code says:

> "due to different keyboard input listener events (i.e. autocorrection or hardware keyboard connection) characters after the first one are often skipped, so we'll input it with lower typing frequency"

## The Autocorrect Interference Mechanism

Here is what happens step by step:

1. **Maestro sends the first character** (e.g., "H") at typing speed 1
2. **iOS keyboard system receives it** and, with autocorrect enabled, puts it into a "marked text" (composing) state — the character is provisionally inserted but iOS considers it part of an in-progress word
3. **500ms passes** (Maestro's built-in delay)
4. **iOS autocorrect/predictive text activates** during the 500ms gap — it may offer an inline prediction or autocorrect suggestion based on the single character
5. **Maestro sends the remaining characters** (e.g., "ello World") at typing speed 30
6. **iOS keyboard processes the new input** — but because the first character was in a marked/composing state, the keyboard system replaces the marked region (deleting "H") and inserts the new text starting fresh, OR the inline prediction replaces the provisional first character

The net effect: the first character gets deleted (backspace event) and then the remaining text is typed, resulting in missing first character.

## Evidence

### Maestro's own changelog confirms autocorrect was a problem:
- v1.24.0 (March 2023): **"Autocorrect is no longer applied to inputText on iOS"** — an explicit fix
- But the current implementation still uses synthesized keyboard events that go through the iOS keyboard pipeline, where autocorrect/predictive text can still interfere

### Maestro issue #1225 shows the exact symptom:
- `mobiletestfreeuser` became `mbiletestfreeusero` — first char dropped, last char duplicated at end
- More stable on iOS 16 (before iOS 17's aggressive inline predictions)

### Maestro issue #395 shows character skipping:
- `simon@cookin.com` became `son@cooking.com` — first characters missing
- Multiple users reported this across versions

### iOS 17+ inline predictions make it worse:
- iOS 17 introduced inline predictive text that tries to autocomplete words as you type
- Accepting a prediction replaces the typed text
- During automated input, the prediction system can activate during Maestro's 500ms delay between first character and remaining text

## Why This Specifically Affects Noto

Noto's `MarkdownEditorView` has:
```swift
textView.autocorrectionType = .default  // autocorrect ON
textView.autocapitalizationType = .sentences  // auto-capitalize ON
```

Both of these cause iOS to actively process keyboard input through its text correction pipeline, which interferes with Maestro's synthesized events.

## Solutions (from most to least reliable)

### 1. Disable autocorrect/autocapitalize on the simulator (system level)

Before running Maestro tests, disable keyboard features on the simulator:

```bash
DEVICE_UUID=$(xcrun simctl list devices booted -j | python3 -c "import json,sys; d=json.load(sys.stdin); print(list(d['devices'].values())[0][0]['udid'])" 2>/dev/null)
PLIST_PATH="$HOME/Library/Developer/CoreSimulator/Devices/$DEVICE_UUID/data/Library/Preferences/com.apple.Preferences.plist"

defaults write "$PLIST_PATH" KeyboardAutocorrection -bool NO
defaults write "$PLIST_PATH" KeyboardAutocapitalization -bool NO
defaults write "$PLIST_PATH" KeyboardCheckSpelling -bool NO
defaults write "$PLIST_PATH" KeyboardPrediction -bool NO
```

Note: Settings may reset on simulator reboot. Run after boot, before launching the app.

### 2. Disable autocorrect on the UITextView (app level, test-only)

Add a launch argument or environment variable that disables autocorrect when running under Maestro:

```swift
// In MarkdownEditorView
textView.autocorrectionType = .no
textView.autocapitalizationType = .none
textView.spellCheckingType = .no
if #available(iOS 17.0, *) {
    textView.inlinePredictionType = .no
}
```

For production, gate behind a test flag:
```swift
if ProcessInfo.processInfo.environment["MAESTRO_TEST"] != nil {
    textView.autocorrectionType = .no
    textView.autocapitalizationType = .none
    textView.spellCheckingType = .no
}
```

### 3. Workaround in Maestro flow (least reliable)

Type one character at a time with delays:
```yaml
- tapOn:
    id: "note_editor"
- inputText: "H"
- inputText: "ello World"
```

Or use the retry pattern some users have adopted:
```yaml
- inputText: "Hello World"
- assertVisible: "Hello World"
```

### 4. Use clipboard paste instead of typing

```yaml
- runScript:
    script: |
      // Copy to clipboard approach
- tapOn:
    id: "note_editor"
- longPressOn:
    id: "note_editor"
- tapOn: "Paste"
```

## Recommendation for Noto

**Use solution #2**: disable autocorrect/autocapitalize/spellcheck on the text view when running under Maestro. This is the most reliable fix because:
- It prevents iOS from processing typed text through the correction pipeline entirely
- It doesn't require simulator configuration that can be fragile
- It matches what the text actually needs (a markdown editor arguably shouldn't aggressively autocorrect anyway)
- The `MAESTRO_TEST` environment variable keeps production behavior unchanged

Additionally, if you want autocorrect in production, consider setting `inlinePredictionType = .no` (iOS 17+) even in production, since inline predictions interfere with markdown editing.
