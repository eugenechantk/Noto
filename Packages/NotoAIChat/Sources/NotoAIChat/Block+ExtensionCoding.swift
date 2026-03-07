//
//  Block+ExtensionCoding.swift
//  NotoAIChat
//

import Foundation
import NotoModels

extension Block {
    /// Decode this block's extensionData into a typed Codable struct.
    /// Returns nil if extensionData is nil or decoding fails.
    public func decodeExtension<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = extensionData else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Encode a Codable value into Data suitable for storing in extensionData.
    /// Returns nil if encoding fails.
    public static func encodeExtension<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }
}
