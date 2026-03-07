# PRD: NotoClaudeAPI Package

## Overview

NotoClaudeAPI is a standalone Swift package that wraps the Anthropic Claude Messages API with a generic tool-use loop. It has zero Noto dependencies (Foundation only) and can be reused in any Swift project.

## Goals

1. Provide a typed, Codable interface to the Claude Messages API via URLSession
2. Define a generic ToolExecutor protocol so any app can plug in its own tool implementations
3. Implement a capped ChatLoop that drives the tool_use -> execute -> tool_result cycle
4. Be independently buildable and testable via `swift build` / `swift test`

## Components

### ClaudeAPIClient
- Thin URLSession wrapper
- Single method: `sendMessage(_:) async throws -> MessagesResponse`
- Sets required headers: Content-Type, x-api-key, anthropic-version
- Throws typed errors for HTTP failures and decoding issues

### Codable API Types
- `MessagesRequest` (Encodable): model, max_tokens, system, messages, tools
- `MessagesResponse` (Decodable): id, content, stop_reason, usage
- `Message`: role + MessageContent (text string or array of ContentBlocks)
- `ContentBlock` enum: .text, .toolUse, .toolResult
- `JSONValue`: flexible JSON type for tool inputs

### Tool Schema Types
- `ToolDefinition`: name, description, input_schema
- `ToolInputSchema`: type, properties, items, required, enum
- `PropertySchema`: type, description, items, properties, enum

### ToolExecutor Protocol
- Single method: `execute(toolUseId:name:input:) async throws -> ToolResult`
- `ToolResult`: toolUseId, content (String), isError (Bool)

### ChatLoop
- Takes ClaudeAPIClient, ChatLoopConfig, tool definitions, and a ToolExecutor
- Runs a capped while loop (maxToolIterations, default 5)
- On tool_use stop reason: executes tools, appends assistant + tool_result messages, continues
- On end_turn stop reason: extracts text, returns ChatLoopResult
- On max iterations: sends final request without tools to force text response
- Returns ChatLoopResult: finalResponse, toolCallHistory, iterationsUsed

### ChatLoopConfig
- model (String, default "claude-sonnet-4-6")
- maxTokens (Int, default 4096)
- systemPrompt (String?, optional)
- tools ([ToolDefinition], the tool schemas)
- maxToolIterations (Int, default 5)

### Error Types
- `ClaudeAPIError`: httpError, decodingError, invalidResponse
- `ChatLoopError`: unexpectedStopReason, maxIterationsReached (informational, not thrown)

## Non-Goals
- Streaming responses (v2)
- Noto-specific tool implementations (belongs in NotoAIChat)
- API key management / keychain storage (app-level concern)
- Retry logic / rate limiting (app-level concern)
