# SPEC: AIChatBlockStore + AI Chat Root + DirtyTracker Wiring

## Files

### `AIChatRootService.swift`
- Struct with static methods (mirrors TodayNotesService pattern)
- `ensureRoot(context:)`: FetchDescriptor predicate for parent == nil, content == "AI Chat", not archived. Create if missing with protection flags.

### `AIChatBlockStore.swift`
- Struct with static methods
- Each mutation method creates Block with parent, sortOrder (sortOrderForAppending), extensionData, MetadataField entries, and calls dirtyTracker.markDirty

#### Method Details

- **createConversation**: Block under AI Chat root with ConversationExtension. Content = "Conversation". Role metadata.
- **addUserMessage**: Block under conversation with UserMessageExtension. Content = user text. turnIndex = existing child count. Role + turnIndex metadata.
- **addAIResponse**: Block under conversation with AIResponseExtension. Content = AI text. turnIndex = existing child count. Role + turnIndex metadata.
- **addSuggestedEdit**: Block under conversation with SuggestedEditExtension. Content = proposal summary. Role + status metadata.
- **updateEditStatus**: Decode SuggestedEditExtension, update status, re-encode. Update status MetadataField. Mark dirty.
- **fetchConversations**: Children of AI Chat root, sorted by sortOrder.
- **fetchMessages**: Children of conversation, sorted by sortOrder.

## Tests
Swift Testing (@Test, #expect) with in-memory ModelContainer. Verify block tree structure, extensionData decoding, metadata fields, dirty tracking, sort ordering.
