# AI Chat Planning — Claude's Analysis & Recommendations

Based on Figma frame `26:1972` and the initial brainstorm (`Brainstorm-ai-chat.md`).

---

## Figma Design Breakdown

The screenshot shows a **bottom sheet** with these distinct content zones:

### 1. User message bubble

- Right-aligned, white background, rounded pill shape
- Example: "what am i thinking today"

### 2. AI response (two sub-sections)

- **Reference blocks**: "Found 4 notes" header + collapsible `>` bullet list of matched blocks (truncated with ellipsis for long text)
- **Response body**: Standard text with lists/paragraphs (the actual AI answer)

### 3. Suggested edits card

- Green-bordered diff view:
  - Context lines (grey, existing blocks)
  - Addition lines (green bg, `+` marker)
  - Bottom action bar: `Dismiss` | `Accept` (green)

### 4. Bottom composer

- "Ask anything" text field + send button, pinned to bottom

### 5. Sheet chrome

- Grabber handle at top
- Centered "AI Chat" title
- Back/close button (chevron left)

---

## Open Decision Recommendations

### 1. LLM provider strategy

**Recommendation: Remote API (Claude) for v1.**

- On-device models can't handle tool-calling + grounded reasoning well enough yet.
- `NotoEmbedding` already handles on-device semantic search — that's the right split (local retrieval, remote reasoning).
- Ship with a single provider. Add a protocol/abstraction for swapping later.

### 2. Conversation persistence — STORED AS BLOCKS

**Recommendation: Store chat conversations using the Block data model.**

Instead of ephemeral ViewModel state or a separate entity, each chat conversation is a **tree of Blocks** using `extensionData` to encode chat-specific metadata.

#### Block tree structure for a conversation

```
Conversation Root Block
  extensionData: { role: .conversation, noteContextId: UUID? }
  isArchived: false
  isDeletable: true, isContentEditableByUser: false
  isReorderable: false, isMovable: false
│
├── [sortOrder 1] User Message Block
│     content: "what am i thinking today"
│     extensionData: { role: .userMessage }
│     isContentEditableByUser: false (sent messages are immutable)
│
├── [sortOrder 2] AI Response Block
│     content: "You are thinking about a lot of things:\n1. ..."
│     extensionData: {
│       role: .aiResponse,
│       references: [
│         { blockId: UUID, excerpt: "but this is a bullet", breadcrumb: "Today / Not too bad" },
│         { blockId: UUID, excerpt: "this is another bullet", breadcrumb: "Today / Not too bad" }
│       ],
│       toolCalls: [ { name: "search_notes", input: {...}, output: {...} } ]
│     }
│     outgoingLinks: [BlockLink -> referenced source blocks] (for navigation)
│     isContentEditableByUser: false
│
├── [sortOrder 3] Suggested Edit Block
│     content: "" (display is driven by extensionData)
│     extensionData: {
│       role: .suggestedEdit,
│       parentResponseId: UUID (links back to the AI response that proposed it),
│       proposal: {
│         operations: [
│           { type: .addBlock, parentId: UUID, afterBlockId: UUID?, content: "today is a lovely day..." },
│           { type: .updateBlock, blockId: UUID, newContent: "..." }
│         ]
│       },
│       status: .pending | .accepted | .dismissed,
│       appliedAt: Date?
│     }
│     isContentEditableByUser: false
│
├── [sortOrder 4] User Message Block
│     content: "tell me more about that"
│     ...
│
└── [sortOrder 5] AI Response Block
      ...
```

#### Codable extension types (stored in `extensionData`)

```swift
// Top-level discriminator
enum ChatBlockRole: String, Codable {
    case conversation    // root block for a chat session
    case userMessage     // user's chat message
    case aiResponse      // AI's text response (may include references)
    case suggestedEdit   // edit proposal with accept/dismiss
}

// Decoded from extensionData based on role
struct ConversationExtension: Codable {
    let role: ChatBlockRole  // .conversation
    var noteContextId: UUID? // the note the user was viewing when chat started
}

struct UserMessageExtension: Codable {
    let role: ChatBlockRole  // .userMessage
}

struct AIResponseExtension: Codable {
    let role: ChatBlockRole  // .aiResponse
    var references: [BlockReference]
    var toolCalls: [ToolCallRecord]?
}

struct BlockReference: Codable {
    let blockId: UUID
    let excerpt: String      // truncated content snapshot at query time
    let breadcrumb: String   // e.g. "Today / Not too bad"
}

struct ToolCallRecord: Codable {
    let toolName: String
    let input: Data          // JSON-encoded tool input
    let output: Data         // JSON-encoded tool output
}

struct SuggestedEditExtension: Codable {
    let role: ChatBlockRole  // .suggestedEdit
    let parentResponseId: UUID
    var proposal: EditProposal
    var status: EditStatus
    var appliedAt: Date?
}

enum EditStatus: String, Codable {
    case pending, accepted, dismissed
}

struct EditProposal: Codable {
    let operations: [EditOperation]
}

enum EditOperation: Codable {
    case addBlock(parentId: UUID, afterBlockId: UUID?, content: String)
    case updateBlock(blockId: UUID, newContent: String)
}
```

#### Rendering logic

The chat UI iterates `conversationRoot.sortedChildren` and switches on the decoded role:

- `.userMessage` -> right-aligned white bubble
- `.aiResponse` -> left-aligned: optional "Found N notes" references header + response body text
- `.suggestedEdit` -> green-bordered diff card with Dismiss/Accept buttons

#### Why this works well

- **No schema changes**: `extensionData` already exists on Block
- **Searchable**: AI conversations appear in search results like any content
- **Navigable**: BlockLinks from AI responses to referenced blocks enable "tap to jump"
- **Protection flags**: `isContentEditableByUser: false` prevents accidental edits to chat messages; `isReorderable: false` keeps message order fixed
- **Cascade delete**: Deleting the conversation root auto-deletes all messages via `@Relationship(deleteRule: .cascade)`
- **Persistence for free**: Conversations survive app restarts via SwiftData

#### "AI Chat" root block — protected system node

Following the same pattern as `TodayNotesService.ensureRoot`, create a protected root-level "AI Chat" block that holds all conversations.

```swift
// Lives in NotoAIChat package
public struct AIChatRootService {
    @MainActor
    public static func ensureRoot(context: ModelContext) -> Block {
        let descriptor = FetchDescriptor<Block>(
            predicate: #Predicate<Block> { block in
                block.parent == nil && block.content == "AI Chat" && !block.isArchived
            }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let root = Block(
            content: "AI Chat",
            sortOrder: Double.leastNormalMagnitude + 1,  // just after Today's Notes
            isDeletable: false,
            isContentEditableByUser: false,
            isReorderable: false,
            isMovable: false
        )
        context.insert(root)
        return root
    }
}
```

**Block tree under AI Chat root:**

```
AI Chat (root, protected — not deletable, not editable, not reorderable)
├── "What was I thinking about self-growth" (conversation root)
│   ├── user message
│   ├── AI response
│   ├── suggested edit
│   └── ...
├── "Summarize last month" (conversation root)
│   └── ...
└── ...
```

Each conversation root's `content` is the first user message (or a generated summary). Conversation blocks use the same protection flags documented in the block tree structure above (`isContentEditableByUser: false`, `isReorderable: false`).

#### Indexing — FTS5, HNSW, and DirtyTracker

**All chat blocks should be indexed.** When the user asks "what was I thinking about X", previous AI conversations are valid search results — they contain the user's questions and the AI's synthesized answers.

**DirtyTracker integration:**

- When a new chat turn (user message, AI response, suggested edit) is persisted, call `dirtyTracker.markDirty(block.id)` for each new block
- When an edit proposal is accepted and the suggestion block status changes, call `dirtyTracker.markDirty(suggestEditBlock.id)`
- The existing `DirtyTracker` → `DirtyStore` → FTS5/HNSW reindex pipeline handles the rest automatically
- After persisting a complete turn, call `await dirtyTracker.flush()` to trigger reindexing

```swift
// In AIChatBlockStore, after persisting a turn:
func persistTurn(userBlock: Block, aiBlock: Block, context: ModelContext, dirtyTracker: DirtyTracker) {
    context.insert(userBlock)
    context.insert(aiBlock)
    dirtyTracker.markDirty(userBlock.id)
    dirtyTracker.markDirty(aiBlock.id)
    Task { await dirtyTracker.flush() }
}
```

