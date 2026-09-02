import Foundation
import Testing
@testable import NotoTags

// MARK: - Test Case Index
// testTagNameNormalizationRules — normalization covers lowercasing, hash strip, whitespace, underscores, and invalid chars
// testTagNameNormalizationRejectsEmptyInputs — invalid values normalize to nil
// testTagNameComparableSortOrder — sort order is lexicographical by normalized value
// testTagNameCodableRoundTripsAsString — JSON codec is a single string
// testTagDefinitionUsesNameAsIdentity — id maps to name
// testTagDefinitionCodableRoundTrip — round-trips through JSON
// testTagDefinitionCodableToleratesUnknownKeys — ignores unknown fields
// testTagDefinitionDecodesNormalizedName — normalizes decoded name
// testTagRegistryUpsertReplacesExistingDefinition — upsert replaces by name
// testTagRegistryRemoveRemovesDefinition — remove deletes entry
// testTagRegistryEnsureCreatesThenReuses — ensure is lazy and idempotent
// testTagRegistryAllDefinitionsSorted — returns sorted definitions
// testTagRegistryDefinitionForName — fetches definitions by name
// testTagRegistryCodableVersionedEnvelope — encodes/decodes versioned payload
// testTagRegistryDecodesUnknownTopLevelFields — unknown envelope keys ignored
// testTagRegistryStoreLoadMissingFile — returns empty when file missing
// testTagRegistryStoreLoadEmptyFile — returns empty on whitespace
// testTagRegistryStoreSaveCreatesDirectory — creates missing directories
// testTagRegistryStoreSaveAndLoadRoundTrip — persists and reloads
// testTagMembershipNotesForTagStableOrder — preserves note order
// testTagMembershipAllTagsDedupedSorted — dedupes and sorts tags
// testTagMembershipCountForTag — counts deduped notes per tag
// testTagMembershipEmptyInput — empty dataset is empty
// testTagTemplateApplySkipsEmptyTemplate — empty template no-op
// testTagTemplateApplyAppendsOnceWithSeparator — append block at end with one blank line
// testTagTemplateApplyIsIdempotent — applying twice does not duplicate
// testTagTemplateApplyCanHandleFullContent — appends at end of content
// testTagTemplateApplyKeepsMultipleTagsSeparate — multiple tags each apply once

@Suite("TagName")
struct TagNameTests {

    // Applies all normalization rules in one pass.
    @Test
    func testTagNameNormalizationRules() {
        #expect(TagName("Podcast Script")?.rawValue == "podcast-script")
        #expect(TagName("#Idea")?.rawValue == "idea")
        #expect(TagName("my__cool  tag!")?.rawValue == "my-cool-tag")
        #expect(TagName("  Mixed   CAPS_and__spaces")?.rawValue == "mixed-caps-and-spaces")
        #expect(TagName("my-_-tag")?.rawValue == "my-tag")
    }

    // Rejects values that normalize to nothing.
    @Test
    func testTagNameNormalizationRejectsEmptyInputs() {
        #expect(TagName("") == nil)
        #expect(TagName("   ") == nil)
        #expect(TagName("---") == nil)
        #expect(TagName("___") == nil)
        #expect(TagName("###") == nil)
    }

    // Comparable uses normalized raw values.
    @Test
    func testTagNameComparableSortOrder() {
        guard
            let idea = TagName("idea"),
            let archive = TagName("archive"),
            let draft = TagName("draft")
        else {
            Issue.record("Tag initialization failed")
            return
        }

        let sorted = [idea, archive, draft].sorted()
        #expect(sorted.map(\.rawValue) == ["archive", "draft", "idea"])
    }

    // Codec must emit and accept plain strings.
    @Test
    func testTagNameCodableRoundTripsAsString() throws {
        guard let tag = TagName("#Idea") else {
            Issue.record("Tag initialization failed")
            return
        }

        let encoded = try JSONEncoder().encode(tag)
        #expect(String(data: encoded, encoding: .utf8) == "\"idea\"")

        let decoded = try JSONDecoder().decode(TagName.self, from: encoded)
        #expect(decoded == tag)
        #expect(decoded.rawValue == "idea")
    }
}

@Suite("TagDefinition")
struct TagDefinitionTests {

    // Name is the source of identity.
    @Test
    func testTagDefinitionUsesNameAsIdentity() {
        guard let name = TagName("work") else {
            Issue.record("Tag initialization failed")
            return
        }

        let definition = TagDefinition(
            name: name,
            template: "Template",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_123)
        )

