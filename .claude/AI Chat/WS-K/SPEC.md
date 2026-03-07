# SPEC: WS-K — Polish

## Files Modified

### `Packages/NotoAIChat/Sources/NotoAIChat/AIChatViewModel.swift`
- Add `retryLastMessage()` method — re-sends last user message
- Add `friendlyErrorMessage(_:)` — maps errors to user-friendly strings
- Track `lastUserMessage` for retry
- Accept/dismiss: surface errors to UI via message update

### `Noto/Views/AIChat/AIChatSheet.swift`
- Error banner: add Retry button
- Composer: disable when state is `.loading` or `.streaming`
- ScrollView: add `.scrollDismissesKeyboard(.interactively)`

### `Noto/Views/AIChat/SuggestedEditCard.swift`
- Add error state display when accept fails
- Accessibility: group card, label buttons

### `Noto/Views/AIChat/ChatComposerBar.swift`
- Add `isDisabled` parameter
- Dim appearance when disabled

### `Noto/Views/AIChat/ChatMessageRow.swift`
- Accessibility grouping for message types