**What gets indexed per block type:**
| Block role | FTS5 (full-text) | HNSW (semantic) | What's searchable |
|---|---|---|---|
| Conversation root | Yes | Yes | First message / title |
| User message | Yes | Yes | The user's question |
| AI response | Yes | Yes | The AI's answer text |
| Suggested edit | Yes | No | The edit description |

**Note**: Suggested edit blocks have structured `extensionData` but their `content` field can store the `description` string for search indexing. The full proposal JSON stays in `extensionData` and isn't indexed.

#### Filtering chat blocks from normal note views

- The OutlineView's `rootBlocks` filter already shows all root blocks — "AI Chat" will appear alongside "Today's Notes" and user notes
- To hide chat blocks from normal outline display, filter by the "AI Chat" root's descendants (check if ancestor chain includes the AI Chat root)
- For search results, chat blocks are included by default — they're valuable context. A future filter could exclude them if needed.

### 3. Retrieval scope defaults

**Recommendation: All notes by default, with current note as bias signal.**

- The `SearchService` already does hybrid ranking — let it work.
- If the user is viewing "Today / Not too bad", include that context in the system prompt so the model knows where they are.
- Don't restrict scope artificially — the model can call `search_notes` with temporal hints to narrow results.

### 4. Edit operation granularity for v1

**Recommendation: `add_block` and `update_block` only.**

- These cover ~90% of use cases (add a reflection, rewrite a bullet).
- Defer `archive_block`, `move_block`, and `reorder` to v2 — they add complexity in validation and undo.

### 5. Citation UX

**Recommendation: Separate references block only (matches Figma).**

- "Found N notes" + expandable list above the response body.
- Inline markers in answer text add parsing complexity.
- The Figma design already established this pattern — follow it.

### 6. Package structure

**Recommendation: Two new packages under `Packages/`.**

#### `NotoClaudeAPI` — Pure API client + tool framework (no Noto dependencies)

A standalone package that handles all Claude Messages API communication and tool definition/execution abstractions. **Zero dependencies on other Noto packages.** Could theoretically be reused in any Swift project.

Contents:

- `ClaudeAPIClient` — thin URLSession wrapper, Codable request/response types
- `MessagesRequest` / `MessagesResponse` / `ContentBlock` — API DTOs
- `ToolDefinition` / `ToolInputSchema` / `PropertySchema` — tool schema types
- `ToolExecutor` protocol — defines how tools are executed locally
- `ChatLoop` — the capped tool-use loop (sends message, handles tool calls via `ToolExecutor`, returns final result)

Dependencies: **None** (Foundation only)

#### `NotoAIChat` — Noto-specific chat logic

Implements the Noto-specific tools, chat block persistence, and edit application. Depends on `NotoClaudeAPI` for the API layer.

Contents:

- `NotoToolExecutor` — conforms to `ToolExecutor` protocol, implements `search_notes`, `get_block_context`, `suggest_edit` using Noto packages
- `NotoToolDefinitions` — the three tool schemas with Noto-specific descriptions
- `AIChatModels` — chat block extension DTOs (`ChatBlockRole`, `AIResponseExtension`, `SuggestedEditExtension`, etc.)
- `AIChatBlockStore` — read/write conversation block trees
- `AIEditApplier` — validates and applies accepted proposals

Dependencies: `NotoClaudeAPI`, `NotoModels`, `NotoCore`, `NotoSearch`

#### App target — UI only

The SwiftUI sheet (`AIChatSheet`) and `AIChatViewModel` stay in the **app target** since they need UIKit/SwiftUI. The ViewModel calls into `NotoAIChat` for business logic.

#### Updated dependency graph

```
Packages/
├── NotoClaudeAPI       ← Pure Claude API client + tool framework (Foundation only)
├── NotoAIChat          ← Noto-specific chat logic
│   └── depends on: NotoClaudeAPI, NotoModels, NotoCore, NotoSearch
├── NotoModels          ← (existing)
├── NotoCore            ← (existing)
├── NotoSearch          ← (existing)
└── ...
```

---

## `extensionData` vs `metadataFields` — Tradeoff Analysis

The user's brainstorm proposes using `metadataFields` for role/status. This file originally proposed `extensionData` only. Here's the comparison:

| Aspect                             | `extensionData` (Data blob)                                      | `metadataFields` (key-value rows)                              |
| ---------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------- |
| Query/filter                       | Requires decoding blob in memory; can't use SwiftData predicates | Queryable via SwiftData predicates on `fieldName`/`fieldValue` |
| Schema flexibility                 | Strongly typed Codable structs, versioned                        | String key-value pairs, looser typing                          |
| Storage efficiency                 | Single blob per block                                            | N rows per block (one per field)                               |
| Rich data (proposals, tool traces) | Natural fit — nested JSON                                        | Poor fit — would need serialized blob in a value anyway        |

**Recommendation: Use both, each for what it's good at.**

- `metadataFields` for **queryable/filterable** attributes: `noto.ai.role`, `noto.ai.status`, `noto.ai.turnIndex`
- `extensionData` for **rich structured data** that doesn't need predicate filtering: tool call traces, full edit proposals, reference snapshots

This way you can efficiently query "all conversation root blocks" or "all pending suggestions" via `metadataFields` predicates, while keeping complex payloads in `extensionData`.

---

## Tool Call Architecture — Capped Loop with Local Execution

Uses Claude Messages API's native tool use with a **capped iteration loop**. The model can chain tool calls (e.g. search → get context → suggest edit) but is bounded by a configurable max iteration limit to prevent runaway calls.

### API client approach: Thin typed wrapper over URLSession

No official Anthropic Swift SDK exists. We write a small `ClaudeAPIClient` (~150 lines) in the `NotoClaudeAPI` package that handles HTTP + Codable. No third-party dependencies — pure Foundation.

```swift
// Lives in NotoClaudeAPI package
public struct ClaudeAPIClient {
    let apiKey: String
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let session = URLSession.shared

    func sendMessage(_ request: MessagesRequest) async throws -> MessagesResponse {
        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw ClaudeAPIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(MessagesResponse.self, from: data)
    }
}
```

### Codable request/response types

```swift
// MARK: - Request

struct MessagesRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: String?
    let messages: [Message]
    let tools: [ToolDefinition]?
}

struct Message: Codable {
    let role: String  // "user" or "assistant"
    let content: MessageContent
}

// Content can be a simple string or an array of content blocks
enum MessageContent: Codable {
    case text(String)
    case blocks([ContentBlock])
}

enum ContentBlock: Codable {
    case text(TextBlock)
    case toolUse(ToolUseBlock)
    case toolResult(ToolResultBlock)
}

struct TextBlock: Codable {
    let type: String  // "text"
    let text: String
}

struct ToolUseBlock: Codable {
    let type: String  // "tool_use"
    let id: String
    let name: String
    let input: JSONValue  // flexible JSON
}

struct ToolResultBlock: Codable {
    let type: String  // "tool_result"
    let tool_use_id: String
    let content: String  // JSON-encoded result
}

// MARK: - Response

struct MessagesResponse: Decodable {
    let id: String
    let content: [ContentBlock]
    let stop_reason: String  // "end_turn" or "tool_use"
    let usage: Usage
}

struct Usage: Decodable {
    let input_tokens: Int
    let output_tokens: Int
}
```

### Tool schemas — three tools available to Claude

The `tools` array is sent with every request. Claude decides autonomously which tools to call (if any) based on the user's message. Generic questions trigger no tools; note questions trigger search; editing requests trigger suggest_edit.

#### Tool 1: `search_notes` — find relevant blocks

```swift
ToolDefinition(
    name: "search_notes",
    description: """
        Search the user's notes by keyword, semantic similarity, or date range.
        Use this when the user asks about their past notes, thoughts, or writing.
        Do NOT use this for generic questions unrelated to the user's notes.
        Returns matching blocks with their content excerpt, breadcrumb path, and timestamps.
        """,
    input_schema: ToolInputSchema(
        type: "object",
        properties: [
            "query": .init(type: "string", description: "Search query — keywords, phrases, or topics"),
            "date_hint": .init(type: "string", description: "Optional time filter, e.g. 'today', 'last month', 'March 2026', 'this year'"),
            "limit": .init(type: "integer", description: "Max results to return (default 8, max 20)")
        ],
        required: ["query"]
    )
)
```

