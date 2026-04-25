//
//  NotoToolExecutor.swift
//  NotoAIChat
//

import Foundation
import SwiftData
import os.log
import NotoModels
import NotoCore
import NotoClaudeAPI
import NotoSearchLegacy

private let logger = Logger(subsystem: "com.noto", category: "NotoToolExecutor")

/// Noto-specific tool executor that dispatches tool calls to local services.
/// Conforms to NotoClaudeAPI's ToolExecutor protocol.
///
/// Accumulates references and edit proposals across iterations for use by the caller.
public final class NotoToolExecutor: ToolExecutor, @unchecked Sendable {
    private let searchService: any SearchServiceProtocol
    private let modelContext: ModelContext

    // Accumulated state across iterations
    public private(set) var references: [BlockReference] = []
    public private(set) var editProposal: EditProposal?

    public init(searchService: any SearchServiceProtocol, modelContext: ModelContext) {
        self.searchService = searchService
        self.modelContext = modelContext
    }

    public func execute(toolUseId: String, name: String, input: JSONValue) async throws -> ToolResult {
        switch name {
        case "search_notes":
            return try await executeSearchNotes(toolUseId: toolUseId, input: input)
        case "get_block_context":
            return try await executeGetBlockContext(toolUseId: toolUseId, input: input)
        case "suggest_edit":
            return try executeSuggestEdit(toolUseId: toolUseId, input: input)
        default:
            logger.error("Unknown tool: \(name)")
            return ToolResult(toolUseId: toolUseId, content: "Unknown tool: \(name)", isError: true)
        }
    }

    // MARK: - search_notes

    @MainActor
    private func executeSearchNotes(toolUseId: String, input: JSONValue) async throws -> ToolResult {
        let params = try decodeInput(SearchNotesInput.self, from: input)
        var rawQuery = params.query
        if let dateHint = params.dateHint {
            rawQuery += " \(dateHint)"
        }

        logger.debug("search_notes: query='\(rawQuery)', limit=\(params.limit ?? 8)")

        let results = await searchService.search(rawQuery: rawQuery)
        let limit = min(params.limit ?? 8, 20)
        let limited = Array(results.prefix(limit))

        let newRefs = limited.map { result in
            BlockReference(blockId: result.id, content: result.content, relevanceScore: result.hybridScore)
        }
        references.append(contentsOf: newRefs)

        let output: [[String: Any]] = limited.map { result in
            [
                "block_id": result.id.uuidString,
                "content": truncate(result.content),
                "breadcrumb": result.breadcrumb,
                "relevance_score": result.hybridScore,
            ]
        }
        let jsonData = try JSONSerialization.data(withJSONObject: output)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"

        logger.debug("search_notes: returned \(limited.count) results")
        return ToolResult(toolUseId: toolUseId, content: jsonString)
    }

    // MARK: - get_block_context

    @MainActor
    private func executeGetBlockContext(toolUseId: String, input: JSONValue) async throws -> ToolResult {
        let params = try decodeInput(GetBlockContextInput.self, from: input)
        let blockIds = params.parsedBlockIds

        logger.debug("get_block_context: \(blockIds.count) blocks, up=\(params.resolvedLevelsUp), down=\(params.resolvedLevelsDown)")

        var contexts: [[String: Any]] = []

        for blockId in blockIds {
            let descriptor = FetchDescriptor<Block>(
                predicate: #Predicate<Block> { $0.id == blockId }
            )
            guard let block = try modelContext.fetch(descriptor).first else {
                contexts.append(["block_id": blockId.uuidString, "error": "Block not found"])
                continue
            }

            var context: [String: Any] = [
                "block_id": block.id.uuidString,
                "content": truncate(block.content),
                "breadcrumb": BreadcrumbBuilder.build(for: block),
                "depth": block.depth,
                "created_at": ISO8601DateFormatter().string(from: block.createdAt),
                "updated_at": ISO8601DateFormatter().string(from: block.updatedAt),
            ]

            // Ancestors
            if params.resolvedLevelsUp > 0 {
                var ancestors: [[String: Any]] = []
                var current = block.parent
                var remaining = params.resolvedLevelsUp
                while let parent = current, remaining > 0 {
                    ancestors.insert([
                        "block_id": parent.id.uuidString,
                        "content": truncate(parent.content),
                        "depth": parent.depth,
                    ], at: 0)
                    current = parent.parent
                    remaining -= 1
                }
                context["ancestors"] = ancestors
            }

            // Descendants
            if params.resolvedLevelsDown > 0 {
                var descendants: [[String: Any]] = []
                collectDescendants(
                    of: block,
                    currentLevel: 1,
                    maxLevel: params.resolvedLevelsDown,
                    into: &descendants
                )
                context["descendants"] = descendants
            }

            // Siblings
            if params.resolvedIncludeSiblings, let parent = block.parent {
                let sorted = parent.sortedChildren.filter { !$0.isArchived }
                if let idx = sorted.firstIndex(where: { $0.id == blockId }) {
                    let maxSib = params.resolvedMaxSiblings
                    let beforeStart = max(0, idx - maxSib)
                    let afterEnd = min(sorted.count, idx + 1 + maxSib)

                    let sibsBefore = sorted[beforeStart..<idx].map { sib -> [String: Any] in
                        ["block_id": sib.id.uuidString, "content": truncate(sib.content)]
                    }
                    let sibsAfter = sorted[(idx + 1)..<afterEnd].map { sib -> [String: Any] in
                        ["block_id": sib.id.uuidString, "content": truncate(sib.content)]
                    }
                    context["siblings_before"] = sibsBefore
                    context["siblings_after"] = sibsAfter
                }
            }

            contexts.append(context)
        }

        let jsonData = try JSONSerialization.data(withJSONObject: contexts)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        return ToolResult(toolUseId: toolUseId, content: jsonString)
    }

