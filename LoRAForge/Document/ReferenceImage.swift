import Foundation
import CommonCrypto

struct ReferenceImage: Identifiable, Codable, Sendable {
    let id: UUID
    let filename: String
    let contentHash: String
    let addedAt: Date

    init(id: UUID = UUID(), filename: String, contentHash: String) {
        self.id = id
        self.filename = filename
        self.contentHash = contentHash
        self.addedAt = Date()
    }
}

enum ContentHasher {
    static func sha256(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