**Execution**: Locally via `SearchService`. Returns `[{ block_id, excerpt, breadcrumb, created_at, updated_at }]`.

#### Tool 2: `get_block_context` — navigate the block tree around a target

The AI controls how much context it needs — it can look up (ancestors), down (descendants), and sideways (siblings) from the target block.

```swift
ToolDefinition(
    name: "get_block_context",
    description: """
        Fetch the full content and surrounding context of specific blocks.
        Use this after search_notes when you need to see the full text, parent hierarchy,
        children, or sibling blocks around a result.
        You control how many levels up (ancestors) and down (descendants) to fetch,
        and whether to include siblings at the target's level.
        """,
    input_schema: ToolInputSchema(
        type: "object",
        properties: [
            "block_ids": .init(type: "array", items: .init(type: "string"),
                description: "Array of block UUIDs to fetch context for"),
            "levels_up": .init(type: "integer",
                description: "How many ancestor levels to include (0 = none, 1 = parent, 2 = grandparent, etc.). Default 1."),
            "levels_down": .init(type: "integer",
                description: "How many descendant levels to include (0 = none, 1 = direct children, 2 = children + grandchildren, etc.). Default 0."),
            "include_siblings": .init(type: "boolean",
                description: "Whether to include sibling blocks at the same level as the target. Default false."),
            "max_siblings": .init(type: "integer",
                description: "Max sibling blocks to include above and below the target (default 3). Only used if include_siblings is true.")
        ],
        required: ["block_ids"]
    )
)
```

**Execution**: Locally via ModelContext fetch. For each block ID:

```swift
func fetchBlockContext(
    blockId: UUID, levelsUp: Int, levelsDown: Int,
    includeSiblings: Bool, maxSiblings: Int
) -> BlockContext {
    let block = fetchBlock(id: blockId)

    // 1. Walk UP the parent chain (ancestors)
    var ancestors: [AncestorBlock] = []
    var current = block.parent
    var remaining = levelsUp
    while let parent = current, remaining > 0 {
        ancestors.insert(AncestorBlock(blockId: parent.id, content: parent.content, depth: parent.depth), at: 0)
        current = parent.parent
        remaining -= 1
    }

    // 2. Walk DOWN the children tree (descendants)
    var descendants: [DescendantBlock] = []
    if levelsDown > 0 {
        collectDescendants(of: block, currentLevel: 1, maxLevel: levelsDown, into: &descendants)
    }

    // 3. Collect SIBLINGS at the same level
    var siblingsBefore: [SiblingBlock] = []
    var siblingsAfter: [SiblingBlock] = []
    if includeSiblings, let parent = block.parent {
        let sorted = parent.sortedChildren.filter { !$0.isArchived }
        if let idx = sorted.firstIndex(where: { $0.id == blockId }) {
            let beforeStart = max(0, idx - maxSiblings)
            siblingsBefore = sorted[beforeStart..<idx].map { SiblingBlock(blockId: $0.id, content: $0.content) }
            let afterEnd = min(sorted.count, idx + 1 + maxSiblings)
            siblingsAfter = sorted[(idx + 1)..<afterEnd].map { SiblingBlock(blockId: $0.id, content: $0.content) }
        }
    }

    return BlockContext(
        blockId: block.id,
        content: block.content,
        breadcrumb: buildBreadcrumb(for: block),
        depth: block.depth,
        createdAt: block.createdAt,
        updatedAt: block.updatedAt,
        ancestors: ancestors,
        descendants: descendants,
        siblingsBefore: siblingsBefore,
        siblingsAfter: siblingsAfter
    )
}

func collectDescendants(of block: Block, currentLevel: Int, maxLevel: Int, into result: inout [DescendantBlock]) {
    for child in block.sortedChildren where !child.isArchived {
        result.append(DescendantBlock(blockId: child.id, content: child.content, depth: child.depth))
        if currentLevel < maxLevel {
            collectDescendants(of: child, currentLevel: currentLevel + 1, maxLevel: maxLevel, into: &result)
        }
    }
}
```

**Return type:**

```swift
struct BlockContext: Codable {
    let blockId: UUID
    let content: String              // full content, not truncated
    let breadcrumb: String           // "Today's Notes / 2026 / March / Mar 6"
    let depth: Int
    let createdAt: Date
    let updatedAt: Date
    let ancestors: [AncestorBlock]   // parent chain going up (ordered root-first)
    let descendants: [DescendantBlock]  // children tree going down (ordered by sortOrder)
    let siblingsBefore: [SiblingBlock]  // blocks above at same level
    let siblingsAfter: [SiblingBlock]   // blocks below at same level
}

struct AncestorBlock: Codable {
    let blockId: UUID
    let content: String
    let depth: Int
}

struct DescendantBlock: Codable {
    let blockId: UUID
    let content: String
    let depth: Int
}

struct SiblingBlock: Codable {
    let blockId: UUID
    let content: String
}
```

**Example calls the AI might make:**

| User request                          | AI's get_block_context call                                                                    |
| ------------------------------------- | ---------------------------------------------------------------------------------------------- |
| "Tell me more about this note"        | `levels_up: 2, levels_down: 1` — see parent context + children                                 |
| "Summarize what's under this section" | `levels_up: 0, levels_down: 3` — deep-dive into descendants                                    |
| "What else did I write around this?"  | `include_siblings: true, max_siblings: 5` — see surrounding blocks                             |
| "Add something after this bullet"     | `levels_up: 1, include_siblings: true` — need parent ID + sibling positions for `suggest_edit` |

#### Tool 3: `suggest_edit` — propose changes to user's notes

```swift
ToolDefinition(
    name: "suggest_edit",
    description: """
        Propose additions or changes to the user's notes. These will be shown
        as a visual diff for the user to review and accept or dismiss.
        NEVER use this without first searching for relevant notes.
        Only call this when the user explicitly asks for edits, additions, or rewrites.
        """,
    input_schema: ToolInputSchema(
        type: "object",
        properties: [
            "description": .init(type: "string",
                description: "Brief human-readable description of what this edit does"),
            "operations": .init(type: "array", items: .init(
                type: "object",
                properties: [
                    "type": .init(type: "string", enum: ["add_block", "update_block"],
                        description: "Operation type"),
                    "parent_id": .init(type: "string",
                        description: "UUID of parent block (required for add_block)"),
                    "after_block_id": .init(type: "string",
                        description: "UUID of sibling to insert after (optional for add_block, omit to append)"),
                    "content": .init(type: "string",
                        description: "New block content (required for add_block)"),
                    "block_id": .init(type: "string",
                        description: "UUID of block to update (required for update_block)"),
                    "new_content": .init(type: "string",
                        description: "Replacement content (required for update_block)")
                ]
            ), description: "Array of edit operations to propose")
        ],
        required: ["description", "operations"]
    )
)
```

**Execution**: NOT executed. The tool call input is captured and persisted as a `SuggestedEdit` block with `status: .pending`. The UI renders it as a diff card for user review.

### How tools interact in a typical flow

```
User: "what was I thinking about self-growth this year?"

→ Claude calls search_notes(query: "self-growth", date_hint: "this year")
← App returns [{ blockId: ..., excerpt: "I want to focus on...", breadcrumb: "Today / Jan 15" }, ...]
→ Claude responds with text referencing the results (no further tool calls)

User: "can you expand on that second point and add it to today's note?"

→ Claude calls get_block_context(block_ids: ["uuid-of-second-result"])
← App returns { content: "I want to focus on being more present...", siblings: [...] }
→ Claude calls suggest_edit(description: "Add expanded reflection under today", operations: [{
    type: "add_block", parent_id: "uuid-of-today", after_block_id: "uuid-of-last-child",
    content: "Building on earlier thoughts about presence..."
  }])
← App captures proposal, persists as SuggestedEdit block, renders diff card
→ Claude responds: "I've suggested adding an expanded reflection. You can review it above."
```

### Codable types for tool definitions

```swift
struct ToolDefinition: Encodable {
    let name: String
    let description: String
    let input_schema: ToolInputSchema
}

struct ToolInputSchema: Encodable {
    let type: String
    let properties: [String: PropertySchema]?
    let items: PropertySchema?       // for array types
    let required: [String]?
    let `enum`: [String]?            // for string enums
}

struct PropertySchema: Encodable {
    let type: String
    let description: String?
    let items: PropertySchema?       // for nested arrays
    let properties: [String: PropertySchema]?  // for nested objects
    let `enum`: [String]?
}
```