    private func collectDescendants(
        of block: Block,
        currentLevel: Int,
        maxLevel: Int,
        into result: inout [[String: Any]]
    ) {
        for child in block.sortedChildren where !child.isArchived {
            result.append([
                "block_id": child.id.uuidString,
                "content": truncate(child.content),
                "depth": child.depth,
            ])
            if currentLevel < maxLevel {
                collectDescendants(of: child, currentLevel: currentLevel + 1, maxLevel: maxLevel, into: &result)
            }
        }
    }

    // MARK: - suggest_edit

    private func executeSuggestEdit(toolUseId: String, input: JSONValue) throws -> ToolResult {
        let params = try decodeInput(SuggestEditInput.self, from: input)

        var operations: [EditOperation] = []
        var errors: [String] = []

        for (index, op) in params.operations.enumerated() {
            switch op.type {
            case "add_block":
                guard let parentIdStr = op.parentId,
                      let parentId = UUID(uuidString: parentIdStr) else {
                    errors.append("Operation \(index): add_block requires a valid parent_id")
                    continue
                }
                guard let content = op.content else {
                    errors.append("Operation \(index): add_block requires content")
                    continue
                }
                let afterBlockId = op.afterBlockId.flatMap { UUID(uuidString: $0) }
                operations.append(.addBlock(AddBlockOp(parentId: parentId, afterBlockId: afterBlockId, content: content)))
            case "update_block":
                guard let blockIdStr = op.blockId,
                      let blockId = UUID(uuidString: blockIdStr) else {
                    errors.append("Operation \(index): update_block requires a valid block_id")
                    continue
                }
                guard let newContent = op.newContent else {
                    errors.append("Operation \(index): update_block requires new_content")
                    continue
                }
                operations.append(.updateBlock(UpdateBlockOp(blockId: blockId, newContent: newContent)))
            default:
                errors.append("Operation \(index): unknown type '\(op.type)'")
            }
        }

        if operations.isEmpty && !errors.isEmpty {
            logger.error("suggest_edit: all operations invalid: \(errors.joined(separator: "; "))")
            return ToolResult(
                toolUseId: toolUseId,
                content: "Error: All operations are invalid. \(errors.joined(separator: ". "))",
                isError: true
            )
        }

        let proposal = EditProposal(operations: operations, summary: params.description)
        editProposal = proposal

        var message = "Edit proposal captured with \(operations.count) operation(s). It will be shown to the user for review."
        if !errors.isEmpty {
            message += " Warning: \(errors.count) operation(s) were invalid and skipped."
        }

        logger.debug("suggest_edit: captured proposal with \(operations.count) operations, \(errors.count) errors")
        return ToolResult(toolUseId: toolUseId, content: message)
    }

    // MARK: - Helpers

    private func decodeInput<T: Decodable>(_ type: T.Type, from input: JSONValue) throws -> T {
        let data = try JSONEncoder().encode(input)
        return try JSONDecoder().decode(type, from: data)
    }

    /// Truncate content to ~200 characters for token budget management.
    private func truncate(_ text: String, maxLength: Int = 200) -> String {
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)) + "..."
    }
}
