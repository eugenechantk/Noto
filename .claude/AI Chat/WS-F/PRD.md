# PRD: AIChatBlockStore + AI Chat Root + DirtyTracker Wiring

## Overview

Persistence layer for AI Chat conversations stored as Blocks in the existing SwiftData model. Provides CRUD operations for conversations, messages, AI responses, and suggested edits, with DirtyTracker integration for FTS5/HNSW indexing.

## Goals

1. Create a protected "AI Chat" root block (mirrors Today's Notes root pattern)
2. Provide a block store API for creating/reading chat entities (conversations, messages, responses, edits)
3. Wire all mutations through DirtyTracker for search indexing

## Data Model

All chat entities are stored as Block objects with typed extensionData:

- **AI Chat Root**: Top-level protected block (isDeletable=false, isContentEditableByUser=false, isReorderable=false, isMovable=false)
- **Conversation**: Child of root, extensionData = ConversationExtension
- **User Message**: Child of conversation, extensionData = UserMessageExtension
- **AI Response**: Child of conversation, extensionData = AIResponseExtension
- **Suggested Edit**: Child of conversation, extensionData = SuggestedEditExtension

## API Surface

### AIChatRootService
- `ensureRoot(context:)` -> Block: Find or create the AI Chat root block

### AIChatBlockStore
- `createConversation(noteContext:context:dirtyTracker:)` -> Block
- `addUserMessage(content:to:context:dirtyTracker:)` -> Block
- `addAIResponse(text:references:toolCalls:to:context:dirtyTracker:)` -> Block
- `addSuggestedEdit(proposal:parentResponseId:to:context:dirtyTracker:)` -> Block
- `updateEditStatus(_:status:context:dirtyTracker:)` -> updates extensionData + metadata
- `fetchConversations(context:)` -> [Block]
- `fetchMessages(for:context:)` -> [Block]

## Constraints

- All new blocks must call `dirtyTracker.markDirty(block.id)`
- Use fractional indexing (sortOrderForAppending) for ordering
- Use MetadataField for queryable attributes (role, status, turnIndex)
- Use os_log for logging