### ToolExecutor protocol (NotoClaudeAPI)

Generic protocol that decouples the tool loop from any specific tool implementation. Lives in `NotoClaudeAPI` alongside `ChatLoop`.

```swift
// Lives in NotoClaudeAPI package
public struct ToolResult {
    public let toolUseId: String
    public let content: String
    public let isError: Bool

    public init(toolUseId: String, content: String, isError: Bool = false) {
        self.toolUseId = toolUseId
        self.content = content
        self.isError = isError
    }
}

public protocol ToolExecutor {
    /// Execute a tool call and return the result string.
    /// The executor decides how to handle each tool name.
    func execute(toolUseId: String, name: String, input: JSONValue) async throws -> ToolResult
}
```

### ChatLoop (NotoClaudeAPI) — generic capped tool loop

The loop is Noto-agnostic. It takes a `ClaudeAPIClient`, a `ToolExecutor`, tool definitions, and a max iteration cap. Any app can reuse this with its own tools.

```swift
// Lives in NotoClaudeAPI package
public struct ChatLoopConfig {
    public var model: String = "claude-sonnet-4-6"
    public var maxTokens: Int = 4096
    public var maxToolIterations: Int = 5

    public init(model: String = "claude-sonnet-4-6", maxTokens: Int = 4096, maxToolIterations: Int = 5) {
        self.model = model
        self.maxTokens = maxTokens
        self.maxToolIterations = maxToolIterations
    }
}

public struct ChatLoopResult {
    public let text: String
    public let toolCallHistory: [ToolCallRecord]  // all tool calls made across iterations
}

public struct ToolCallRecord {
    public let name: String
    public let input: JSONValue
    public let output: String
}

public struct ChatLoop {
    let client: ClaudeAPIClient
    let config: ChatLoopConfig

    public init(client: ClaudeAPIClient, config: ChatLoopConfig = .init()) {
        self.client = client
        self.config = config
    }

    public func run(
        system: String,
        messages: [Message],
        tools: [ToolDefinition],
        executor: ToolExecutor
    ) async throws -> ChatLoopResult {
        var messages = messages
        var toolCallHistory: [ToolCallRecord] = []
        var iteration = 0

        while iteration < config.maxToolIterations {
            let request = MessagesRequest(
                model: config.model,
                max_tokens: config.maxTokens,
                system: system,
                messages: messages,
                tools: tools
            )

            let response = try await client.sendMessage(request)

            // Model is done — return text
            if response.stop_reason == "end_turn" {
                let text = extractText(from: response.content)
                return ChatLoopResult(text: text, toolCallHistory: toolCallHistory)
            }

            guard response.stop_reason == "tool_use" else {
                throw ChatLoopError.unexpectedStopReason(response.stop_reason)
            }

            // Execute all tool calls in this iteration
            let toolCalls = extractToolUses(from: response.content)
            var toolResults: [ToolResultBlock] = []

            for toolCall in toolCalls {
                let result = try await executor.execute(
                    toolUseId: toolCall.id, name: toolCall.name, input: toolCall.input
                )
                toolResults.append(ToolResultBlock(
                    type: "tool_result",
                    tool_use_id: result.toolUseId,
                    content: result.content,
                    is_error: result.isError
                ))
                toolCallHistory.append(ToolCallRecord(
                    name: toolCall.name, input: toolCall.input, output: result.content
                ))
            }

            messages.append(Message(role: "assistant", content: .blocks(response.content)))
            messages.append(Message(role: "user", content: .blocks(toolResults.map { .toolResult($0) })))
            iteration += 1
        }

        // Hit max iterations — final call without tools to force text response
        let finalRequest = MessagesRequest(
            model: config.model,
            max_tokens: config.maxTokens,
            system: system,
            messages: messages,
            tools: nil
        )
        let finalResponse = try await client.sendMessage(finalRequest)
        let text = extractText(from: finalResponse.content)
        return ChatLoopResult(text: text, toolCallHistory: toolCallHistory)
    }
}
```

### NotoToolExecutor (NotoAIChat) — Noto-specific tool implementation

Conforms to `ToolExecutor` from `NotoClaudeAPI`. Contains all Noto-specific logic for search, block context, and edit proposals.

```swift
// Lives in NotoAIChat package
import NotoClaudeAPI
import NotoSearch
import NotoModels
import NotoCore

public class NotoToolExecutor: ToolExecutor {
    let searchService: SearchService
    let modelContext: ModelContext

    // Accumulated state across iterations
    public private(set) var references: [BlockReference] = []
    public private(set) var editProposal: EditProposal? = nil

    public init(searchService: SearchService, modelContext: ModelContext) {
        self.searchService = searchService
        self.modelContext = modelContext
    }

    public func execute(toolUseId: String, name: String, input: JSONValue) async throws -> ToolResult {
        switch name {
        case "search_notes":
            let params = try decode(SearchNotesInput.self, from: input)
            let results = try await searchService.search(
                query: params.query, dateHint: params.dateHint, limit: params.limit ?? 8
            )
            let newRefs = results.map { BlockReference(from: $0) }
            references.append(contentsOf: newRefs)
            return ToolResult(toolUseId: toolUseId, content: try encode(newRefs))

        case "get_block_context":
            let params = try decode(GetBlockContextInput.self, from: input)
            let contexts = try params.blockIds.map { blockId in
                try fetchBlockContext(
                    blockId: blockId,
                    levelsUp: params.levelsUp,
                    levelsDown: params.levelsDown,
                    includeSiblings: params.includeSiblings,
                    maxSiblings: params.maxSiblings
                )
            }
            return ToolResult(toolUseId: toolUseId, content: try encode(contexts))

        case "suggest_edit":
            let params = try decode(SuggestEditInput.self, from: input)
            editProposal = EditProposal(
                description: params.description,
                operations: params.operations
            )
            return ToolResult(
                toolUseId: toolUseId,
                content: "Edit proposal captured. It will be shown to the user for review."
            )

        default:
            return ToolResult(toolUseId: toolUseId, content: "Unknown tool: \(name)", isError: true)
        }
    }
}
```

### AIChatService (NotoAIChat) — ties it together

Thin orchestrator that creates a `ChatLoop` + `NotoToolExecutor` and returns a `ChatResult`.

```swift
// Lives in NotoAIChat package
public struct AIChatService {
    let chatLoop: ChatLoop
    let searchService: SearchService
    let modelContext: ModelContext

    public init(apiKey: String, searchService: SearchService, modelContext: ModelContext, config: ChatLoopConfig = .init()) {
        let client = ClaudeAPIClient(apiKey: apiKey)
        self.chatLoop = ChatLoop(client: client, config: config)
        self.searchService = searchService
        self.modelContext = modelContext
    }

    public func chat(userMessage: String, history: [Message], noteContext: NoteContext?) async throws -> ChatResult {
        let executor = NotoToolExecutor(searchService: searchService, modelContext: modelContext)
        let system = buildSystemPrompt(noteContext: noteContext)
        let messages = history + [Message(role: "user", content: .text(userMessage))]

        let result = try await chatLoop.run(
            system: system,
            messages: messages,
            tools: NotoToolDefinitions.all,
            executor: executor
        )

        return ChatResult(
            text: result.text,
            references: executor.references,
            editProposal: executor.editProposal,
            toolCallHistory: result.toolCallHistory
        )
    }
}
```

````

### Decodable input types