        #expect(definition.id == name)
        #expect(definition.id.rawValue == "work")
    }

    // JSON round-trip preserves all decoded fields.
    @Test
    func testTagDefinitionCodableRoundTrip() throws {
        guard let name = TagName("Idea") else {
            Issue.record("Tag initialization failed")
            return
        }

        let definition = TagDefinition(
            name: name,
            template: "## Heading",
            createdAt: Date(timeIntervalSince1970: 1_700_000_123),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_456)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(definition)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TagDefinition.self, from: data)

        #expect(decoded == definition)
        #expect(decoded.name.rawValue == "idea")
    }

    // Unknown per-tag fields should not fail decoding.
    @Test
    func testTagDefinitionCodableToleratesUnknownKeys() throws {
        let payload = """
        {
          "name": "project",
          "template": "Body",
          "createdAt": "2026-01-01T00:00:00Z",
          "modifiedAt": "2026-01-02T00:00:00Z",
          "future": "ignored"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(TagDefinition.self, from: payload.data(using: .utf8)!)

        #expect(decoded.name.rawValue == "project")
        #expect(decoded.template == "Body")
    }

    // Name input from payload should be normalized before storage.
    @Test
    func testTagDefinitionDecodesNormalizedName() throws {
        let payload = """
        {
          "name": "  #Daily\\tNotes ",
          "template": "",
          "createdAt": "2026-01-01T00:00:00Z",
          "modifiedAt": "2026-01-02T00:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(TagDefinition.self, from: payload.data(using: .utf8)!)
        #expect(decoded.name.rawValue == "daily-notes")
    }
}

@Suite("TagRegistry")
struct TagRegistryTests {

    // Upsert is replace-or-add based on tag name.
    @Test
    func testTagRegistryUpsertReplacesExistingDefinition() {
        guard
            let idea = TagName("idea"),
            let first = TagName("first")
        else {
            Issue.record("Tag initialization failed")
            return
        }

        var registry = TagRegistry()
        registry.upsert(TagDefinition(name: idea, template: "A", createdAt: .now, modifiedAt: .now))
        registry.upsert(TagDefinition(name: idea, template: "B", createdAt: .now, modifiedAt: .now))
        registry.upsert(TagDefinition(name: first, template: "C", createdAt: .now, modifiedAt: .now))

        #expect(registry.definition(for: idea)?.template == "B")
        #expect(registry.allDefinitions().count == 2)
    }

    // Remove should drop a definition by name.
    @Test
    func testTagRegistryRemoveRemovesDefinition() {
        guard
            let idea = TagName("idea"),
            let task = TagName("task")
        else {
            Issue.record("Tag initialization failed")
            return
        }

        var registry = TagRegistry()
        registry.upsert(TagDefinition(name: idea, template: "A", createdAt: .now, modifiedAt: .now))
        registry.upsert(TagDefinition(name: task, template: "B", createdAt: .now, modifiedAt: .now))

        registry.remove(task)

        #expect(registry.definition(for: task) == nil)
        #expect(registry.allDefinitions().count == 1)
    }

    // Ensure should create once and reuse same definition on later calls.
    @Test
    func testTagRegistryEnsureCreatesThenReuses() {
        guard let tagName = TagName("new-tag") else {
            Issue.record("Tag initialization failed")
            return
        }

        var registry = TagRegistry()
        let first = registry.ensure(tagName, now: Date(timeIntervalSince1970: 1_000_000_000))
        let second = registry.ensure(tagName, now: Date(timeIntervalSince1970: 2_000_000_000))

        #expect(registry.allDefinitions().count == 1)
        #expect(first == second)
        #expect(first.createdAt == second.createdAt)
        #expect(first.modifiedAt == second.modifiedAt)
    }

    // Definitions are returned with stable sorting.
    @Test
    func testTagRegistryAllDefinitionsSorted() {
        guard
            let firstName = TagName("zeta"),
            let secondName = TagName("alpha"),
            let thirdName = TagName("delta")
        else {
            Issue.record("Tag initialization failed")
            return
        }

        var registry = TagRegistry()
        registry.upsert(TagDefinition(name: firstName, template: "", createdAt: .now, modifiedAt: .now))
        registry.upsert(TagDefinition(name: secondName, template: "", createdAt: .now, modifiedAt: .now))
        registry.upsert(TagDefinition(name: thirdName, template: "", createdAt: .now, modifiedAt: .now))

        #expect(registry.allDefinitions().map(\.name.rawValue) == ["alpha", "delta", "zeta"])
    }

