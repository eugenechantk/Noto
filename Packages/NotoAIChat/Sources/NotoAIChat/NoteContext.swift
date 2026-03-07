//
//  NoteContext.swift
//  NotoAIChat
//

import Foundation

/// Context about the note the user is currently viewing, passed to the system prompt.
public struct NoteContext: Sendable {
    public let title: String
    public let breadcrumb: String

    public init(title: String, breadcrumb: String) {
        self.title = title
        self.breadcrumb = breadcrumb
    }
}
