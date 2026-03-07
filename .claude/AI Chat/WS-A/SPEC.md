# Technical Spec: NotoClaudeAPI Package

## Package Structure

```
Packages/NotoClaudeAPI/
  Package.swift
  Sources/NotoClaudeAPI/
    ClaudeAPIClient.swift      -- URLSession HTTP client
    Models.swift               -- MessagesRequest, MessagesResponse, Message, ContentBlock, etc.
    JSONValue.swift            -- Flexible JSON Codable type
    ToolSchema.swift           -- ToolDefinition, ToolInputSchema, PropertySchema
    ToolExecutor.swift         -- ToolExecutor protocol, ToolResult
    ChatLoop.swift             -- Capped tool-use loop
    ChatLoopConfig.swift       -- Configuration types
    Errors.swift               -- ClaudeAPIError, ChatLoopError
  Tests/NotoClaudeAPITests/
    ModelsTests.swift          -- Encode/decode round-trips
    ChatLoopTests.swift        -- Loop behavior tests with mock executor
    JSONValueTests.swift       -- JSONValue coding tests
```

## Key Design Decisions

### JSONValue
Recursive enum conforming to Codable for arbitrary JSON. Cases: string, number, bool, null, array, object. Used for tool `input` fields where schema is dynamic.

### MessageContent encoding
- `.text(String)` encodes as a bare JSON string (Claude API accepts this)
- `.blocks([ContentBlock])` encodes as a JSON array of typed content blocks

### ContentBlock discriminator
Uses `type` field for coding: "text", "tool_use", "tool_result". Custom Codable implementation with CodingKeys.

### ChatLoop algorithm
```
func run(messages, tools, executor) -> ChatLoopResult:
  iteration = 0
  while iteration < maxToolIterations:
    response = client.sendMessage(request with messages + tools)
    if response.stop_reason == "end_turn":
      return ChatLoopResult(text, history, iteration)
    if response.stop_reason != "tool_use":
      throw unexpectedStopReason
    for each tool_use block in response.content:
      result = executor.execute(toolUseId, name, input)
      record in history
    append assistant message (response.content) to messages
    append user message (tool_results) to messages
    iteration += 1
  // max iterations hit - final call without tools
  response = client.sendMessage(request without tools)
  return ChatLoopResult(text, history, iteration)
```

### Protocol for testability
ClaudeAPIClient uses a protocol (`ClaudeAPIClientProtocol`) internally so ChatLoop can be tested with a mock client that returns canned responses without hitting the network.

## Test Plan

1. **Codable round-trips**: Encode then decode MessagesRequest, MessagesResponse, ContentBlock variants, JSONValue
2. **ChatLoop end_turn**: Mock client returns end_turn on first call -> loop exits immediately, 0 iterations
3. **ChatLoop tool_use -> end_turn**: Mock returns tool_use, then end_turn -> 1 iteration, tool executed
4. **ChatLoop max iterations**: Mock always returns tool_use -> loop hits cap, final call made without tools
5. **Message threading**: Verify assistant tool_use message and user tool_result message are correctly appended
6. **ToolResult isError**: Verify error results are encoded with is_error: true
