import Foundation
import Testing
@testable import NotoChat

// Verifies SC5: SSE parsing + streamed tool-call delta accumulation.
@Suite struct SSEStreamDecoderTests {

    private func drain(_ lines: [String]) -> [ChatStreamEvent] {
        var decoder = SSEStreamDecoder()
        var events: [ChatStreamEvent] = []
        for line in lines { events.append(contentsOf: decoder.ingest(line)) }
        return events
    }

    @Test func parsesIncrementalTextDeltasThenFinish() {
        let events = drain([
            sseLine(["choices": [["delta": ["content": "Hel"]]]]),
            sseLine(["choices": [["delta": ["content": "lo"]]]]),
            ": OPENROUTER PROCESSING",            // keep-alive comment — ignored
            "",                                    // blank line — ignored
            sseLine(["choices": [["delta": [:], "finish_reason": "stop"]]]),
            "data: [DONE]",
        ])
        #expect(events == [.textDelta("Hel"), .textDelta("lo"), .finished(reason: "stop")])
    }

    @Test func accumulatesToolCallArgumentsAcrossChunks() {
        let events = drain([
            sseLine(["choices": [["delta": ["tool_calls": [
                ["index": 0, "id": "call_1", "type": "function",
                 "function": ["name": "grep", "arguments": ""]]
            ]]]]]),
            sseLine(["choices": [["delta": ["tool_calls": [
                ["index": 0, "function": ["arguments": "{\"query\":\"al"]]
            ]]]]]),
            sseLine(["choices": [["delta": ["tool_calls": [
                ["index": 0, "function": ["arguments": "pha\"}"]]
            ]]]]]),
            sseLine(["choices": [["delta": [:], "finish_reason": "tool_calls"]]]),
        ])

        let expectedCall = ToolCall(id: "call_1", type: "function",
                                    function: .init(name: "grep", arguments: "{\"query\":\"alpha\"}"))
        #expect(events == [.toolCalls([expectedCall]), .finished(reason: "tool_calls")])
    }

    @Test func handlesTwoParallelToolCallsByIndex() {
        let events = drain([
            sseLine(["choices": [["delta": ["tool_calls": [
                ["index": 0, "id": "a", "function": ["name": "grep", "arguments": "{}"]],
                ["index": 1, "id": "b", "function": ["name": "list", "arguments": "{}"]]
            ]]]]]),
            sseLine(["choices": [["delta": [:], "finish_reason": "tool_calls"]]]),
        ])
        guard case let .toolCalls(calls)? = events.first else {
            Issue.record("expected tool calls"); return
        }
        #expect(calls.map(\.function.name) == ["grep", "list"])
        #expect(calls.map(\.id) == ["a", "b"])
    }
}
