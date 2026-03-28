//
//  MetadataField.swift
//  NotoModels
//
//  Custom metadata fields attached to blocks.
//

import Foundation
import SwiftData

public enum MetadataType: String, Codable {
    case text
    case number
    case date
    case select
}

@Model
public final class MetadataField {
    @Attribute(.unique) public var id: UUID
    public var fieldName: String
    public var fieldValue: String
    public var fieldTypeRaw: String

    // Relationships
    public var block: Block?

    public var fieldType: MetadataType {
        get { MetadataType(rawValue: fieldTypeRaw) ?? .text }
        set { fieldTypeRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        block: Block,
        fieldName: String,
        fieldValue: String,
        fieldType: MetadataType = .text
    ) {
        self.id = id
        self.block = block
        self.fieldName = fieldName
        self.fieldValue = fieldValue
        self.fieldTypeRaw = fieldType.rawValue
    }
}
