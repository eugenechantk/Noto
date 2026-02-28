//
//  MetadataField.swift
//  Noto
//
//  Custom metadata fields attached to blocks.
//

import Foundation
import SwiftData

enum MetadataType: String, Codable {
    case text
    case number
    case date
    case select
}

@Model
final class MetadataField {
    @Attribute(.unique) var id: UUID
    var fieldName: String
    var fieldValue: String
    var fieldTypeRaw: String

    // Relationships
    var block: Block?

    var fieldType: MetadataType {
        get { MetadataType(rawValue: fieldTypeRaw) ?? .text }
        set { fieldTypeRaw = newValue.rawValue }
    }

    init(
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
