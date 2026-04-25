import Foundation

enum SearchUtilities {
    static let iso8601 = ISO8601DateFormatter()

    static func stableID(for value: String) -> UUID {
        var hash = FNV1a128()
        hash.update(value)
        return hash.uuid
    }

    static func contentHash(_ value: String) -> String {
        var hash = FNV1a128()
        hash.update(value)
        let uuid = hash.uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return uuid
    }

    static func relativePath(for fileURL: URL, in rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else {
            return fileURL.lastPathComponent
        }
        var relative = String(filePath.dropFirst(rootPath.count))
        if relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative
    }
}

private struct FNV1a128 {
    private var high: UInt64 = 0xcbf29ce484222325
    private var low: UInt64 = 0x84222325cbf29ce4

    mutating func update(_ string: String) {
        for byte in string.utf8 {
            high ^= UInt64(byte)
            high &*= 0x100000001b3
            low ^= UInt64(byte)
            low &*= 0x100000001b3
            low ^= high.rotateLeft(13)
        }
    }

    var uuid: UUID {
        var bytes: uuid_t = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
        bytes.0 = UInt8(truncatingIfNeeded: high >> 56)
        bytes.1 = UInt8(truncatingIfNeeded: high >> 48)
        bytes.2 = UInt8(truncatingIfNeeded: high >> 40)
        bytes.3 = UInt8(truncatingIfNeeded: high >> 32)
        bytes.4 = UInt8(truncatingIfNeeded: high >> 24)
        bytes.5 = UInt8(truncatingIfNeeded: high >> 16)
        bytes.6 = UInt8(truncatingIfNeeded: high >> 8)
        bytes.7 = UInt8(truncatingIfNeeded: high)
        bytes.8 = UInt8(truncatingIfNeeded: low >> 56)
        bytes.9 = UInt8(truncatingIfNeeded: low >> 48)
        bytes.10 = UInt8(truncatingIfNeeded: low >> 40)
        bytes.11 = UInt8(truncatingIfNeeded: low >> 32)
        bytes.12 = UInt8(truncatingIfNeeded: low >> 24)
        bytes.13 = UInt8(truncatingIfNeeded: low >> 16)
        bytes.14 = UInt8(truncatingIfNeeded: low >> 8)
        bytes.15 = UInt8(truncatingIfNeeded: low)
        return UUID(uuid: bytes)
    }
}

private extension UInt64 {
    func rotateLeft(_ shift: Int) -> UInt64 {
        (self << shift) | (self >> (64 - shift))
    }
}
