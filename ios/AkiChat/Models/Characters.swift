import Foundation

struct LoreEntry: Codable, Equatable, Identifiable {
    var id: Int
    var keys: [String]
    var secondaryKeys: [String]
    var content: String
    var enabled: Bool
    var constant: Bool
    var selective: Bool
    var caseSensitive: Bool
    var order: Int
    var position: String
    var supported: Bool
}
struct CharacterBook: Codable, Equatable {
    var name: String
    var entries: [LoreEntry]
    var rawJSON: Data
    var budget: Int
    var scanDepth: Int
}
struct CharacterFields: Codable, Equatable {
    var name: String
    var description: String
    var personality: String
    var scenario: String
    var firstMessage: String
    var examples: String
    var alternateGreetings: [String]
    var systemPrompt: String
    var postHistory: String
    var creatorNotes: String
    var tags: [String]
    var creator: String
    var version: String
    var extensionsJSON: Data
    var book: CharacterBook?
}
struct CharacterRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var spec: String
    var fields: CharacterFields
    var rawJSON: Data // Complete V2/V3 object, including unknown fields and asset references.
    var avatarJPEG: Data?
    var originalPNGAssetID: UUID?
    var importedAt = Date()
    var storageBytes: Int {
        let avatarBytes: Int = avatarJPEG?.count ?? 0
        return rawJSON.count + avatarBytes
    }
}
struct CharacterBinding: Codable, Equatable {
    var characterID: UUID
    var snapshot: CharacterRecord
    var greetingMessageID: UUID?
}
struct CharacterImport {
    var record: CharacterRecord
    var originalPNG: Data?
    var warnings: [String] = []
}

enum CharacterImportError: LocalizedError {
    case invalid, unsupported, missingMetadata, corrupt, limit(String)
    var errorDescription: String? {
        switch self {
        case .invalid: return "不是有效的角色卡：需要规范的 V2/V3 标识与完整基础字段。"
        case .unsupported: return "JSON 格式不受支持：本版支持 Character Card V2 2.0 和 V3 3.0，不将 V1 当作 V2。"
        case .missingMetadata: return "PNG 没有角色信息：请选择原始酒馆 PNG 文件，而不是重新保存的图片。"
        case .corrupt: return "角色卡数据损坏，无法安全读取。"
        case .limit(let reason): return "文件超过限制：" + reason
        }
    }
}