    // Definition lookup by tag is stable.
    @Test
    func testTagRegistryDefinitionForName() {
        guard
            let name = TagName("goal"),
            let missing = TagName("missing")
        else {
            Issue.record("Tag initialization failed")
            return
        }

        var registry = TagRegistry()
        registry.upsert(TagDefinition(name: name, template: "Plan", createdAt: .now, modifiedAt: .now))

        #expect(registry.definition(for: name)?.template == "Plan")
        #expect(registry.definition(for: missing) == nil)
    }

    // JSON shape should include version and sorted tag list.
    @Test
    func testTagRegistryCodableVersionedEnvelope() throws {
        guard
            let firstName = TagName("zulu"),
            let secondName = TagName("alpha")
        else {
            Issue.record("Tag initialization failed")
            return
        }

        var registry = TagRegistry()
        registry.upsert(TagDefinition(name: firstName, template: "", createdAt: Date(timeIntervalSince1970: 1), modifiedAt: Date(timeIntervalSince1970: 2)))
        registry.upsert(TagDefinition(name: secondName, template: "T", createdAt: Date(timeIntervalSince1970: 3), modifiedAt: Date(timeIntervalSince1970: 4)))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(registry)

        let payload = String(data: data, encoding: .utf8) ?? ""
        #expect(payload.contains("\"version\""))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TagRegistry.self, from: data)

        #expect(decoded.allDefinitions().map(\.name.rawValue) == ["alpha", "zulu"])
    }

