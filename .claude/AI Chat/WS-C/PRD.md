# PRD: WS-C — Chat Block Extension DTOs (NotoAIChat Models)

## Goal

Create the `NotoAIChat` Swift package containing all Codable data transfer objects that represent AI chat conversations stored as Blocks. These DTOs encode/decode to `Block.extensionData` and define the structure for conversation roots, user messages, AI responses, and suggested edits.

## Background

Noto stores AI chat conversations as Block trees. Each block in a conversation carries structured metadata in its `extensionData` (a `Data?` blob). This package defines the Codable types that serialize into that blob, plus helper extensions on Block for encoding/decoding.

## Types

### ChatBlockRole
Discriminator enum: `.conversation`, `.userMessage`, `.aiResponse`, `.suggestedEdit`. Stored as raw strings.

### Extension structs (one per role)
- **ConversationExtension** — root of a chat session. Links to the note the user was viewing.
- **UserMessageExtension** — a sent user message with turn index.
- **AIResponseExtension** — AI reply with references to source blocks and tool call records.
- **SuggestedEditExtension** — an edit proposal with accept/dismiss status.

### Supporting types
- **BlockReference** — snapshot of a referenced block (id, content excerpt, relevance score).
- **ToolCallRecord** — record of a tool invocation (name, input JSON, output JSON).
- **EditProposal** — list of edit operations with a summary.
- **EditOperation** — discriminated union: `.addBlock(...)` or `.updateBlock(...)`.
- **EditStatus** — `.pending`, `.accepted`, `.dismissed`.

### Block helpers
- `Block.decodeExtension<T>(_:)` — decode extensionData to a Codable type.
- `Block.encodeExtension<T>(_:)` — encode a Codable value to Data for extensionData.
- MetadataField key constants for queryable fields.

## Non-goals
- No UI code, no API client, no persistence/store logic.
- No SwiftData queries or ModelContext usage (that's WS-F).

## Dependencies
- NotoModels (for Block type)
- NotoCore (for utilities)
