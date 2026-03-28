import Testing
import Foundation
@testable import NotoClaudeAPI

@Suite("JSONValue Tests")
struct JSONValueTests {
    @Test("Encode and decode string")
    func stringRoundTrip() throws {
        let value = JSONValue.string("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("Encode and decode number")
    func numberRoundTrip() throws {
        let value = JSONValue.number(42.5)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("Encode and decode bool")
    func boolRoundTrip() throws {
        let value = JSONValue.bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("Encode and decode null")
    func nullRoundTrip() throws {
        let value = JSONValue.null
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("Encode and decode array")
    func arrayRoundTrip() throws {
        let value = JSONValue.array([.string("a"), .number(1), .bool(false)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("Encode and decode nested object")
    func objectRoundTrip() throws {
        let value = JSONValue.object([
            "query": .string("self-growth"),
            "limit": .number(10),
            "nested": .object(["key": .bool(true)])
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("Subscript access on object")
    func subscriptAccess() {
        let value = JSONValue.object(["name": .string("test")])
        #expect(value["name"]?.stringValue == "test")
        #expect(value["missing"] == nil)
    }

    @Test("Type accessors return nil for wrong type")
    func typeAccessors() {
        let str = JSONValue.string("hello")
        #expect(str.stringValue == "hello")
        #expect(str.numberValue == nil)
        #expect(str.boolValue == nil)
        #expect(str.arrayValue == nil)
        #expect(str.objectValue == nil)
    }
}
