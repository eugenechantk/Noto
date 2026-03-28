import Foundation

/// Operation type for dirty block tracking.
public enum DirtyOperation: String, Sendable {
    case upsert
    case delete
}
