//
//  NotoToolDefinitions.swift
//  NotoAIChat
//

import Foundation
import NotoClaudeAPI

/// The three tool schemas available to Claude for Noto interactions.
public struct NotoToolDefinitions {
    public static let all: [ToolDefinition] = [searchNotes, getBlockContext, suggestEdit]

    public static let searchNotes = ToolDefinition(
        name: "search_notes",
        description: """
            Search the user's notes by keyword, semantic similarity, or date range. \
            Use this when the user asks about their past notes, thoughts, or writing. \
            Do NOT use this for generic questions unrelated to the user's notes. \
            Returns matching blocks with their content excerpt, breadcrumb path, and timestamps.
            """,
        inputSchema: ToolInputSchema(
            type: "object",
            properties: [
                "query": PropertySchema(
                    type: "string",
                    description: "Search query — keywords, phrases, or topics"
                ),
                "date_hint": PropertySchema(
                    type: "string",
                    description: "Optional time filter, e.g. 'today', 'last month', 'March 2026', 'this year'"
                ),
                "limit": PropertySchema(
                    type: "integer",
                    description: "Max results to return (default 8, max 20)"
                ),
            ],
            required: ["query"]
        )
    )

    public static let getBlockContext = ToolDefinition(
        name: "get_block_context",
        description: """
            Fetch the full content and surrounding context of specific blocks. \
            Use this after search_notes when you need to see the full text, parent hierarchy, \
            children, or sibling blocks around a result. \
            You control how many levels up (ancestors) and down (descendants) to fetch, \
            and whether to include siblings at the target's level.
            """,
        inputSchema: ToolInputSchema(
            type: "object",
            properties: [
                "block_ids": PropertySchema(
                    type: "array",
                    description: "Array of block UUIDs to fetch context for",
                    items: PropertySchema(type: "string")
                ),
                "levels_up": PropertySchema(
                    type: "integer",
                    description: "How many ancestor levels to include (0 = none, 1 = parent, etc.). Default 1."
                ),
                "levels_down": PropertySchema(
                    type: "integer",
                    description: "How many descendant levels to include (0 = none, 1 = direct children, etc.). Default 0."
                ),
                "include_siblings": PropertySchema(
                    type: "boolean",
                    description: "Whether to include sibling blocks at the same level. Default false."
                ),
                "max_siblings": PropertySchema(
                    type: "integer",
                    description: "Max sibling blocks above and below the target (default 3). Only used if include_siblings is true."
                ),
            ],
            required: ["block_ids"]
        )
    )

    public static let suggestEdit = ToolDefinition(
        name: "suggest_edit",
        description: """
            Propose additions or changes to the user's notes. These will be shown \
            as a visual diff for the user to review and accept or dismiss. \
            NEVER use this without first searching for relevant notes. \
            Only call this when the user explicitly asks for edits, additions, or rewrites.
            """,
        inputSchema: ToolInputSchema(
            type: "object",
            properties: [
                "description": PropertySchema(
                    type: "string",
                    description: "Brief human-readable description of what this edit does"
                ),
                "operations": PropertySchema(
                    type: "array",
                    description: "Array of edit operations to propose",
                    items: PropertySchema(
                        type: "object",
                        properties: [
                            "type": PropertySchema(
                                type: "string",
                                description: "Operation type",
                                enum: ["add_block", "update_block"]
                            ),
                            "parent_id": PropertySchema(
                                type: "string",
                                description: "UUID of parent block (required for add_block)"
                            ),
                            "after_block_id": PropertySchema(
                                type: "string",
                                description: "UUID of sibling to insert after (optional for add_block)"
                            ),
                            "content": PropertySchema(
                                type: "string",
                                description: "New block content (required for add_block)"
                            ),
                            "block_id": PropertySchema(
                                type: "string",
                                description: "UUID of block to update (required for update_block)"
                            ),
                            "new_content": PropertySchema(
                                type: "string",
                                description: "Replacement content (required for update_block)"
                            ),
                        ]
                    )
                ),
            ],
            required: ["description", "operations"]
        )
    )
}
