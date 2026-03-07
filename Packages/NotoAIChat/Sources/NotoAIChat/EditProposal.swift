//
//  EditProposal.swift
//  NotoAIChat
//

import Foundation

/// A proposed set of edit operations with a human-readable summary.
public struct EditProposal: Codable, Sendable {
    public let operations: [EditOperation]
    public let summary: String

    public init(operations: [EditOperation], summary: String) {
        self.operations = operations
        self.summary = summary
    }
}
