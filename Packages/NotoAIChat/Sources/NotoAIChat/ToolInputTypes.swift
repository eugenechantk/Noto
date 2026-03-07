//
//  ToolInputTypes.swift
//  NotoAIChat
//
//  Decodable input structs for each Noto tool, decoded from JSONValue.

import Foundation

struct SearchNotesInput: Decodable {
    let query: String
    let dateHint: String?
    let limit: Int?

    enum CodingKeys: String, CodingKey {
        case query
        case dateHint = "date_hint"
        case limit
    }
}

struct GetBlockContextInput: Decodable {
    let blockIds: [String]
    let levelsUp: Int?
    let levelsDown: Int?
    let includeSiblings: Bool?
    let maxSiblings: Int?

    enum CodingKeys: String, CodingKey {
        case blockIds = "block_ids"
        case levelsUp = "levels_up"
        case levelsDown = "levels_down"
        case includeSiblings = "include_siblings"
        case maxSiblings = "max_siblings"
    }

    var parsedBlockIds: [UUID] { blockIds.compactMap { UUID(uuidString: $0) } }
    var resolvedLevelsUp: Int { levelsUp ?? 1 }
    var resolvedLevelsDown: Int { levelsDown ?? 0 }
    var resolvedIncludeSiblings: Bool { includeSiblings ?? false }
    var resolvedMaxSiblings: Int { maxSiblings ?? 3 }
}

struct SuggestEditInput: Decodable {
    let description: String
    let operations: [SuggestEditOperation]
}

struct SuggestEditOperation: Decodable {
    let type: String
    let parentId: String?
    let afterBlockId: String?
    let content: String?
    let blockId: String?
    let newContent: String?

    enum CodingKeys: String, CodingKey {
        case type
        case parentId = "parent_id"
        case afterBlockId = "after_block_id"
        case content
        case blockId = "block_id"
        case newContent = "new_content"
    }
}
