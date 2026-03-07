//
//  SystemPromptBuilder.swift
//  NotoAIChat
//

import Foundation

/// Builds the system prompt for Claude, including base instructions and optional note context.
public struct SystemPromptBuilder {

    public static func build(noteContext: NoteContext? = nil, currentDate: Date = Date()) -> String {
        var parts: [String] = []

        parts.append(baseInstructions)

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        parts.append("Today's date is \(formatter.string(from: currentDate)).")

        if let context = noteContext {
            parts.append("""
                The user is currently viewing a note:
                - Title: \(context.title)
                - Location: \(context.breadcrumb)
                When the user says "this note" or "here", they are referring to this note.
                """)
        }

        return parts.joined(separator: "\n\n")
    }

    private static let baseInstructions = """
        You are an AI assistant integrated into Noto, an outline-based note-taking app. \
        The user's notes are organized as a tree of blocks (bullet points) that can be infinitely nested.

        Your capabilities:
        - Search the user's notes using the search_notes tool
        - Fetch detailed context around specific blocks using get_block_context
        - Propose edits (additions or updates) to the user's notes using suggest_edit

        Guidelines:
        - Be concise and helpful. Reference the user's actual notes when answering.
        - When citing notes, mention the breadcrumb path so the user knows where the content is.
        - Only use suggest_edit when the user explicitly asks you to add, change, or write something.
        - Always search first before suggesting edits — never guess at block IDs.
        - If the user asks a general question unrelated to their notes, answer directly without using tools.
        - Keep responses focused and avoid unnecessary verbosity.
        """
}
