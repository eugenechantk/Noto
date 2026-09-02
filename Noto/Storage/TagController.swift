import Foundation
import NotoTags
import NotoVault
import Observation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "TagController")

@MainActor
@Observable
final class TagController {
    let vaultURL: URL
    private(set) var registry: TagRegistry
    private(set) var membershipIndex: TagMembershipIndex

    private let registryStore: TagRegistryStore
    private let registryURL: URL

    init(vaultURL: URL, registryStore: TagRegistryStore = TagRegistryStore()) {
        self.vaultURL = vaultURL.standardizedFileURL
        self.registryStore = registryStore
        self.registryURL = vaultURL.standardizedFileURL.appendingPathComponent(".noto/tags.json")
        self.registry = TagRegistry()
        self.membershipIndex = TagMembershipIndex(records: [])
    }

    nonisolated static func tagNames(inFrontmatterOf markdown: String) -> [TagName] {
        guard
            let document = EditableFrontmatterDocument(markdown: markdown),
            let tagsField = document.fields.first(where: { $0.key == "tags" })
        else {
            return []
        }

        return NotePropertyClassifier.parseTags(tagsField.value)
            .compactMap(TagName.init)
    }

    func load() {
        let registryStore = registryStore
        let registryURL = registryURL

        Task.detached(priority: .utility) { [weak self] in
            do {
                let loaded = try registryStore.load(from: registryURL)
                await MainActor.run {
                    self?.registry = loaded
                }
            } catch {
                logger.error("Failed to load tag registry from \(registryURL.path): \(error.localizedDescription)")
                await MainActor.run {
                    self?.registry = TagRegistry()
                }
            }
        }
    }

    func rebuildMembership() {
        let vaultURL = vaultURL
        let currentRegistry = registry
        let registryStore = registryStore
        let registryURL = registryURL

        Task { @MainActor in
            let result = await Task.detached(priority: .utility) {
                let records = Self.scanTagRecords(in: vaultURL)

                var registry = currentRegistry
                let discoveredTags = Set(records.flatMap { $0.tags })
                var didRegisterTags = false

                if !discoveredTags.isEmpty {
                    let now = Date()
                    for tag in discoveredTags {
                        if registry.definition(for: tag) == nil {
                            _ = registry.ensure(tag, now: now)
                            didRegisterTags = true
                        }
                    }
                }

                return (
                    registry: registry,
                    membershipIndex: TagMembershipIndex(records: records),
                    shouldPersistRegistry: didRegisterTags
                )
            }.value

            registry = result.registry
            membershipIndex = result.membershipIndex

            if result.shouldPersistRegistry {
                let registry = result.registry
                Task.detached(priority: .utility) {
                    do {
                        try registryStore.save(registry, to: registryURL)
                    } catch {
                        logger.error("Failed to persist tag registry after rebuild from \(registryURL.path): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func allTagNames() -> [TagName] {
        var names = Set<TagName>()
        names.formUnion(registry.allDefinitions().map(\.name))
        names.formUnion(membershipIndex.allTags())
        return Array(names).sorted()
    }

    func suggestions(matching fragment: String) -> [TagName] {
        let normalized = TagName.normalize(fragment)
        let names = allTagNames()

        if normalized.isEmpty {
            return Array(names.prefix(10))
        }

        let prefixMatches = names.filter { $0.rawValue.hasPrefix(normalized) }
        let substringMatches = names.filter {
            !$0.rawValue.hasPrefix(normalized) && $0.rawValue.contains(normalized)
        }
        return Array((prefixMatches + substringMatches).prefix(10))
    }

    @discardableResult
    func commitTags(_ rawMembers: [String], previous: [TagName], frontmatterKey: String, session: NoteEditorSession) -> [TagName] {
        var normalizedMembers: [TagName] = []
        for raw in rawMembers {
            guard let tag = TagName(raw) else { continue }
            if !normalizedMembers.contains(tag) {
                normalizedMembers.append(tag)
            }
        }

        session.applyExternalContentEdit(
            EditableFrontmatterDocument.updatingField(
                key: frontmatterKey,
                value: NotePropertyClassifier.serializeTags(normalizedMembers.map(\.rawValue)),
                in: session.content
            )
        )

        for tag in normalizedMembers where !previous.contains(tag) {
            let withTemplate = applyTemplate(for: tag, to: session.content)
            if withTemplate != session.content {
                session.applyExternalContentEdit(withTemplate)
            }
        }

        return normalizedMembers
    }

    func definition(for name: TagName) -> TagDefinition? {
        registry.definition(for: name)
    }

    func notes(withTag name: TagName) -> [String] {
        membershipIndex.notes(withTag: name)
    }

    func count(for name: TagName) -> Int {
        membershipIndex.count(for: name)
    }

    @discardableResult
    func save(_ definition: TagDefinition) -> TagDefinition {
        let now = Date()
        var normalizedDefinition = definition
        if let existing = registry.definition(for: definition.name) {
            normalizedDefinition = TagDefinition(
                name: definition.name,
                template: definition.template,
                createdAt: existing.createdAt,
                modifiedAt: now
            )
        } else {
            normalizedDefinition = TagDefinition(
                name: definition.name,
                template: definition.template,
                createdAt: now,
                modifiedAt: now
            )
        }

        var next = registry
        next.upsert(normalizedDefinition)
        registry = next

        let persisted = next
        Task.detached(priority: .utility) { [registryStore, registryURL] in
            do {
                try registryStore.save(persisted, to: registryURL)
            } catch {
                logger.error("Failed to persist tag registry after save to \(registryURL.path): \(error.localizedDescription)")
            }
        }

        return normalizedDefinition
    }

    func remove(_ name: TagName) {
        var next = registry
        guard next.definition(for: name) != nil else {
            return
        }

        next.remove(name)
        registry = next

        let persisted = next
        Task.detached(priority: .utility) { [registryStore, registryURL] in
            do {
                try registryStore.save(persisted, to: registryURL)
            } catch {
                logger.error("Failed to persist tag registry after removal from \(registryURL.path): \(error.localizedDescription)")
            }
        }
    }

    func applyTemplate(for name: TagName, to content: String) -> String {
        guard
            let definition = definition(for: name),
            !definition.template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return content
        }

        return TagTemplateApplier.apply(template: definition.template, forTag: name, to: content)
    }

    nonisolated private static func scanTagRecords(in vaultURL: URL) -> [NoteTagRecord] {
        guard let enumerator = FileManager.default.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            logger.error("Failed to enumerate vault for tag rebuild: \(vaultURL.path)")
            return []
        }

        var records: [NoteTagRecord] = []

        for case let fileURL as URL in enumerator {
            if fileURL.pathComponents.contains(".noto") {
                continue
            }

            guard fileURL.pathExtension.lowercased() == "md" else {
                continue
            }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            let tags = Self.tagNames(inFrontmatterOf: content)
            guard !tags.isEmpty else { continue }

            records.append(NoteTagRecord(
                noteID: vaultRelativePath(for: fileURL, in: vaultURL),
                tags: tags
            ))
        }

        return records
    }

    nonisolated private static func vaultRelativePath(for fileURL: URL, in vaultURL: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let vaultPath = vaultURL.standardizedFileURL.path
        guard filePath.hasPrefix(vaultPath) else {
            return fileURL.lastPathComponent
        }

        let relative = String(filePath.dropFirst(vaultPath.count))
        return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
    }
}