    // Unknown top-level keys in JSON envelope must be tolerated.
    @Test
    func testTagRegistryDecodesUnknownTopLevelFields() throws {
        let payload = """
        {
          "version": 99,
          "legacy": true,
          "tags": [
            {
              "name": "idea",
              "template": "",
              "createdAt": "2026-01-01T00:00:00Z",
              "modifiedAt": "2026-01-02T00:00:00Z",
              "future": "ignored"
            }
          ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(TagRegistry.self, from: payload.data(using: .utf8)!)
        #expect(decoded.allDefinitions().count == 1)
        #expect(decoded.definition(for: TagName("idea")!)?.template == "")
    }
}

@Suite("TagRegistryStore")
struct TagRegistryStoreTests {

    private func makeTempFile() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotoTagsTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(".noto").appendingPathComponent("tags.json")
    }

    // Missing file should return empty registry.
    @Test
    func testTagRegistryStoreLoadMissingFile() throws {
        let store = TagRegistryStore()
        let file = try makeTempFile()
        try? FileManager.default.removeItem(at: file)

        #expect(try store.load(from: file).allDefinitions().isEmpty)

        try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent())
    }

    // Empty or whitespace file should return empty registry.
    @Test
    func testTagRegistryStoreLoadEmptyFile() throws {
        let store = TagRegistryStore()
        let file = try makeTempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "   \n\n".data(using: .utf8)!.write(to: file)

        #expect(try store.load(from: file).allDefinitions().isEmpty)

        try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent())
    }

    // Save should create missing directories, including .noto.
    @Test
    func testTagRegistryStoreSaveCreatesDirectory() throws {
        let store = TagRegistryStore()
        let file = try makeTempFile()
        let registry = TagRegistry(definitions: [
            TagDefinition(
                name: TagName("todo")!,
                template: "- [ ] item",
                createdAt: .now,
                modifiedAt: .now
            )
        ])

        try store.save(registry, to: file)

        #expect(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))

        try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent())
    }

    // Save-and-load round-trip should be lossless.
    @Test
    func testTagRegistryStoreSaveAndLoadRoundTrip() throws {
        let store = TagRegistryStore()
        let file = try makeTempFile()

        let expected = TagRegistry(definitions: [
            TagDefinition(
                name: TagName("idea")!,
                template: "Some idea body",
                createdAt: Date(timeIntervalSince1970: 1_700_000_001),
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_002)
            ),
            TagDefinition(
                name: TagName("task")!,
                template: "",
                createdAt: Date(timeIntervalSince1970: 1_700_000_003),
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_004)
            )
        ])

        try store.save(expected, to: file)
        let loaded = try store.load(from: file)

        #expect(loaded.allDefinitions() == expected.allDefinitions())

        try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent())
    }
}

@Suite("TagMembershipIndex")
struct TagMembershipIndexTests {

    // Notes for a tag stay in the input order.
    @Test
    func testTagMembershipNotesForTagStableOrder() {
        guard
            let idea = TagName("idea"),
            let draft = TagName("draft")
        else {
            Issue.record("Tag initialization failed")
            return
        }

        let records: [NoteTagRecord] = [
            NoteTagRecord(noteID: "note-2", tags: [idea, draft]),
            NoteTagRecord(noteID: "note-1", tags: [idea]),
            NoteTagRecord(noteID: "note-3", tags: [draft])
        ]

        let index = TagMembershipIndex(records: records)

        #expect(index.notes(withTag: idea) == ["note-2", "note-1"])
        #expect(index.notes(withTag: draft) == ["note-2", "note-3"])
    }

    // allTags should be deduped and sorted.
    @Test
    func testTagMembershipAllTagsDedupedSorted() {
        guard
            let idea = TagName("idea"),
            let draft = TagName("draft"),
            let alpha = TagName("alpha")
        else {
            Issue.record("Tag initialization failed")
            return
        }

        let records: [NoteTagRecord] = [
            NoteTagRecord(noteID: "note-1", tags: [idea, idea, draft]),
            NoteTagRecord(noteID: "note-2", tags: [alpha, idea]),
            NoteTagRecord(noteID: "note-3", tags: [draft])
        ]

        let index = TagMembershipIndex(records: records)

        #expect(index.allTags() == [alpha, draft, idea])
    }

    // Count is per deduplicated tag-note membership.
    @Test
    func testTagMembershipCountForTag() {
        guard
            let idea = TagName("idea"),
            let task = TagName("task")
        else {
            Issue.record("Tag initialization failed")
            return
        }

        let records = [
            NoteTagRecord(noteID: "note-1", tags: [idea]),
            NoteTagRecord(noteID: "note-2", tags: [idea, task]),
            NoteTagRecord(noteID: "note-2", tags: [idea]),
            NoteTagRecord(noteID: "note-3", tags: [task]),
            NoteTagRecord(noteID: "", tags: [task])
        ]

        let index = TagMembershipIndex(records: records)

        #expect(index.count(for: idea) == 2)
        #expect(index.count(for: idea) == 2)
        #expect(index.count(for: task) == 2)
    }

    // Empty input yields empty outputs.
    @Test
    func testTagMembershipEmptyInput() {
        let index = TagMembershipIndex(records: [])

        #expect(index.allTags().isEmpty)
        #expect(index.notes(withTag: TagName("anything")!).isEmpty)
    }
}

@Suite("TagTemplateApplier")
struct TagTemplateApplierTests {

    // Whitespace-only templates should no-op.
    @Test
    func testTagTemplateApplySkipsEmptyTemplate() {
        let content = "# heading"
        let result = TagTemplateApplier.apply(template: "   \n\n", forTag: TagName("idea")!, to: content)

        #expect(result == content)
    }

    // Appending creates marker + template block at document end.
    @Test
    func testTagTemplateApplyAppendsOnceWithSeparator() {
        let content = "# Heading\nParagraph"
        let tag = TagName("Idea")!
        let result = TagTemplateApplier.apply(template: "Template line", forTag: tag, to: content)

        #expect(result == "# Heading\nParagraph\n\n<!-- noto:tag-template:idea -->\nTemplate line\n")
        #expect(TagTemplateApplier.isApplied(template: "Template line", forTag: tag, in: result))
    }

    // Reapplying should be idempotent per marker.
    @Test
    func testTagTemplateApplyIsIdempotent() {
        let tag = TagName("task")!
        let content = "body\n"
        let once = TagTemplateApplier.apply(template: "Todo item", forTag: tag, to: content)
        let twice = TagTemplateApplier.apply(template: "Todo item", forTag: tag, to: once)

        #expect(once == twice)
        #expect(once.components(separatedBy: "<!-- noto:tag-template:task -->").count - 1 == 1)
    }

    // Appends to full content, not frontmatter sections only.
    @Test
    func testTagTemplateApplyCanHandleFullContent() {
        let content = """
        ---
        id: abc
        tags: [idea]
        ---
        # Note body
        """

        let tag = TagName("daily")!
        let result = TagTemplateApplier.apply(template: "Daily template", forTag: tag, to: content)

        #expect(result.hasPrefix(content))
        #expect(result.hasSuffix("<!-- noto:tag-template:daily -->\nDaily template\n"))
    }

    // Multiple tags append independent single marker/template blocks.
    @Test
    func testTagTemplateApplyKeepsMultipleTagsSeparate() {
        let content = "start"
        let idea = TagName("idea")!
        let task = TagName("task")!

        let ideaApplied = TagTemplateApplier.apply(template: "Idea body", forTag: idea, to: content)
        let full = TagTemplateApplier.apply(template: "Task body", forTag: task, to: ideaApplied)

        #expect(full.components(separatedBy: "<!-- noto:tag-template:idea -->").count - 1 == 1)
        #expect(full.components(separatedBy: "<!-- noto:tag-template:task -->").count - 1 == 1)
        #expect(full.hasPrefix("start\n\n"))
    }
}
