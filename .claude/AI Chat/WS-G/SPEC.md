# Technical Spec: WS-G Service Layer

## Package Changes

Add `NotoClaudeAPI` and `NotoSearch` as dependencies to `Packages/NotoAIChat/Package.swift`.

## New Files

```
Sources/NotoAIChat/
  SearchServiceProtocol.swift   -- Protocol for testable search
  NotoToolDefinitions.swift     -- Three tool schemas
  NotoToolExecutor.swift        -- ToolExecutor conformance
  AIChatService.swift           -- Orchestrator
  SystemPromptBuilder.swift     -- System prompt construction
  ChatResult.swift              -- Return type from AIChatService
  ToolInputTypes.swift          -- Decodable input structs for each tool

Tests/NotoAIChatTests/
  NotoToolExecutorTests.swift   -- Mock search, verify dispatch
  AIChatServiceTests.swift      -- Mock client, verify result assembly
```

## Key Design

### SearchServiceProtocol
```swift
public protocol SearchServiceProtocol: Sendable {
    @MainActor func search(rawQuery: String) async -> [SearchResult]
}
extension SearchService: SearchServiceProtocol {}
```

### NotoToolExecutor
- Holds a `SearchServiceProtocol` and a `ModelContext`
- `execute()` switches on tool name, decodes input from JSONValue, calls appropriate service
- Accumulates `references: [BlockReference]` and `editProposal: EditProposal?`
- For `get_block_context`: walks Block.parent chain up (levelsUp), Block.sortedChildren down (levelsDown), siblings at same level

### AIChatService
- init(apiKey, searchService, modelContext, config)
- chat(userMessage, history, noteContext) async throws -> ChatResult
- Creates fresh NotoToolExecutor per call
- Delegates to ChatLoop.run()

### Test Strategy
- MockSearchService returns canned SearchResults
- MockClaudeClient (from NotoClaudeAPI tests pattern) returns canned responses
- Verify: tool dispatch routes correctly, references accumulated, edit proposals captured, ChatResult assembled
