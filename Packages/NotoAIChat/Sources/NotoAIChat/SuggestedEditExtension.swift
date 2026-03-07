//
//  SuggestedEditExtension.swift
//  NotoAIChat
//

import Foundation

/// Extension data for a suggested edit block.
public struct SuggestedEditExtension: Codable, Sendable {
    public let role: ChatBlockRole
    public var proposal: EditProposal
    public var status: EditStatus

    public init(proposal: EditProposal, status: EditStatus = .pending) {
        self.role = .suggestedEdit
        self.proposal = proposal
        self.status = status
    }
}