```swift
struct SearchNotesInput: Decodable {
    let query: String
    let date_hint: String?
    let limit: Int?
    var dateHint: String? { date_hint }
}

struct GetBlockContextInput: Decodable {
    let block_ids: [String]
    let levels_up: Int?
    let levels_down: Int?
    let include_siblings: Bool?
    let max_siblings: Int?
    var blockIds: [UUID] { block_ids.compactMap { UUID(uuidString: $0) } }
    var levelsUp: Int { levels_up ?? 1 }
    var levelsDown: Int { levels_down ?? 0 }
    var includeSiblings: Bool { include_siblings ?? false }
    var maxSiblings: Int { max_siblings ?? 3 }
}

struct SuggestEditInput: Decodable {
    let description: String
    let operations: [EditOperation]
}

struct ChatResult {
    let text: String
    let references: [BlockReference]
    let editProposal: EditProposal?
}
````

### Why this approach

- **No third-party SDK**: Pure URLSession + Codable. Zero external dependencies.
- **Capped loop, not unbounded**: `maxToolIterations` (default 5) prevents runaway calls. Typical flows use 1-3 iterations. If the cap is hit, a final call without tools forces a text response.
- **Three focused tools**: `search_notes` for discovery, `get_block_context` for deep-dive, `suggest_edit` for proposals. Claude chains them as needed (search → context → edit).
- **Local execution**: `search_notes` and `get_block_context` execute in-process. `suggest_edit` is captured but not executed — user must accept.
- **Simple states**: ViewModel is `.idle` -> `.loading` -> `.streaming` -> `.complete`. The loop runs inside `.loading` — the UI doesn't need to know how many iterations happened.

---

## Changes from Initial Brainstorm

### 1. Three tools instead of two

The initial brainstorm had `search_blocks` and `get_block_context`. We now have three: `search_notes` (discovery), `get_block_context` (deep-dive with ancestors, descendants, and siblings), and `suggest_edit` (structured edit proposal as a tool call, not prompt-parsed JSON).

### 2. Edit proposals are a tool, not prompt-parsed JSON

Cleaner than parsing trailing JSON from response text. The `suggest_edit` tool call gives us structured, validated input. The tool is "captured" (persisted as SuggestedEdit block) but never executed — user must accept.

### 3. Design for streaming from day one

The Figma shows a complete response, but in practice:

- Reference block appears first (search completes)
- Then the answer streams in token by token
- Then the suggested edit card appears at the end (if any)

The ViewModel needs to handle partial/incremental state from the start.

---

## Implementation Plan — Parallelized Work Streams

### Dependency graph

```
                    ┌─────────────────┐
                    │  Nothing needed  │
                    └────────┬────────┘
          ┌─────────────┬────┴────┬──────────────┬──────────────┐
          v             v         v              v              v
     [WS-A]        [WS-B]    [WS-C]         [WS-D]         [WS-E]
  NotoClaudeAPI   BlockBuilder  Chat DTOs   DateFilter    Chat UI Shell
  (Foundation)    extensions    (Codable)    Parser ext    (static/mock)
          │         (NotoCore)  (NotoAIChat)                    │
          │             │         │                             │
          │             │         v                             │
          │             │    [WS-F]                             │
          │             │    AIChatBlockStore                   │
          │             │    + AI Chat root                     │
          │             │    + DirtyTracker wiring              │
          │             │         │                             │
          v             │         v                             │
     [WS-G]             │    [WS-H]                            │
  NotoToolExecutor      │    Tool implementations              │
  + NotoToolDefs        │    (search, context, suggest)        │
  + AIChatService       │         │                            │
          │             │         │                            │
          └──────┬──────┘─────────┘────────────────────────────┘
                 v
            [WS-I]
         Integration: ViewModel + live UI + tool loop + persistence
                 │
                 v
            [WS-J]
         Edit apply flow: AIEditApplier + accept/dismiss + diff card
                 │
                 v
            [WS-K]
         Polish: streaming UX, error states, edge cases
```

### Work streams detail

---

#### WS-A: `NotoClaudeAPI` package (Foundation only — no Noto deps)
**Can start immediately. No blockers.**

- `ClaudeAPIClient` — URLSession wrapper, `sendMessage(_:)` method
- Codable types: `MessagesRequest`, `MessagesResponse`, `ContentBlock`, `ToolUseBlock`, `ToolResultBlock`, `MessageContent`
- `ToolDefinition`, `ToolInputSchema`, `PropertySchema` — tool schema types
- `ToolExecutor` protocol + `ToolResult` type
- `ChatLoop` — capped `while` loop with `maxToolIterations`, `ChatLoopConfig`, `ChatLoopResult`
- `ChatLoopError` enum
- Tests: mock executor, verify loop terminates at cap, correct message threading, end_turn vs tool_use branching

**Output**: A standalone, tested package that any Swift project could use.

---

#### WS-B: `BlockBuilder` extensions in NotoCore
**Can start immediately. No blockers.**

- `BlockBuilder.addBlock(content:parent:afterSibling:extensionData:context:)` → returns new Block
- `BlockBuilder.updateBlock(_:newContent:)` → throws `BlockBuilderError.notEditable`
- `BlockBuilder.archiveBlock(_:)` → throws `BlockBuilderError.notDeletable`
- `BlockBuilderError` enum
- Tests: add between siblings (sortOrder), add at end, update with permission check, archive with permission check, protected block rejection

**Output**: Reusable block mutation API in NotoCore, used by AI edits and future features.

---

#### WS-C: Chat block extension DTOs (`NotoAIChat` models only)
**Can start immediately. No blockers.** (Just Codable structs depending on NotoModels)

- `ChatBlockRole` enum (`.conversation`, `.userMessage`, `.aiResponse`, `.suggestedEdit`)
- `ConversationExtension`, `UserMessageExtension`, `AIResponseExtension`, `SuggestedEditExtension` Codable structs
- `BlockReference`, `ToolCallRecord`, `EditProposal`, `EditOperation`, `EditStatus` types
- Helper to encode/decode `extensionData` ↔ extension types
- MetadataField key constants (`noto.ai.role`, `noto.ai.status`, `noto.ai.turnIndex`)
- Tests: encode/decode round-trips for all types

**Output**: All the data types that the rest of NotoAIChat depends on.

---

#### WS-D: `DateFilterParser` extension
**Can start immediately. No blockers.**

- Add `this year` / `last year` patterns to existing parser
- Tests: verify "what I wrote this year" and "last year's goals" produce correct date ranges

**Output**: Small, isolated change in NotoSearch. Merged early.

---

#### WS-E: Chat UI shell (static, mock data)
**Can start immediately. No blockers.** (Uses hardcoded mock data, no real services)

- `AIChatSheet` SwiftUI view — sheet chrome (grabber, title, close button)
- `ChatMessageRow` — user bubble (right-aligned) and AI response (left-aligned)
- `ReferencesSection` — "Found N notes" + expandable bullet list
- `SuggestedEditCard` — green-bordered diff view with context/addition lines + Dismiss/Accept buttons
- `ChatComposerBar` — text field + send button, pinned to bottom
- Loading/typing indicator view
- Route: "Ask AI" button in SearchSheet → presents `AIChatSheet`
- All rendering from hardcoded mock data (no ViewModel, no services)
- UI tests: sheet presentation, all row types render, composer interaction

**Output**: Pixel-accurate chat UI against Figma, ready to be wired to real data.

---

#### WS-F: `AIChatBlockStore` + AI Chat root + DirtyTracker wiring
**Depends on: WS-C** (needs chat DTOs)

- `AIChatRootService.ensureRoot(context:)` — protected "AI Chat" root block (mirrors TodayNotesService pattern)
- `AIChatBlockStore` — CRUD for conversation block trees:
  - `createConversation(noteContext:context:)` → conversation root block under AI Chat root
  - `addUserMessage(content:to:context:)` → user message block
  - `addAIResponse(text:references:toolCalls:to:context:)` → AI response block + BlockLinks
  - `addSuggestedEdit(proposal:parentResponseId:to:context:)` → suggested edit block
  - `updateEditStatus(_:status:context:)` → accept/dismiss
  - `fetchConversations(context:)` → list all conversations
  - `fetchMessages(for:context:)` → sorted children of a conversation
- DirtyTracker integration: `markDirty` on every new block, `flush` after each turn
- Tests: create conversation, add turns, verify block tree structure, verify dirty tracking

**Output**: Persistence layer for chat conversations as blocks.

---

#### WS-G: `NotoToolExecutor` + `NotoToolDefinitions` + `AIChatService`
**Depends on: WS-A** (needs `ToolExecutor` protocol and `ChatLoop`)

- `NotoToolDefinitions` — three tool schemas (`search_notes`, `get_block_context`, `suggest_edit`)
- `NotoToolExecutor` — conforms to `ToolExecutor`, dispatches by tool name
  - `search_notes` → calls `SearchService`
  - `get_block_context` → fetches block + ancestors/descendants/siblings from ModelContext
  - `suggest_edit` → captures proposal, returns acknowledgment
- `AIChatService` — thin orchestrator: creates `ChatLoop` + `NotoToolExecutor`, returns `ChatResult`
- System prompt builder (`buildSystemPrompt(noteContext:)`)
- Tests: mock SearchService, verify tool dispatch, verify ChatResult assembly

**Output**: Service layer that connects Claude API to local Noto data.

---

#### WS-H: Tool implementations (search, context, suggest)
**Depends on: WS-G** (needs executor scaffold) + existing NotoSearch

- `search_notes` implementation: wire `SearchNotesInput` → `SearchService.search()` → `[BlockReference]`
- `get_block_context` implementation: fetch block, walk ancestors (N levels up), collect descendants (N levels down), collect siblings
- `suggest_edit` implementation: decode `SuggestEditInput`, store as `EditProposal`, return confirmation
- Integration tests: real in-memory FTS5/HNSW index, verify search results flow through tool executor

**Output**: Working local tool execution for all three tools.

---

#### WS-I: Integration — ViewModel + live UI + tool loop + persistence
**Depends on: WS-E (UI), WS-F (persistence), WS-G (service), WS-H (tools)**

This is the "wire everything together" step:

- `AIChatViewModel` — state machine (`.idle` → `.loading` → `.streaming` → `.complete` → `.error`)
  - `sendMessage(_:)` → persist user message block → call `AIChatService.chat()` → persist AI response block → update UI state
  - Holds conversation root block reference
  - Exposes messages as `[ChatMessage]` for the UI to render
- Replace mock data in `AIChatSheet` with ViewModel-driven rendering
- Wire SearchSheet "Ask AI" → AIChatSheet with real services
- Test: end-to-end flow with mock API client but real SearchService + real block persistence

**Output**: Functional chat that searches notes and responds. No edit apply yet.

---

#### WS-J: Edit apply flow
**Depends on: WS-B (BlockBuilder extensions), WS-I (integrated chat)**

- `AIEditApplier` in NotoAIChat:
  - Validate all block IDs exist
  - Check staleness (`block.updatedAt <= proposalCreatedAt`)
  - Delegate to `BlockBuilder.addBlock` / `.updateBlock` / `.archiveBlock`
  - `dirtyTracker.markDirty()` after each mutation
  - All-or-nothing transaction semantics
- Wire Accept button → `AIEditApplier.apply()` → update SuggestedEdit block status → reload OutlineView
- Wire Dismiss button → update status only
- Diff card rendering from real proposal data (context lines + green additions)
- Tests: apply add/update, staleness rejection, permission rejection, OutlineView refresh after accept

**Output**: Complete edit proposal flow — suggest, preview, accept/dismiss, apply.

---

#### WS-K: Polish
**Depends on: WS-I, WS-J**

- Streaming UX: typing indicator, progressive token rendering
- Error states: network failure, API rate limit, malformed response → retry UX
- Long content: truncation for references, scroll behavior for long conversations
- Conversation list/history browsing
- Edge cases: stale proposals, concurrent edits, conversation while note is being edited
- Latency and token-budget tuning
- Dark mode verification
- Accessibility: VoiceOver ordering, button labels

---

### Parallelism summary

```
Time →

