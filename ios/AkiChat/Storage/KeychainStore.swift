import Foundation
import Security

enum KeychainStore {
    private static let service = "com.akisenn.akichat.keys"
    private static func query(_ reference: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: reference]
    }
    static func read(_ reference: String) throws -> String? {
        var query = self.query(reference)
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw AppError.storage("无法读取 Keychain（\(status)）")
        }
        return value
    }
    static func write(_ value: String, reference: String) throws {
        let query = self.query(reference)
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; attributes.forEach { item[$0.key] = $0.value }
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw AppError.storage("无法保存 Keychain（\(added)）") }
        } else if status != errSecSuccess { throw AppError.storage("无法更新 Keychain（\(status)）") }
    }
    static func delete(_ reference: String) throws {
        let status = SecItemDelete(query(reference) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppError.storage("无法删除 Keychain（\(status)）") }
    }
}
