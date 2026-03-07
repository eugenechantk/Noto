# PRD: WS-K — Polish

## Scope
Final polish pass on AI Chat. Focus on error UX, composer state, accessibility, and edge cases.

## Changes

### 1. Error states with retry
- Map ClaudeAPIError to user-friendly messages (network, rate limit, server error)
- Add Retry button to error banner that re-sends the last message
- Clear error state when user sends a new message

### 2. Composer state management
- Disable send button and text field while loading/streaming
- Visual feedback (dimmed state)

### 3. Accessibility improvements
- VoiceOver labels on all interactive elements
- Proper grouping for suggested edit cards
- Accessibility traits on buttons

### 4. Edge case: stale edit proposal
- If acceptEdit throws (stale, not found), show error in the card instead of silently failing

### 5. Scroll behavior
- Auto-scroll to bottom on new messages and loading indicator
- ScrollView keyboard dismiss on drag