WS-A  ████████░░░░░░░░░░░░░░░░░░░░░░░░░
WS-B  ████████░░░░░░░░░░░░░░░░░░░░░░░░░
WS-C  ██████░░░░░░░░░░░░░░░░░░░░░░░░░░░
WS-D  ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
WS-E  ████████████░░░░░░░░░░░░░░░░░░░░░
WS-F  ░░░░░░████████░░░░░░░░░░░░░░░░░░░  (waits for WS-C)
WS-G  ░░░░░░░░████████░░░░░░░░░░░░░░░░░  (waits for WS-A)
WS-H  ░░░░░░░░░░░░████████░░░░░░░░░░░░░  (waits for WS-G)
WS-I  ░░░░░░░░░░░░░░░░████████░░░░░░░░░  (waits for E,F,G,H)
WS-J  ░░░░░░░░░░░░░░░░░░░░████████░░░░░  (waits for B,I)
WS-K  ░░░░░░░░░░░░░░░░░░░░░░░░░░░██████  (waits for I,J)

Parallel lanes at peak: 5 (A, B, C, D, E all run simultaneously)
```

### Critical path

The longest dependency chain determines minimum time:

```
WS-A (ClaudeAPI) → WS-G (executor/service) → WS-H (tool impls) → WS-I (integration) → WS-J (edit apply) → WS-K (polish)
```

To minimize total time, **prioritize WS-A** — it gates the most downstream work. WS-B, C, D, E can all run alongside it but don't block as much.

---

## Testing Strategy

### Layer 1: Package unit tests (`swift test`, no simulator)

Run via `cd Packages/NotoAIChat && swift test`. Fast, CI-friendly, no Xcode needed.

| Area                            | What to test                                                                             | Approach                                                                         |
| ------------------------------- | ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| **ChatBlockRole serialization** | `extensionData` encode/decode round-trips for all roles                                  | Create Codable structs, encode to Data, decode back, assert equality             |
| **MetadataField helpers**       | Read/write `noto.ai.role`, `noto.ai.status` etc.                                         | Helper functions that wrap MetadataField creation/query                          |
| **Tool schema validation**      | `search_notes` and `propose_edits` input/output parsing                                  | Feed valid + malformed JSON, assert correct parse or error                       |
| **Edit proposal validation**    | Block ID existence, operation type checks, staleness detection                           | Mock block store with known IDs + timestamps, feed proposals                     |
| **AIEditApplier logic**         | `add_block` inserts at correct position, `update_block` changes content                  | In-memory ModelContainer, apply operations, assert block tree state              |
| **Prompt assembly**             | System prompt includes note context, conversation history is formatted correctly         | Assert string contains expected sections, tool definitions are valid JSON        |
| **Tool call flow**              | With tool use: 2 API calls. Without: 1 API call. Both paths produce correct final state. | Mock API client that returns canned responses (with and without tool_use blocks) |

#### Mock/stub strategy for package tests

- `MockClaudeAPIClient`: Returns canned `MessagesResponse` structs (text blocks, tool_use blocks, stop reasons)
- `MockSearchService`: Returns fixed `[SearchResult]` for given queries
- `MockBlockStore`: In-memory block tree for testing persistence logic without SwiftData

### Layer 2: Integration tests (`swift test`, cross-package)

Test that `NotoAIChat` correctly calls into `NotoSearch` and `NotoModels`.

| Area                                  | What to test                                                                                              |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| **Tool execution -> SearchService**   | `NotoToolExecutor.execute("search_notes", ...)` returns results from a real (in-memory) FTS5 + HNSW index |
| **Block persistence round-trip**      | Write a conversation tree via `AIChatBlockStore`, read it back, verify structure and metadata             |
| **Edit apply -> Block tree mutation** | Apply an `add_block` proposal, verify the target note's block tree is correctly modified                  |
| **DirtyTracker integration**          | After applying edits, verify dirty blocks are flagged for reindexing                                      |

### Layer 3: App-level unit tests (`xcodebuild test -only-testing:NotoTests`)

Tests that require the app's ModelContainer or ViewModel layer. Run on session simulator.

| Area                                      | What to test                                                                                |
| ----------------------------------------- | ------------------------------------------------------------------------------------------- |
| **AIChatViewModel state transitions**     | Send message -> `.loading` -> `.streaming` -> `.complete` (with and without tool call path) |
| **Conversation block tree persistence**   | ViewModel persists turns correctly in SwiftData, survives fetch cycle                       |
| **Accept/Dismiss flow**                   | Tap Accept -> `AIEditApplier` runs -> status changes to `.accepted` -> target note updated  |
| **Error states**                          | Network failure -> `.error(message)` state -> retry available                               |
| **Filtering chat blocks from note views** | Chat blocks don't appear in normal note queries                                             |

### Layer 4: UI tests (`xcodebuild test -only-testing:NotoUITests`)

Visual + interaction tests on session simulator. Use `-UITesting` launch argument for in-memory container.

| Area                    | What to test                                                                              |
| ----------------------- | ----------------------------------------------------------------------------------------- |
| **Sheet presentation**  | Tap "Ask AI" in SearchSheet -> AI Chat sheet slides up with grabber + title               |
| **Message rendering**   | User bubble right-aligned, AI response left-aligned with correct styling                  |
| **References section**  | "Found N notes" header appears, reference rows are tappable                               |
| **Suggested edit card** | Green border, context lines, addition lines with `+`, Dismiss/Accept buttons              |
| **Accept flow**         | Tap Accept -> card updates to show accepted state -> dismiss sheet -> verify edit in note |
| **Dismiss flow**        | Tap Dismiss -> card updates to show dismissed state                                       |
| **Composer**            | Text field accepts input, send button enabled when non-empty, keyboard behavior           |
| **Scrolling**           | Long conversations scroll correctly, composer stays pinned at bottom                      |

### Layer 5: Manual verification (required for UI/UX tasks)

Per CLAUDE.md convention, always invoke `/flowdeck` after UI changes to visually verify on simulator.

| Check                    | Details                                                                                    |
| ------------------------ | ------------------------------------------------------------------------------------------ |
| **Figma fidelity**       | Compare sheet layout, spacing, colors, typography against Figma frame `26:1972`            |
| **Dark mode**            | Verify all chat elements render correctly in dark appearance                               |
| **Keyboard interaction** | Composer rises with keyboard, sheet scrolls to keep latest message visible                 |
| **Long content**         | Very long AI responses, many references, long edit proposals scroll and truncate correctly |
| **Accessibility**        | VoiceOver reads chat messages in order, buttons are labeled                                |

### Test data strategy

- **Seed data for UI tests**: `AIChatTestHelpers` creates a conversation root with canned user/AI turns, references, and a pending suggested edit
- **Seed data for integration tests**: Pre-populated in-memory SwiftData container with known notes to search against
- **Mock API responses**: JSON fixtures in test bundle matching Claude Messages API format (text blocks, tool_use blocks, streaming deltas)

---

## Key Architecture Diagram

```
User taps "Ask AI" in SearchSheet
        |
        v
  AIChatSheet (app target, SwiftUI)
        |
        v
  AIChatViewModel (app target)
        |
        v
  AIChatService (NotoAIChat package)
    |              |
    v              v
  Claude API     search_notes (local tool call)
  (1-2 calls)      |
                    v
                SearchService (NotoSearch package)
                |         |
                v         v
            NotoFTS5   NotoHNSW
                        |
                        v
                    NotoEmbedding (on-device CoreML)
