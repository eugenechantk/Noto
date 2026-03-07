# PRD: NotoToolExecutor + NotoToolDefinitions + AIChatService

## Overview

Service layer connecting the NotoClaudeAPI package to local Noto data. Implements Noto-specific tool definitions, a ToolExecutor that dispatches to local services, and an AIChatService orchestrator.

## Components

### NotoToolDefinitions
Three tool schemas sent with every Claude API request:
- `search_notes` — keyword/semantic/date search via SearchService
- `get_block_context` — fetch block with ancestors, descendants, and siblings from ModelContext
- `suggest_edit` — capture edit proposal for user review (not auto-applied)

### NotoToolExecutor
Conforms to NotoClaudeAPI's `ToolExecutor` protocol. Dispatches by tool name:
- `search_notes` -> calls SearchService, returns JSON array of results with blockId, content, breadcrumb
- `get_block_context` -> walks Block tree (parent chain up, children down, siblings sideways), returns structured JSON
- `suggest_edit` -> parses proposal, stores it, returns acknowledgment string
- Unknown tools -> returns error ToolResult

Accumulates state: collected `references` and optional `editProposal`.

### AIChatService
Thin orchestrator:
- Creates ChatLoop with NotoToolExecutor
- Builds system prompt with optional note context
- Returns ChatResult (text, references, editProposal, toolCallHistory)

### SearchServiceProtocol
Protocol abstraction over SearchService for testability. Single method: `search(rawQuery:) async -> [SearchResult]`.

### SystemPromptBuilder
Builds system prompt including:
- Base instructions (role, behavior guidelines)
- Current date for temporal awareness
- Optional note context (title + breadcrumb of the note the user is viewing)

## Non-Goals
- UI/ViewModel layer (app target concern)
- Block persistence of chat messages (already in AIChatBlockStore)
- Edit application logic (future WS)
