//
//  EditStatus.swift
//  NotoAIChat
//

import Foundation

/// Status of a suggested edit proposal.
public enum EditStatus: String, Codable, Sendable {
    case pending
    case accepted
    case dismissed
}