```

On "Accept" edit:

```
AIChatViewModel -> AIEditApplier (NotoAIChat)
                      |
                      v
                  Block model ops (NotoModels/NotoCore)
                      |
                      v
                  DirtyTracker -> reindex
```

---

## How `propose_edits` Maps to Block Operations

This section traces how an AI-proposed edit flows from the tool call through validation and into actual Block mutations, using existing `Block` model operations and `BlockBuilder`.

### End-to-end flow

```
1. AI calls propose_edits tool
       |
2. AIChatService captures proposal JSON (does NOT execute)
       |
3. Proposal persisted as SuggestedEdit block (status: .pending)
       |
4. UI renders diff card from proposal
       |
5. User taps "Accept"
       |
6. AIEditApplier.apply(proposal, modelContext, dirtyTracker)
       |  a. Validate all block IDs exist
       |  b. Check permissions on each target block
       |  c. Check staleness (block.updatedAt vs proposal.createdAt)
       |  d. Execute operations in order
       |  e. Mark dirty for reindexing
       |  f. Update SuggestedEdit block status -> .accepted
       |
7. OutlineView picks up SwiftData changes on next appearance
```

### BlockBuilder extension — generic block operations in NotoCore

Instead of implementing add/update/archive logic inside `AIEditApplier`, extend `BlockBuilder` in `NotoCore` with generic reusable operations. These are not AI-specific — any feature (templates, automation, import, bulk edits) can use them.

**Current `BlockBuilder` API:**

- `buildPath(root:path:context:)` — find-or-create blocks along a hierarchy

**Proposed additions:**

```swift
// All in BlockBuilder (NotoCore package)
extension BlockBuilder {

    /// Insert a new block as a child of `parent`, positioned after `afterSibling`.
    /// If `afterSibling` is nil, appends to end.
    /// Returns the newly created block.
    @MainActor
    public static func addBlock(
        content: String,
        parent: Block,
        afterSibling: Block? = nil,
        extensionData: Data? = nil,
        context: ModelContext
    ) -> Block

    /// Update a block's content. Checks `isContentEditableByUser` permission.
    /// Throws `BlockBuilderError.notEditable` if the block is protected.
    @MainActor
    public static func updateBlock(
        _ block: Block,
        newContent: String
    ) throws

    /// Soft-delete a block by setting `isArchived = true`. Checks `isDeletable` permission.
    /// Throws `BlockBuilderError.notDeletable` if the block is protected.
    @MainActor
    public static func archiveBlock(
        _ block: Block
    ) throws
}

enum BlockBuilderError: Error {
    case notEditable(UUID)
    case notDeletable(UUID)
}
```

**Key implementation details:**

- `addBlock` uses `Block.sortOrderBetween(_:_:)` for fractional index positioning — no sibling rewrite needed
- `addBlock` computes depth from parent automatically via `Block.init(parent:)`
- `updateBlock` calls `block.updateContent(newContent)` which handles both `content` and `updatedAt`
- `archiveBlock` sets `isArchived = true` (soft delete, reversible)
- All operations respect existing protection flags (`isContentEditableByUser`, `isDeletable`)
- Callers are responsible for `dirtyTracker.markDirty()` / `markDeleted()` — BlockBuilder doesn't own the tracker

**Who uses these:**

- `AIEditApplier` (NotoAIChat) — applies accepted edit proposals by calling `BlockBuilder.addBlock` / `.updateBlock` / `.archiveBlock`
- Future: templates, bulk import, automation, share extension
- Existing `buildPath` stays unchanged — it's a higher-level operation that uses find-or-create semantics

**What `AIEditApplier` becomes:**
A thin validation + orchestration layer that:

1. Validates all block IDs exist
2. Checks staleness (`block.updatedAt <= proposalCreatedAt`)
3. Delegates to `BlockBuilder.addBlock` / `.updateBlock` / `.archiveBlock`
4. Calls `dirtyTracker.markDirty()` after each mutation
5. Handles all-or-nothing transaction semantics (validate all, then execute all)

---

### Operation: `add_block`

**Input from AI:**

```json
{
  "type": "add_block",
  "parent_id": "UUID-of-parent",
  "after_block_id": "UUID-of-sibling-or-null",
  "content": "today is a lovely day because it is very good"
}
```

**Execution in AIEditApplier (pseudocode):**

```swift
func applyAddBlock(op: AddBlockOp, context: ModelContext, dirtyTracker: DirtyTracker) throws {
    // 1. Fetch parent block
    let parent = try fetchBlock(id: op.parentId, context: context)

    // 2. Calculate sort order
    let sortOrder: Double
    if let afterId = op.afterBlockId {
        // Insert after a specific sibling
        let afterBlock = try fetchBlock(id: afterId, context: context)
        let siblings = parent.sortedChildren.filter { !$0.isArchived }
        let afterIndex = siblings.firstIndex(where: { $0.id == afterId })
        let nextBlock = afterIndex.map { idx in
            idx + 1 < siblings.count ? siblings[idx + 1] : nil
        } ?? nil
        sortOrder = Block.sortOrderBetween(afterBlock.sortOrder, nextBlock?.sortOrder)
    } else {
        // Append to end of parent's children
        sortOrder = Block.sortOrderForAppending(to: parent.sortedChildren)
    }

    // 3. Create and insert block
    let newBlock = Block(
        content: op.content,
        parent: parent,
        sortOrder: sortOrder
    )
    context.insert(newBlock)

    // 4. Mark dirty for search reindexing
    dirtyTracker.markDirty(newBlock.id)
}
```

**Key details:**

- Uses `Block.sortOrderBetween(_:_:)` for precise insertion positioning (fractional indexing — no sibling rewrite needed)
- Uses `Block.sortOrderForAppending(to:)` when no `afterBlockId` is specified
- New block inherits depth automatically from `Block.init(parent:)` which sets `depth = parent.depth + 1`
- Default protection flags: `isDeletable: true`, `isContentEditableByUser: true`, etc. — the AI-created block is a normal user block

### Operation: `update_block`

**Input from AI:**

```json
{
  "type": "update_block",
  "block_id": "UUID-of-target",
  "new_content": "Refined and clearer sentence"
}
```

**Execution in AIEditApplier (pseudocode):**

```swift
func applyUpdateBlock(op: UpdateBlockOp, context: ModelContext, dirtyTracker: DirtyTracker, proposalCreatedAt: Date) throws {
    // 1. Fetch target block
    let block = try fetchBlock(id: op.blockId, context: context)

    // 2. Permission check
    guard block.isContentEditableByUser else {
        throw EditApplyError.blockNotEditable(op.blockId)
    }

    // 3. Staleness check — reject if block was modified after the proposal was generated
    guard block.updatedAt <= proposalCreatedAt else {
        throw EditApplyError.staleBlock(
            blockId: op.blockId,
            blockUpdatedAt: block.updatedAt,
            proposalCreatedAt: proposalCreatedAt
        )
    }

    // 4. Apply content change (uses Block.updateContent which sets updatedAt)
    block.updateContent(op.newContent)

    // 5. Mark dirty for search reindexing
    dirtyTracker.markDirty(block.id)
}
```

**Key details:**

- Uses `Block.updateContent(_:)` which handles both `content` and `updatedAt` in one call
- Staleness check compares `block.updatedAt` against proposal creation time — if the user edited the block between when AI generated the proposal and when they tapped "Accept", the proposal is rejected
- Permission check respects `isContentEditableByUser` flag (e.g. system-generated blocks like "Today's Notes" headers are protected)

### Operation: `archive_block` (v2)

**Input from AI:**

```json
{
  "type": "archive_block",
  "block_id": "UUID-of-target"
}
```

**Execution (pseudocode):**

```swift
func applyArchiveBlock(op: ArchiveBlockOp, context: ModelContext, dirtyTracker: DirtyTracker) throws {
    let block = try fetchBlock(id: op.blockId, context: context)

    guard block.isDeletable else {
        throw EditApplyError.blockNotDeletable(op.blockId)
    }

    // Soft delete — set isArchived flag, don't actually delete
    block.isArchived = true
    block.updatedAt = Date()

    // Mark deleted for search index cleanup
    dirtyTracker.markDeleted(block.id)
}
```

**Key details:**

- Soft delete via `isArchived = true` — reversible, unlike `modelContext.delete()`
- Respects `isDeletable` flag
- Archived blocks are filtered out by `displayEntries()` and search queries
- Deferred to v2 because destructive actions need extra UX care (undo toast, confirmation)

### Transactional apply — all-or-nothing

```swift
struct AIEditApplier {
    @MainActor
    static func apply(
        proposal: EditProposal,
        proposalCreatedAt: Date,
        context: ModelContext,
        dirtyTracker: DirtyTracker
    ) throws -> ApplyResult {
        // Phase 1: Validate ALL operations before executing any
        for op in proposal.operations {
            try validate(op, context: context, proposalCreatedAt: proposalCreatedAt)
        }

        // Phase 2: Execute all operations (only reached if all validations pass)
        var appliedOps: [AppliedOp] = []
        for op in proposal.operations {
            switch op {
            case .addBlock(let add):
                let newBlock = try applyAddBlock(op: add, context: context, dirtyTracker: dirtyTracker)
                appliedOps.append(.added(newBlock.id))

            case .updateBlock(let update):
                try applyUpdateBlock(op: update, context: context, dirtyTracker: dirtyTracker, proposalCreatedAt: proposalCreatedAt)
                appliedOps.append(.updated(update.blockId))
            }
        }

        // Phase 3: Flush dirty tracker to trigger reindexing
        Task { await dirtyTracker.flush() }

        return ApplyResult(appliedOps: appliedOps, appliedAt: Date())
    }

    private static func validate(_ op: EditOperation, context: ModelContext, proposalCreatedAt: Date) throws {
        switch op {
        case .addBlock(let add):
            // Parent must exist
            let _ = try fetchBlock(id: add.parentId, context: context)
            // afterBlockId must exist if specified
            if let afterId = add.afterBlockId {
                let _ = try fetchBlock(id: afterId, context: context)
            }

        case .updateBlock(let update):
            let block = try fetchBlock(id: update.blockId, context: context)
            guard block.isContentEditableByUser else {
                throw EditApplyError.blockNotEditable(update.blockId)
            }
            guard block.updatedAt <= proposalCreatedAt else {
                throw EditApplyError.staleBlock(blockId: update.blockId, blockUpdatedAt: block.updatedAt, proposalCreatedAt: proposalCreatedAt)
            }
        }
    }
}
```

**Why all-or-nothing:**

- If op 2 fails validation, op 1 should NOT have been applied
- Prevents partial state where some edits landed and others didn't
- Simple to reason about: either the whole proposal was applied or none of it was

### How the note view refreshes after edits

Two scenarios:

**A. User is NOT currently viewing the edited note:**

- No immediate UI refresh needed
- When they navigate to the note, `OutlineView.loadContent()` calls `buildEditableContent()` which reads from SwiftData — the new/updated blocks are already there

**B. User IS currently viewing the edited note (chat sheet is presented over it):**

- After dismissing the chat sheet, `OutlineView.onAppear` fires
- But `hasLoaded` is already `true`, so `loadContent()` won't re-run
- **Solution**: After applying edits, the ViewModel should set a flag or post a notification that triggers `reloadContent()` on the underlying OutlineView
- Simplest approach: `OutlineView` observes a `@Published var needsReload` on a shared state object, and calls `reloadContent()` when it flips

### Relationship to BlockBuilder

`BlockBuilder.buildPath()` is designed for **hierarchical path creation** (e.g., "Today's Notes > 2026 > March > Week 10 > Mar 6"). It finds-or-creates blocks along a path.

For AI edits, `BlockBuilder` is useful in one specific scenario:

- **`add_block` with a path**: If the AI wants to add a block under a note that might not exist yet (e.g., "add a reflection under today's note"), the applier can use `BlockBuilder.buildPath()` to ensure the full hierarchy exists before inserting the new content block.

```swift
// Example: AI says "add a block under today's note"
// Use BlockBuilder to ensure Today > 2026 > March > Week 10 > Mar 6 exists
let todayRoot = TodayNotesService.ensureRoot(context: context)
let dayBlock = BlockBuilder.buildPath(root: todayRoot, path: todayPath, context: context)

// Then add the AI-proposed block as a child of dayBlock
let newBlock = Block(content: op.content, parent: dayBlock, sortOrder: ...)
context.insert(newBlock)
```

For most `add_block` / `update_block` operations, the parent already exists (the AI references it by ID from search results), so `BlockBuilder` isn't needed — direct `Block` init + `modelContext.insert()` or `block.updateContent()` suffices.

### Error types

```swift
enum EditApplyError: Error {
    case blockNotFound(UUID)
    case blockNotEditable(UUID)
    case blockNotDeletable(UUID)
    case staleBlock(blockId: UUID, blockUpdatedAt: Date, proposalCreatedAt: Date)
    case invalidParentChild(parentId: UUID, afterBlockId: UUID)  // afterBlock is not a child of parent
}
```

### Diff preview rendering (for the suggested edit card)

The Figma design shows context lines + addition lines. To render this from the proposal:

```
For each operation in proposal.operations:
  if add_block:
    1. Fetch the parent block's sorted children
    2. Find the afterBlock (or use last child)
    3. Show 1-2 context lines BEFORE insertion point (existing sibling content, grey)
    4. Show the new content line(s) with green bg + "+" marker
    5. Show 1-2 context lines AFTER insertion point (existing sibling content, grey)

  if update_block:
    1. Fetch the block's current content
    2. Show current content as a deletion line (red bg + "-" marker)
    3. Show new content as an addition line (green bg + "+" marker)
    4. Show 1-2 surrounding siblings as context lines (grey)
```

This matches the Figma design where surrounding blocks provide context for where the edit lands.

---

## Risks & Mitigations

| Risk                                           | Mitigation                                                                    |
| ---------------------------------------------- | ----------------------------------------------------------------------------- |
| Broad retrieval produces noisy answers         | Cap retrieved blocks (e.g. top 8), include relevance scores, let model filter |
| Stale proposals after user edits main editor   | Check block `updatedAt` timestamp at apply time, reject if changed            |
| API latency hurts UX                           | Stream responses, show references immediately, typing indicator               |
| Proposal schema drift from prompt              | Strict JSON schema in system prompt, validate on parse, reject malformed      |
| Token budget blowup with many retrieved blocks | Truncate block content to ~200 chars in tool results, summarize if needed     |
